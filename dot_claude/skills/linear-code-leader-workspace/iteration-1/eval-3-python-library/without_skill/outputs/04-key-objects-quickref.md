# 主要オブジェクト クイックリファレンス

公開 API → トランスポートの経路を追っているときに「これ何だっけ」となりがちなオブジェクトをまとめておく。

## `Request` (`_models.py:382-512`)

```python
class Request:
    method: str                                # 常に upper()
    url: URL
    headers: Headers
    stream: SyncByteStream | AsyncByteStream    # ボディ (遅延)
    extensions: dict                            # transport 向けメタ (timeout 等)
    # content / data / files / json から build される
```

設計のキモ:
- **コンストラクタで content/data/files/json のどれかを受け取り、`encode_request()` でボディ bytes + auto headers (Content-Type, Content-Length, Host) を生成** (`_models.py:407-419`)
- `stream` は `ByteStream`(bytes 1 発) / `IteratorByteStream` (sync iter) / `MultipartStream` などの sub-class
- `extensions["timeout"] = {"connect": 5.0, "read": 5.0, ...}` のように **transport へ追加情報を渡す箱** が `extensions`。これは httpcore と共通の規約

## `Response` (`_models.py:515-1070`)

主な API:

| メソッド/プロパティ | 役割 |
| --- | --- |
| `status_code`, `headers`, `url`, `request` | 基本属性 |
| `content` | 全 bytes (read 済みでなければ `ResponseNotRead`) |
| `text` | デコード済み str (`encoding` プロパティで charset 解決) |
| `json()` | `json.loads(self.content)` |
| `read()` / `aread()` | ボディを全部読み、`_content` に格納 |
| `iter_bytes(chunk_size)` | decoded bytes イテレータ (gzip/brotli/zstd 透過) |
| `iter_raw(chunk_size)` | raw bytes イテレータ (圧縮そのまま) |
| `iter_text()` / `iter_lines()` | text/line イテレータ |
| `close()` / `aclose()` | ストリーム解放 |
| `elapsed` | `Client.send()` 経由のとき `BoundSyncStream` が closure で計測して setter |
| `history` | リダイレクトの履歴 |
| `next_request` | `follow_redirects=False` のとき次の Request を保持 |
| `has_redirect_location` | 3xx かつ Location ヘッダがある |

`iter_bytes` → `iter_raw` → `self.stream` (= transport が返した raw stream) という三段重ねで、**最終的に `httpcore.Response.stream` (HTTPTransport の場合) を消費する**。
レスポンスを全部読まずに捨てると httpcore 側のコネクションが返却されないので、`Client.send(stream=False)` の通常パスでは末尾で `response.read()` が呼ばれている。

## `Auth` (`_auth.py:22-110`)

```python
class Auth:
    requires_request_body = False
    requires_response_body = False

    def auth_flow(self, request: Request) -> Generator[Request, Response, None]:
        yield request
```

**ジェネレータベース**。クライアントはこう使う:

```python
flow = auth.sync_auth_flow(request)
request = next(flow)
while True:
    response = ...send request...
    try: next_request = flow.send(response)
    except StopIteration: break
```

サブクラス:
- `BasicAuth` (126) — `Authorization: Basic <b64>` を 1 回 yield して終わり
- `DigestAuth` (175) — 最初に request を yield。401 を受けたら nonce/qop/algorithm をパースし、digest 計算した新 request を yield して終わり
- `FunctionAuth` — `Client(auth=lambda req: req.headers["X-Token"] = "...")` の薄いラッパ
- `NetRCAuth` — `~/.netrc` を参照して BasicAuth を組む

async でも `async_auth_flow` をオーバライドできるが、ほとんどの場合は同期 `auth_flow` で十分 (内側で I/O しないなら)。

## `URL` (`_urls.py:15-`)

requests の `URL` よりずっとリッチで **immutable**:

