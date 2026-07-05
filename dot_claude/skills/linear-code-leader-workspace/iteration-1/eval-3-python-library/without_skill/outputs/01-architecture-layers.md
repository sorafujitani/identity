# httpx のレイヤ構造

## 4 レイヤで把握する

```
┌────────────────────────────────────────────────────────────────┐
│ L1: 関数 API                                                    │
│   httpx.get / post / put / patch / delete / request / stream    │
│   (_api.py)                                                      │
│   → 毎回 with Client(...) を作って client.request() に委譲      │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌────────────────────────────────────────────────────────────────┐
│ L2: Client / AsyncClient (オーケストレーション層)                │
│   (_client.py — 2019 行、ここが本体)                             │
│   • build_request() : URL/Headers/Cookies/Params をマージし       │
│     Request を生成                                                │
│   • send() : Auth flow → redirect ループ → 単発リクエスト         │
│   • _transport_for_url() : mounts (URLPattern) で transport 選択 │
│   • event_hooks, cookies の永続化, base_url, timeout 既定値        │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼ transport.handle_request(request)
┌────────────────────────────────────────────────────────────────┐
│ L3: Transport 抽象                                                │
│   (_transports/base.py — BaseTransport / AsyncBaseTransport)     │
│   • handle_request(Request) -> Response という 1 メソッド契約    │
│   実装は 4 つ:                                                    │
│     • HTTPTransport / AsyncHTTPTransport (default.py) ← 既定      │
│     • MockTransport          (mock.py)                            │
│     • WSGITransport          (wsgi.py)                            │
│     • ASGITransport          (asgi.py)                            │
└────────────────────────────────────────────────────────────────┘
                              │
                              ▼ (default 経路のみ)
┌────────────────────────────────────────────────────────────────┐
│ L4: httpcore (別パッケージ)                                       │
│   httpcore.ConnectionPool / AsyncConnectionPool                  │
│   HTTPProxy / SOCKSProxy                                          │
│   ── ここで実際にソケットを開き、HTTP/1.1 or HTTP/2 を喋る ──     │
└────────────────────────────────────────────────────────────────┘
```

## モジュール対応表

| ファイル | 役割 | サイズ |
| --- | --- | --- |
| `httpx/__init__.py` | 全 public 名を `httpx.*` に再エクスポート、`__module__` を上書きして traceback を綺麗に | 106 |
| `httpx/_api.py` | モジュール関数 (`get` 等)。実装は `with Client(...) as c: c.request(...)` の薄ラッパ | 438 |
| `httpx/_client.py` | `BaseClient` / `Client` / `AsyncClient` 。**httpx の中枢**。リダイレクト/Auth/event hooks/cookies/mounts | 2019 |
| `httpx/_transports/base.py` | `BaseTransport` / `AsyncBaseTransport` ABC (sync = `handle_request`, async = `handle_async_request`) | 86 |
| `httpx/_transports/default.py` | `HTTPTransport` / `AsyncHTTPTransport`。httpcore に処理を渡すアダプタ + 例外マッピング | 406 |
| `httpx/_transports/mock.py` | `MockTransport`: テスト用、関数 `(Request) -> Response` を取って即返す | 43 |
| `httpx/_transports/asgi.py` | `ASGITransport`: in-process で ASGI app を叩く (FastAPI/Starlette のテスト用途) | 187 |
| `httpx/_transports/wsgi.py` | `WSGITransport`: 同じく WSGI app 用 (Flask/Django) | 149 |
| `httpx/_models.py` | `Request` / `Response` / `Headers` / `Cookies` 等のデータモデル | 1277 |
| `httpx/_urls.py` | `URL` / `QueryParams` (RFC3986 準拠の不変オブジェクト) | 641 |
| `httpx/_urlparse.py` | URL の低レベル parser | 527 |
| `httpx/_auth.py` | `Auth` (基底, ジェネレータ流) / `BasicAuth` / `DigestAuth` / `NetRCAuth` / `FunctionAuth` | 348 |
| `httpx/_config.py` | `Timeout` / `Limits` / `Proxy` / `create_ssl_context` | 248 |
| `httpx/_content.py` | `ByteStream` / `IteratorByteStream` 等、リクエスト/レスポンスの bytes 表現 | 240 |
| `httpx/_multipart.py` | multipart/form-data エンコーダ | 300 |
| `httpx/_decoders.py` | gzip/deflate/brotli/zstd ストリーミングデコーダ | 393 |
| `httpx/_exceptions.py` | 例外階層 (HTTPError → RequestError/HTTPStatusError → TransportError → 各種) | 377 |
| `httpx/_utils.py` | `URLPattern` (mounts のマッチング), env proxy 取得 等 | 242 |
| `httpx/_types.py` | type alias と `SyncByteStream`/`AsyncByteStream` ABC | 114 |
| `httpx/_status_codes.py` | `codes.OK` 等の HTTP ステータスコード enum | 162 |
| `httpx/_main.py` | `httpx` CLI (rich/click 依存) | 506 |

## 「依存方向」のメンタルモデル

- `_api.py` → `_client.py` → (`_transports/*`, `_models.py`, `_auth.py`, `_config.py`)
- `_transports/default.py` → `httpcore` (外部)
- `_transports/asgi.py`, `_transports/wsgi.py` → 内製 (`Request` / `Response` だけ参照、httpcore は触らない)
- `_models.py` → `_urls.py`, `_content.py`, `_multipart.py`, `_decoders.py`, `_exceptions.py`

逆向き (たとえば `_transports/*` から `_client.py` を import) は無い。
これは「Client を差し替えても transport は動く / transport を差し替えても Client は動く」設計のため。
