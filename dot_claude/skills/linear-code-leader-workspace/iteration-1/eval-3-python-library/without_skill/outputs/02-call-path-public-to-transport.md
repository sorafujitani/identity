# `httpx.get(url)` → ソケットまでの呼び出しトレース

ここが「半日で掴みたい一番のもの」。コード行と一緒に追います。

## Sync 経路 (1 リクエストで follow_redirects=False のシンプル経路)

### ① ユーザコード

```python
import httpx
r = httpx.get("https://example.org")
```

### ② `httpx/_api.py:174-207` — `get()`

```python
def get(url, *, params=None, headers=None, ...) -> Response:
    return request("GET", url, params=params, headers=headers, ...)
```

### ③ `httpx/_api.py:39-120` — `request()`

```python
def request(method, url, *, ...) -> Response:
    with Client(
        cookies=cookies, proxy=proxy, verify=verify,
        timeout=timeout, trust_env=trust_env,
    ) as client:
        return client.request(method=method, url=url, ...)
```

**ポイント**: モジュール関数は毎回 `Client` を作って捨てる。
コネクションプールは使い回されないので、**繰り返し叩くなら `with httpx.Client() as c:` を自前で持つべき** という指針はここから来ている。
`with` ブロックを抜けると `Client.__exit__` → `transport.close()` → `httpcore.ConnectionPool.close()` で全ソケットが閉じる。

### ④ `httpx/_client.py:771-825` — `Client.request()`

```python
def request(self, method, url, *, ...) -> Response:
    request = self.build_request(method=method, url=url, ...)
    return self.send(request, auth=auth, follow_redirects=follow_redirects)
```

ここで「URL/Headers/Cookies/Params のマージ + `Request` オブジェクトの構築」が完了する。

### ⑤ `httpx/_client.py:340-389` — `BaseClient.build_request()`

```python
url = self._merge_url(url)              # base_url とくっつける
headers = self._merge_headers(headers)  # client.headers + per-call headers
cookies = self._merge_cookies(cookies)
params = self._merge_queryparams(params)
extensions = dict(**extensions, timeout=timeout.as_dict())
return Request(method, url, content=..., headers=..., extensions=extensions)
```

`Request.__init__` (`_models.py:382`) で content/data/files/json から **ボディ bytes と Content-Type/Content-Length を計算**し、`self.stream: SyncByteStream | AsyncByteStream` が確定する。

### ⑥ `httpx/_client.py:879-928` — `Client.send()`

```python
self._set_timeout(request)
auth = self._build_request_auth(request, auth)   # Auth flow ジェネレータの素

response = self._send_handling_auth(...)
if not stream:
    response.read()                # gzip/brotli/zstd デコードしながら全部読む
return response
```

### ⑦ `_send_handling_auth` (930-962) — Auth ジェネレータループ

```python
auth_flow = auth.sync_auth_flow(request)
request = next(auth_flow)              # 最初の Authorization header 付き request
while True:
    response = self._send_handling_redirects(request, ...)
    try:
        next_request = auth_flow.send(response)  # 401 -> challenge 応答, など
    except StopIteration:
        return response
    request = next_request
```

`Auth.sync_auth_flow` はジェネレータ。`yield request` で「これ送って」、その `yield` の戻り値が `response`。
これで DigestAuth みたいな **「最初に 401 を受けて nonce を取得して再送」** のフローが綺麗に書ける (`_auth.py:175` 以降)。

### ⑧ `_send_handling_redirects` (964-999) — リダイレクトループ + event hooks

```python
while True:
    if len(history) > self.max_redirects: raise TooManyRedirects(...)
    for hook in self._event_hooks["request"]: hook(request)

    response = self._send_single_request(request)
    for hook in self._event_hooks["response"]: hook(response)

    if not response.has_redirect_location: return response
    request = self._build_redirect_request(request, response)
    if follow_redirects:
        response.read()
    else:
        response.next_request = request
        return response
```

`event_hooks` がここに刺さる。リダイレクト時の Authorization 剥がし、Host 書き換え、Cookie 再計算は `_build_redirect_request` → `_redirect_headers` (524-571) で。

### ⑨ `_send_single_request` (1001-1034) — **transport 選択の境界**

