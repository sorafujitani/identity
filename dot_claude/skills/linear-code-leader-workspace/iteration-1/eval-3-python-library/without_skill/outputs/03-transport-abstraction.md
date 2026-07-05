# Transport 抽象と 4 つの実装

## 抽象 — `_transports/base.py`

たった 86 行。実質これだけ:

```python
class BaseTransport:
    def __enter__(self): return self
    def __exit__(self, *exc): self.close()
    def handle_request(self, request: Request) -> Response:
        raise NotImplementedError
    def close(self) -> None: pass

class AsyncBaseTransport:
    async def __aenter__(self): return self
    async def __aexit__(self, *exc): await self.aclose()
    async def handle_async_request(self, request: Request) -> Response:
        raise NotImplementedError
    async def aclose(self) -> None: pass
```

**契約は「`Request` を受け取って `Response` を返す」だけ**。
リダイレクト・Auth・Cookie・Timeout などはすべて Client 側の責務で、Transport はピュアに 1 リクエスト/1 レスポンス。

これが httpx の testability の核 — Transport さえ満たせば、ソケットを開かずに任意のスタブが書ける。

## ① `HTTPTransport` / `AsyncHTTPTransport` (default.py)

実プロダクションで使う既定の transport。中身は **httpcore のラッパ**。

### `__init__` で何をしているか (135-216)

引数で `proxy` の有無・スキーム (http/https/socks5) を見て、**3 種類の httpcore プールのうちひとつ**をインスタンス化:

```python
if proxy is None:
    self._pool = httpcore.ConnectionPool(...)
elif proxy.url.scheme in ("http", "https"):
    self._pool = httpcore.HTTPProxy(...)
elif proxy.url.scheme in ("socks5", "socks5h"):
    import socksio                  # extras [socks] が要る
    self._pool = httpcore.SOCKSProxy(...)
```

`ssl_context` は `_config.create_ssl_context(verify, cert, trust_env)` で certifi の CA バンドルから組み立て。
`Limits` は **httpcore に渡すコネクション上限の構造体** — `max_connections=100, max_keepalive_connections=20, keepalive_expiry=5.0` がデフォルト (`_config.py`)。

### `handle_request` で何をしているか (230-259)

すでに `02-call-path-public-to-transport.md` ⑩ で書いた通り、**詰め替えのみ**。

注目すべき設計判断:
- **`request.stream` をそのまま `httpcore.Request(content=...)` に渡す** → リクエストボディは遅延 (chunked) 送出が可能
- **レスポンス bytes も `ResponseStream` で wrapping し iter で yield する** → ストリーミングダウンロードが可能
- 例外は `map_httpcore_exceptions` (95-118) で `httpcore.X` → `httpx.X` にマップ。`HTTPCORE_EXC_MAP` (74-92) は遅延初期化される (httpcore を import するコストを最小化するため)

### キャッシュコメント (default.py:1-25)

httpcore 固有の引数 (`uds` (Unix Domain Socket), `local_address`, `retries`, `socket_options`) はそのまま受け取ってプールに転送。
**httpx に直接の HTTP/2 実装は無く、`http2=True` は httpcore + `h2` パッケージで実現**。

## ② `MockTransport` (mock.py, 43 行)

```python
class MockTransport(AsyncBaseTransport, BaseTransport):
    def __init__(self, handler: SyncHandler | AsyncHandler):
        self.handler = handler

    def handle_request(self, request: Request) -> Response:
        request.read()
        return self.handler(request)

    async def handle_async_request(self, request: Request) -> Response:
        await request.aread()
        response = self.handler(request)
        if not isinstance(response, Response):
            response = await response
        return response
```

**多重継承で sync/async 両対応**。テストで:

```python
def handler(request): return httpx.Response(200, json={"ok": True})
client = httpx.Client(transport=httpx.MockTransport(handler))
```

httpx 自身のテストスイート (`tests/`) も多用している。`request.read()` を内部で呼ぶので、ハンドラ側で `request.content` を素直に触れる。

## ③ `ASGITransport` (asgi.py, 187 行)

FastAPI/Starlette などの ASGI app を **in-process** で叩くための async transport。
ソケットを開かない。

中身は本物の ASGI server (uvicorn/hypercorn) と同じプロトコルを忠実に再現:

1. `scope` dict を組む (`type: "http"`, method, headers, path, query_string, scheme, server, client, root_path)
2. `receive()` / `send()` callable を作って `await self.app(scope, receive, send)` を呼ぶ
3. `send` で渡ってきた `http.response.start` から `status_code` と `headers` を取り、`http.response.body` を `body_parts` に積む
4. 完了したら `Response(status_code, headers=..., stream=ASGIResponseStream(body_parts))` を返す

trio/asyncio 両対応のため `create_event()` (44-52) で `sniffio` を使って動的に分岐。
これは httpx のドキュメントでも紹介されるテストパターンだが、本番でも「同一プロセスでマイクロサービスを呼ぶ」用途で実用可能。

## ④ `WSGITransport` (wsgi.py, 149 行)

Flask/Django などの WSGI app 用の sync transport。
こちらは `environ` dict を組み立てて `self.app(environ, start_response)` を直接呼ぶ。

ポイント:
- `start_response` クロージャ内で `nonlocal seen_status, seen_response_headers, seen_exc_info` を捕捉 (WSGI 仕様準拠)
- `wsgi.input` には `io.BytesIO(request.content)` を渡す (= リクエストボディは一度全部メモリ化される)
- ヘッダ名は `HTTP_` プレフィックス + 大文字 + ハイフン→アンダースコア変換、ただし `CONTENT_TYPE` / `CONTENT_LENGTH` は例外 — これは PEP 3333 そのまま

## 4 実装の比較表

| | HTTPTransport | MockTransport | ASGITransport | WSGITransport |
| --- | --- | --- | --- | --- |
| ファイル | default.py | mock.py | asgi.py | wsgi.py |
| sync/async | 両方 (別クラス) | **両方 (多重継承)** | async のみ | sync のみ |
| 実ソケット | ◯ (httpcore) | × | × | × |
| 主用途 | 本番 | テスト | ASGI app テスト | WSGI app テスト |
| 行数 | 406 | 43 | 187 | 149 |
| プロトコル | HTTP/1.1, HTTP/2 (extras) | n/a | ASGI 3.0 | PEP 3333 |
| プロキシ | HTTP, HTTPS, SOCKS5 | — | — | — |

## mounts による振り分け

`Client(mounts=...)` を渡すと URL パターンごとに transport を切り替えられる:

```python
client = httpx.Client(mounts={
    "https://api.example.com": httpx.HTTPTransport(http2=True),
    "http://": httpx.HTTPTransport(verify=False),
    "all://*.test": httpx.MockTransport(test_handler),
})
```

実体は `Client.__init__` で `dict[URLPattern, BaseTransport]` を作って `sorted` し、`_send_single_request` から `_transport_for_url` (`_client.py:760-769`) で **上から順に `URLPattern.matches(url)` を試す** だけ。マッチしなければ既定の `self._transport`。

`URLPattern` (`_utils.py:120-209`) は `"all://"`, `"https://"`, `"https://*.example.com:1234"` のような表記をスキーム/ホスト/ポートに分解して、ホストは `re.compile()` で正規表現化。`priority` プロパティでソートして「最も具体的なパターン」が先に当たるようにしてある。
