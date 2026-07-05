# Phase 4: 代表フロー — `httpx.get('https://example.com')` から Response 返却まで

★ **本スキルの最重要フェーズ**。ライブラリ向けアダプテーションに従い、「公開 API の代表呼び出し」を選定。

## シーケンス図 (Mermaid)

各矢印には呼び出し先の **ファイルパス:行 関数名** を併記する。
リダイレクトなし、認証なし (= `Auth()` ベース) の **happy path** をたどり、最後にエラーパスにも 1 本触れる。

```mermaid
sequenceDiagram
  autonumber
  participant U as User
  participant API as httpx._api
  participant C as Client (sync)
  participant BC as BaseClient
  participant REQ as Request
  participant AUTH as Auth.sync_auth_flow
  participant T as HTTPTransport
  participant HC as httpcore.ConnectionPool
  participant RESP as Response

  U->>API: httpx.get('https://example.com')
  Note over API: _api.py:174 get()
  API->>API: request('GET', url, ...)
  Note over API: _api.py:39 request()
  API->>C: with Client(...) as client
  Note over C: _client.py:639 Client.__init__()<br/>_client.py:718 _init_transport() → HTTPTransport(...)
  C->>T: HTTPTransport(...)
  Note over T: _transports/default.py:135 HTTPTransport.__init__()<br/>→ httpcore.ConnectionPool(...)  (line 156)
  API->>C: client.request('GET', url, ...)
  Note over C: _client.py:771 Client.request()
  C->>BC: build_request('GET', url, ...)
  Note over BC: _client.py:340 BaseClient.build_request()<br/>_merge_url / _merge_headers / _merge_cookies / _merge_queryparams
  BC->>REQ: Request(method, url, headers=..., extensions={timeout:..})
  Note over REQ: _models.py:382 Request.__init__()<br/>encode_request() で ByteStream を作り self.stream に格納
  REQ-->>BC: request
  BC-->>C: request

  C->>C: send(request, auth=USE_CLIENT_DEFAULT, follow_redirects=USE_CLIENT_DEFAULT)
  Note over C: _client.py:879 Client.send()<br/>_set_timeout(request)  (_client.py:584)
  C->>BC: _build_request_auth(request, auth)
  Note over BC: _client.py:457 → Auth() (no-auth) を返す
  BC-->>C: auth (Auth)

  C->>AUTH: _send_handling_auth(request, auth, follow_redirects, history=[])
  Note over C,AUTH: _client.py:930 _send_handling_auth()
  AUTH->>AUTH: auth_flow = auth.sync_auth_flow(request)
  Note over AUTH: _auth.py:62 Auth.sync_auth_flow()<br/>(no-auth は 1 回だけ yield して終わる)
  AUTH->>AUTH: request = next(auth_flow)

  C->>C: _send_handling_redirects(request, follow_redirects, history)
  Note over C: _client.py:964 _send_handling_redirects()<br/>event_hooks['request'] を順に呼ぶ
  C->>C: _send_single_request(request)
  Note over C: _client.py:1001 _send_single_request()<br/>transport = _transport_for_url(request.url)  (_client.py:760)
  C->>T: transport.handle_request(request)
  Note over T: _transports/default.py:230 HTTPTransport.handle_request()<br/>httpx.Request → httpcore.Request 変換 (line 237)
  T->>HC: self._pool.handle_request(httpcore_req)
  Note over HC: httpcore.ConnectionPool.handle_request()<br/>(外部ライブラリ: 接続プール / TLS / h11 によるバイト送受信)
  HC-->>T: httpcore.Response (status, headers, stream, extensions)
  Note over T: map_httpcore_exceptions() で例外を httpx 階層に再写像  (_transports/default.py:95)
  T->>RESP: Response(status_code, headers, stream=ResponseStream(...), extensions=...)
  Note over RESP: _models.py:515 Response.__init__()
  T-->>C: response (Response)
  C->>C: response.stream = BoundSyncStream(...)   ← elapsed 計測用
  Note over C: _client.py:1019, _client.py:139 BoundSyncStream
  C->>C: cookies.extract_cookies(response)
  Note over C: _client.py:1022 (Set-Cookie 取り込み)
  C->>C: logger.info('HTTP Request: ...')
  Note over C: _client.py:1025 (ロギング)
  C-->>C: response (戻る — has_redirect_location なら ループ)
  C-->>AUTH: response
  AUTH->>AUTH: try next_request = auth_flow.send(response)<br/>StopIteration なら return response
  AUTH-->>C: response

  C->>RESP: if not stream: response.read()
  Note over RESP: _models.py:876 Response.read() → iter_bytes() → デコーダ経由でバイト連結  (_decoders.py)
  RESP-->>C: bytes (self._content にキャッシュ)
  C-->>API: response
  API->>C: __exit__()  →  client.close() → transport.close() → pool.close()
  Note over C: _client.py:1263, 1293; _transports/default.py:261; httpcore 側で keep-alive 切断
  API-->>U: Response (status_code=200, content=...)
```

