# Phase 5: 横断的関心事

Phase 0 の目的「公開 API ↔ トランスポート層の経路を把握」に必要な分だけ拾う。

## 例外ハンドリング

- **階層**: `httpx.HTTPError` をルートに、`RequestError` → `TransportError` → 具体 (`ConnectError`, `ReadTimeout`, ...) というツリー (`httpx/_exceptions.py:74-271`)。
- **httpcore 例外との境界**: `HTTPTransport.handle_request` が `with map_httpcore_exceptions():` を必ず噛ませる (`httpx/_transports/default.py:249`)。例外マップは `_load_httpcore_exceptions()` (`:74`) で 1 度だけ構築されモジュールグローバル `HTTPCORE_EXC_MAP` にキャッシュされる。
- **方針**: ユーザーから見える例外は **常に `httpx.*`**。`__cause__` で `httpcore.*` を chain。
- **ストリーム関連**: `ResponseNotRead`, `StreamConsumed`, `StreamClosed` など、ライフサイクルミスを早期に検出する例外 (`_exceptions.py:309-364`)。

## 認証 / 認可

- **ジェネレータベース**の `Auth.auth_flow(request) -> Generator[Request, Response, None]` がコア抽象 (`httpx/_auth.py:38`)。
- `Client._send_handling_auth` が次のように回す (`_client.py:930-962`):
  ```
  request = next(auth_flow)
  while True:
      response = _send_handling_redirects(request, ...)
      try:
          request = auth_flow.send(response)
      except StopIteration:
          return response
  ```
- 実装: `BasicAuth`, `DigestAuth` (challenge-response で 2 往復)、`NetRCAuth`、callable を包む `FunctionAuth` (`_auth.py:113-175`)。
- 認可は HTTPX 側にはない (HTTP クライアントのため)。サーバー側関心事。

## ロギング / 観測性

- `httpx/_client.py` 冒頭で `logger = logging.getLogger('httpx')`。
- 各リクエスト完了時に `logger.info('HTTP Request: %s %s "%s %d %s"', method, url, http_version, status, reason)` を出す (`_client.py:1025-1032`, 非同期側にも対称コード)。
- `request_context` (`_client.py:1013` で使用) は **トレース用のコンテキスト** を持ち回す関数 (`_utils.py` 由来)。
- メトリクスは固有実装なし。`response.elapsed` が `BoundSyncStream.close()` で計測される (`_client.py:156-159`)。

## 設定管理

- **モジュール定数**で完結 (`httpx/_config.py:246-248`):
  - `DEFAULT_TIMEOUT_CONFIG = Timeout(timeout=5.0)`
  - `DEFAULT_LIMITS = Limits(max_connections=100, max_keepalive_connections=20)`
  - `DEFAULT_MAX_REDIRECTS = 20`
- 環境変数読み込み: `trust_env=True` のとき `get_environment_proxies()` (`_utils.py`) が `HTTP_PROXY` 等を返し、`BaseClient._get_proxy_map` (`_client.py:239`) が `Proxy` インスタンスに変換。
- SSL: `create_ssl_context(verify, cert, trust_env)` が `certifi` の CA バンドルで `ssl.SSLContext` を作る。
- シークレット管理は **netrc** 経由のみ (`NetRCAuth`)。それ以外は呼び出し側責任。

## 永続化

- なし。Cookie は in-memory (`httpx/_models.py:1079 Cookies`)。

## 非同期 / 並行性

- **同期と非同期は完全対称**:
  - `Client` ↔ `AsyncClient` (`_client.py:594` / `:1307`)
  - `BaseTransport.handle_request` ↔ `AsyncBaseTransport.handle_async_request` (`_transports/base.py:26` / `:77`)
  - `HTTPTransport` (内部 `httpcore.ConnectionPool`) ↔ `AsyncHTTPTransport` (`httpcore.AsyncConnectionPool`) (`_transports/default.py:135` / `:279`)
  - `SyncByteStream` ↔ `AsyncByteStream` (`_types.py`)
- スレッドセーフ性: `Client` は keep-alive プールを内部に持つが、`httpcore` 側でロックされており **複数スレッドで共有可** (README の記述と `Client` docstring `_client.py:598`)。
- async 側は `sniffio` で asyncio/trio を自動判別 (`pyproject.toml` 依存)。

## トランスポート抽象 (本リポの設計の中核)

- `BaseTransport` は **最小契約**: `handle_request(Request) -> Response`, `close()`, `__enter__/__exit__` の 4 つだけ (`_transports/base.py:14-62`)。
- 同梱実装は **4 種**:
  | クラス | 用途 |
  |---|---|
  | `HTTPTransport` | 実ネットワーク (httpcore 経由) |
  | `MockTransport` | テスト用。コンストラクタに `callable(Request)->Response` を渡す (`_transports/mock.py`) |
  | `WSGITransport` | プロセス内の WSGI アプリ呼び出し (`_transports/wsgi.py`) |
  | `ASGITransport` | プロセス内の ASGI アプリ呼び出し (`_transports/asgi.py`) |
- ユーザー拡張: `Client(transport=MyTransport())` で差し替え可能、または `mounts={"https://example.com": MyTransport()}` で URL パターン単位で混在。
- **`_init_transport` は `transport` 引数があれば自前生成をスキップ** (`_client.py:728-738`)。これがテスト容易性の鍵。

## テスト戦略

- `tests/` 直下にトピック別ディレクトリ (`client/`, `models/`, `test_main.py`, `test_timeouts.py` 等)。
- 100% カバレッジを謳う (README)。
- `MockTransport` でネットワークなしのユニットテスト可能。ASGI/WSGI アダプタも同様に外部依存ゼロでテスト可能。

## まとめ (Phase 0 目的に直結する 3 行)

> HTTPX は HTTP 周りの面倒な状態 (cookies / redirects / auth) を **`Client` の中で完結** させ、
> 実際のソケット I/O は **`BaseTransport.handle_request` という 1 メソッドの抽象** に隔離している。
> その境界に `map_httpcore_exceptions` というアダプタを置くことで、`httpcore` 側の例外を `httpx` 階層に統一している。