```python
url = URL("https://user:pass@example.com:443/path?q=1#frag")
url.scheme      # "https"
url.host        # "example.com"
url.port        # 443
url.raw_path    # b"/path?q=1"  (transport に渡すのはこっち)
url.params      # QueryParams({"q": "1"})
url.copy_with(path="/other")    # 新インスタンス
url.join("/relative")           # 新インスタンス
```

httpcore に渡すときは `URL(scheme=..., host=..., port=..., target=...)` という別表現に組み替える (default.py:239-244)。
これは httpcore が「**bytes ベースで scheme/host/port/target を別個に持つ**」設計のため。

## `Headers` / `Cookies` / `QueryParams`

- `Headers` (`_models.py:139`) — `MutableMapping[str, str]` だが内部は `list[tuple[bytes, bytes]]` ですべて bytes 保持、case-insensitive。`.raw` で list of tuples を取れる
- `Cookies` (`_models.py:1079`) — Python 標準 `http.cookiejar.CookieJar` のラッパ。`Client` がレスポンス毎に `extract_cookies(response)` で更新
- `QueryParams` (`_urls.py`) — immutable, `merge(other)` / `add(key, value)` で新インスタンス

## `URLPattern` (`_utils.py:120-209`)

`mounts={"all://*.example.com": MyTransport()}` の鍵。
コンストラクタで scheme/host/port/host_regex を分解。
`matches(url)` で URL とマッチング。
`priority` プロパティでソートできるので **最も具体的なパターンが最優先**。

## `Limits` / `Timeout` / `Proxy` (`_config.py`)

```python
Limits(max_connections=100, max_keepalive_connections=20, keepalive_expiry=5.0)
Timeout(5.0)
Timeout(None, connect=5.0)               # connect のみ 5s、他は無制限
Timeout(5.0, connect=10.0)               # connect 10s、他 5s
Proxy(url="http://proxy:8080", auth=("user", "pass"))
```

`Timeout.as_dict()` は `{"connect": ..., "read": ..., "write": ..., "pool": ...}` を返し、**`request.extensions["timeout"]` 経由で httpcore へ伝達** される。
httpcore はこの dict を見て各段階のソケット I/O にタイムアウトを掛ける。

## `BoundSyncStream` / `BoundAsyncStream` (`_client.py:139-182`)

`Client._send_single_request` が `transport.handle_request()` のレスポンスストリームを **これでラップ**:

```python
response.stream = BoundSyncStream(response.stream, response=response, start=start)
```

`close()` のときに `response.elapsed` を `time.perf_counter() - start` で計算してセット。
これにより `Response.elapsed` が「リクエスト開始からストリーム消費完了まで」を表すようになる。Transport 側からは elapsed は見えない (関心分離)。

## 例外階層 (`_exceptions.py`)

```
Exception
└── HTTPError
    ├── RequestError                # network/timeout/cookie 等
    │   ├── TransportError
    │   │   ├── TimeoutException
    │   │   │   ├── ConnectTimeout
    │   │   │   ├── ReadTimeout
    │   │   │   ├── WriteTimeout
    │   │   │   └── PoolTimeout
    │   │   ├── NetworkError
    │   │   │   ├── ConnectError
    │   │   │   ├── ReadError
    │   │   │   ├── WriteError
    │   │   │   └── CloseError
    │   │   ├── ProtocolError ─→ LocalProtocolError / RemoteProtocolError
    │   │   ├── ProxyError
    │   │   └── UnsupportedProtocol
    │   ├── DecodingError
    │   ├── TooManyRedirects
    │   └── (Stream系) StreamError → StreamConsumed / StreamClosed / ResponseNotRead / RequestNotRead
    ├── HTTPStatusError              # response.raise_for_status() が投げる
    └── InvalidURL / CookieConflict
```

`map_httpcore_exceptions` (`default.py:95-118`) が `httpcore.X` を `httpx.X` に変換する箇所をまず読むと、httpx と httpcore の責任分界がよく分かる。