## 矢印ごとの根拠 (ファイルパス:行 関数名)

| # | 呼び出し | 場所 |
|---|---|---|
| 1 | `httpx.get(...)` | `httpx/_api.py:174` `get()` |
| 2 | `_api.get` が `_api.request` に委譲 | `httpx/_api.py:195` `request('GET', url, ...)` |
| 3 | `_api.request` が一時 `Client` を生成 | `httpx/_api.py:102` `with Client(...) as client` |
| 4 | `Client.__init__` → `_init_transport` → `HTTPTransport(...)` | `httpx/_client.py:639` `Client.__init__`, `httpx/_client.py:718` `_init_transport`, `httpx/_client.py:731` `return HTTPTransport(...)` |
| 5 | `HTTPTransport.__init__` が `httpcore.ConnectionPool` を生成 | `httpx/_transports/default.py:135` `HTTPTransport.__init__`, `httpx/_transports/default.py:156` `self._pool = httpcore.ConnectionPool(...)` |
| 6 | `client.request(...)` | `httpx/_client.py:771` `Client.request` |
| 7 | `build_request` | `httpx/_client.py:340` `BaseClient.build_request` |
| 8 | URL / headers / cookies / params のマージ | `httpx/_client.py:391` `_merge_url`, `:413` `_merge_cookies`, `:424` `_merge_headers`, `:433` `_merge_queryparams` |
| 9 | `Request(...)` 構築 — bodyエンコード | `httpx/_models.py:382` `Request.__init__`, `httpx/_models.py:408` `encode_request(...)` |
| 10 | `Client.send(request, ...)` | `httpx/_client.py:879` `Client.send` |
| 11 | `_set_timeout` で `request.extensions['timeout']` を埋める | `httpx/_client.py:584` `BaseClient._set_timeout` |
| 12 | `_build_request_auth` (auth 未指定なら `Auth()`) | `httpx/_client.py:457` `BaseClient._build_request_auth` |
| 13 | `_send_handling_auth` — auth_flow ジェネレータをドライブ | `httpx/_client.py:930` `Client._send_handling_auth` |
| 14 | `Auth.sync_auth_flow` 呼び出し | `httpx/_auth.py:62` `Auth.sync_auth_flow` |
| 15 | `_send_handling_redirects` — `event_hooks['request']` 実行 | `httpx/_client.py:964` `Client._send_handling_redirects`, `httpx/_client.py:976` `for hook in self._event_hooks['request']` |
| 16 | `_send_single_request` | `httpx/_client.py:1001` `Client._send_single_request` |
| 17 | URL → トランスポート選択 (mounts 走査) | `httpx/_client.py:760` `Client._transport_for_url`, `httpx/_client.py:765-769` `for pattern, transport in self._mounts.items()` |
| 18 | `transport.handle_request(request)` | `httpx/_transports/default.py:230` `HTTPTransport.handle_request` |
| 19 | `httpx.Request` → `httpcore.Request` 変換 | `httpx/_transports/default.py:237-248` (`httpcore.Request(method=.., url=httpcore.URL(...), headers=..., content=request.stream, extensions=...)`) |
| 20 | `self._pool.handle_request(req)` で `httpcore.ConnectionPool` を叩く | `httpx/_transports/default.py:250` (`with map_httpcore_exceptions(): resp = self._pool.handle_request(req)`) |
| 21 | 例外マッピング | `httpx/_transports/default.py:95` `map_httpcore_exceptions()`, `httpx/_transports/default.py:74` `_load_httpcore_exceptions()` |
| 22 | `httpcore.Response` → `httpx.Response` 再構築 | `httpx/_transports/default.py:254-259` `Response(status_code=resp.status, headers=resp.headers, stream=ResponseStream(resp.stream), extensions=resp.extensions)` |
| 23 | `Response.__init__` | `httpx/_models.py:515` `Response.__init__` |
| 24 | `BoundSyncStream` で elapsed 計測ストリームに差し替え | `httpx/_client.py:1019` (`response.stream = BoundSyncStream(...)`), `httpx/_client.py:139` `class BoundSyncStream` |
| 25 | クッキー回収 | `httpx/_client.py:1022` `self.cookies.extract_cookies(response)`, `httpx/_models.py:1079` `class Cookies` |
| 26 | ロギング | `httpx/_client.py:1025-1032` `logger.info('HTTP Request: ...')` |
| 27 | `response.has_redirect_location` を見てリダイレクトループ判定 | `httpx/_client.py:985` |
| 28 | auth_flow へ `response` を送り返す | `httpx/_client.py:949` `next_request = auth_flow.send(response)` |
| 29 | `Client.send` の最後で `response.read()` (stream=False のとき) | `httpx/_client.py:921-922` `if not stream: response.read()` |
| 30 | `Response.read()` 本体 | `httpx/_models.py:876` `Response.read` → `:884` `iter_bytes()` |
| 31 | `Client.__exit__` → `close` → `_transport.close` → `_pool.close` | `httpx/_client.py:1293` `__exit__`, `:1263` `close()`, `_transports/default.py:261` `HTTPTransport.close` |