```python
def _send_single_request(self, request: Request) -> Response:
    transport = self._transport_for_url(request.url)   # ← mounts ルックアップ
    start = time.perf_counter()

    with request_context(request=request):
        response = transport.handle_request(request)   # ← Transport 境界!

    response.request = request
    response.stream = BoundSyncStream(response.stream, response, start)
    self.cookies.extract_cookies(response)
    response.default_encoding = self._default_encoding
    return response
```

ここが **「httpx の公開 API 側」と「Transport 側」の最後の接点**。
`_transport_for_url` (760-769) は `self._mounts: dict[URLPattern, BaseTransport]` を上から順に見てマッチしたものを返す、なければ既定の `self._transport` を返す。

### ⑩ `httpx/_transports/default.py:230-259` — `HTTPTransport.handle_request()`

```python
def handle_request(self, request: Request) -> Response:
    import httpcore
    req = httpcore.Request(
        method=request.method,
        url=httpcore.URL(scheme=..., host=..., port=..., target=...),
        headers=request.headers.raw,
        content=request.stream,
        extensions=request.extensions,
    )
    with map_httpcore_exceptions():
        resp = self._pool.handle_request(req)        # ← httpcore へ!
    return Response(
        status_code=resp.status,
        headers=resp.headers,
        stream=ResponseStream(resp.stream),
        extensions=resp.extensions,
    )
```

**ここで httpx は httpcore に処理を完全に委譲する。** 仕事は 3 つだけ:

1. `httpx.Request` → `httpcore.Request` への詰め替え (URL を分解してまた組み立て直す)
2. `self._pool.handle_request()` を呼ぶ (`_pool` は `httpcore.ConnectionPool`、`__init__` で確定)
3. `httpcore.Response` → `httpx.Response` への詰め替え + 例外を `map_httpcore_exceptions` で `httpx.*` 例外にリマップ

ソケット I/O・TLS ハンドシェイク・HTTP/2 フレーミング・コネクション再利用・keepalive は **すべて httpcore 側**。httpx のソースには `socket.socket()` も `ssl.wrap_socket()` も登場しない。

## Async 経路 (sync と完全に対称)

| sync | async |
| --- | --- |
| `Client.request` | `AsyncClient.request` |
| `Client.send` (`_client.py:879`) | `AsyncClient.send` (`_client.py:1594`) |
| `_send_handling_auth` | `_send_handling_auth` (1645) |
| `_send_handling_redirects` | `_send_handling_redirects` (1679) |
| `_send_single_request` | `_send_single_request` (1717) |
| `HTTPTransport.handle_request` | `AsyncHTTPTransport.handle_async_request` |
| `httpcore.ConnectionPool` | `httpcore.AsyncConnectionPool` |

唯一の構造差は **Auth flow が `async generator` になり `await flow.asend(response)`** になる点 (`_auth.py` の `async_auth_flow`)。

## まとめ — 一枚絵

```
httpx.get
  → _api.request                       (_api.py)
    → with Client() as c
      → c.request                      (_client.py:771)
        → c.build_request → Request    (_client.py:340 / _models.py:382)
        → c.send                       (_client.py:879)
          → _send_handling_auth        (auth ジェネレータループ)
            → _send_handling_redirects (リダイレクト + event hooks)
              → _send_single_request
                → _transport_for_url   (URLPattern マッチで mounts ルックアップ)
                → transport.handle_request   ← ★Transport 境界★
                  ─── HTTPTransport の場合 ───
                  → httpcore.Request 詰め直し
                  → self._pool.handle_request    ← httpcore へ委譲
                    → ソケット I/O / TLS / HTTP/1.1 or HTTP/2
                  → httpcore.Response → httpx.Response 詰め直し
                  → map_httpcore_exceptions で例外リマップ
              ← Response
            ← Response (redirect なら再ループ)
          ← Response (auth flow に send-back、終わったら return)
        ← Response (stream=False なら response.read() で全部読む)
      ← Response
    ← c.__exit__ → transport.close → pool.close
  ← Response
```

行番号は master @ depth=1 時点 (`wc -l _client.py = 2019`)。リファクタで多少ずれることはあるが、関数名で grep すれば追える。