## 同期/非同期の対称関係

`AsyncClient` (`httpx/_client.py:1307`) は名前を `async_` / `a` 付きに変えた **完全対称版**。
代表対応:
- `Client.send` ⇔ `AsyncClient.send` (`_client.py` 後半に同名で存在)
- `_send_single_request` も同じ位置に存在し、`transport.handle_async_request()` (`_transports/base.py:77`) を呼ぶ
- `HTTPTransport.handle_request` ⇔ `AsyncHTTPTransport.handle_async_request` (`_transports/default.py:374`)
- `httpcore.ConnectionPool` ⇔ `httpcore.AsyncConnectionPool` (`_transports/default.py:300`)

つまり「ストリーム抽象 (`SyncByteStream` ↔ `AsyncByteStream`) と transport 抽象 (`BaseTransport` ↔ `AsyncBaseTransport`) を切替えただけで、フローの形は同じ」。

## エラーパス (1 本だけ)

接続失敗の場合:
1. `httpcore.ConnectionPool.handle_request` が `httpcore.ConnectError` を送出
2. `HTTPTransport.handle_request` 内の `with map_httpcore_exceptions():` で捕捉 (`_transports/default.py:249`)
3. `_load_httpcore_exceptions()` のマップ表 (`_transports/default.py:74-92`) で `httpcore.ConnectError → httpx.ConnectError` に再 raise (`_transports/default.py:118` `raise mapped_exc(message) from exc`)
4. 呼び出し元の `Client._send_single_request` には `httpx.ConnectError` (= `TransportError` の子) が伝搬
5. `Client._send_handling_redirects` 〜 `_send_handling_auth` は `try/except BaseException` で **response.close() を実行** してから再 raise (`_client.py:997-999`, `:958-960`)
6. 最終的に `with Client(...) as client:` の `__exit__` で `pool.__exit__` も呼ばれる (`_transports/default.py:221`)
7. ユーザーには `httpx.ConnectError` (`__cause__` に元 `httpcore.ConnectError`) が返る

## 終了条件

ユーザーがこの図を見て、コードを開かずに **各矢印にあたる関数名/ファイル位置** を言える。
たとえば「`map_httpcore_exceptions` はどこ?」→ `_transports/default.py:95` を即答できる。
