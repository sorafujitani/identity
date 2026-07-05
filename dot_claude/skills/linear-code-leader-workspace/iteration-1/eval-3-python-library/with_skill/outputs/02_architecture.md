# Phase 2: アーキテクチャマップ

## アーキテクチャスタイル

**「2 層 + プラガブルトランスポート」** 構造。要するに **ヘキサゴナル風**:
- **コア (Client / Models)** がアプリケーションロジック (セッション状態、リダイレクト、認証、
  ボディエンコード、レスポンスデコード) を持つ
- **ポート (`BaseTransport`)** が外界 (ネットワーク or アプリ) との単一インタフェース
- **アダプタ (`HTTPTransport`, `ASGITransport`, `WSGITransport`, `MockTransport`)** が
  具体実装を差し替え可能

これにより「`Client` のユーザー機能は固定、出力先 (ソケット / メモリ内アプリ / モック) は差し替え」
というテスタブルな設計が成立している。

## コンポーネント図

```mermaid
graph LR
  subgraph User_Facing[User-facing API]
    APIfns["_api.py<br/>(get/post/request/stream)"]
    Client["_client.py<br/>Client / AsyncClient"]
  end

  subgraph Models[Domain Models]
    Req["_models.py<br/>Request"]
    Resp["_models.py<br/>Response"]
    HC["_models.py<br/>Headers / Cookies"]
    URL["_urls.py<br/>URL / QueryParams"]
  end

  subgraph Support[Support layer]
    Auth["_auth.py<br/>Auth / BasicAuth / DigestAuth"]
    Cfg["_config.py<br/>Timeout / Limits / Proxy / SSL"]
    Content["_content.py<br/>encode_request"]
    Decode["_decoders.py<br/>gzip/br/zstd"]
    Exc["_exceptions.py<br/>HTTPError 階層"]
  end

  subgraph Transport[Transport port + adapters]
    Base["_transports/base.py<br/>BaseTransport (abstract)"]
    HTTPT["_transports/default.py<br/>HTTPTransport"]
    Mock["_transports/mock.py<br/>MockTransport"]
    WSGI["_transports/wsgi.py<br/>WSGITransport"]
    ASGI["_transports/asgi.py<br/>ASGITransport"]
  end

  External["httpcore<br/>(+ h11 / h2)<br/>外部ライブラリ"]

  APIfns --> Client
  Client --> Req
  Client --> Resp
  Client --> Auth
  Client --> Cfg
  Client --> Base
  Req --> Content
  Req --> URL
  Resp --> Decode
  Base <|-- HTTPT
  Base <|-- Mock
  Base <|-- WSGI
  Base <|-- ASGI
  HTTPT --> External
  HTTPT --> Exc
```

## コンポーネント別の役割 (1 行)

| コンポーネント | 役割 |
|---|---|
| `_api.py` | モジュール関数。`Client` を 1 回ごとに作って委譲する糖衣 |
| `_client.py` `BaseClient` | 共通状態 (headers/cookies/auth/timeout/base_url) と redirect/url merge のロジック |
| `_client.py` `Client` / `AsyncClient` | トランスポート保持 + `request → build_request → send → handle_request` を統括 |
| `_models.py` `Request` / `Response` | リクエスト/レスポンスの中心エンティティ。ストリームを内包 |
| `_models.py` `Headers` / `Cookies` | requests 互換の Mapping ラッパ |
| `_urls.py` `URL` / `QueryParams` | 公開 URL/クエリ型 |
| `_auth.py` | `Auth.auth_flow(request) -> Generator[Request, Response, None]` 形式の認証反復 |
| `_config.py` | `Timeout`, `Limits`, `Proxy`, `create_ssl_context` |
| `_content.py` / `_multipart.py` | リクエストボディのバイト列化 |
| `_decoders.py` | gzip / deflate / brotli / zstd の解凍 |
| `_exceptions.py` | 例外階層。`httpcore` 例外を `map_httpcore_exceptions()` で **再写像** する |
| `_transports/base.py` | `BaseTransport.handle_request(Request) -> Response` の抽象 |
| `_transports/default.py` | `httpcore.ConnectionPool` / `HTTPProxy` / `SOCKSProxy` を内包 |
| `_transports/mock.py` | テスト用。任意の callable を `Response` に写像 |
| `_transports/{wsgi,asgi}.py` | プロセス内 WSGI/ASGI アプリ呼び出しでネットワーク不要 |

## 依存方向の確認

`import` を抜粋でサンプリングして整合性確認:
- `_api.py` → `_client.py`, `_models.py`, `_types.py`, `_urls.py` (上位 → 下位)
- `_client.py` → `_auth.py`, `_config.py`, `_models.py`, `_transports`, `_urls.py`, `_utils.py`
- `_transports/default.py` → `_config.py`, `_exceptions.py`, `_models.py`, `_types.py`,
  `_urls.py`, `.base`, **`httpcore` (lazy import)**
- `_transports/base.py` → `_models.py` のみ (極小)
- `_models.py` → `_content.py`, `_decoders.py`, `_status_codes.py`, `_types.py`, `_urls.py`,
  `_multipart.py`, `_exceptions.py`

**逆向きの依存はない** (例: `_models.py` は `_client.py` を import しない)。
これがヘキサゴナル的に綺麗な「内 → 外」の依存方向を保証している。

## 外部依存 (実行時)

- **`httpcore`** — `HTTPTransport` から `ConnectionPool` / `HTTPProxy` / `SOCKSProxy` /
  `Request` / `URL` / 例外群を直接利用。**遅延 import** (`HTTPTransport.__init__` 内で
  `import httpcore`)
- `certifi` — `create_ssl_context` で CA バンドルを取得
- `idna` — URL パース時の国際化ドメイン処理
- (オプション) `h2`, `socksio`, `brotli`/`brotlicffi`, `zstandard`, `click`, `rich`

## 終了条件

`httpx.get(...)` がどのコンポーネントを通るかが、図上で矢印 1 本ずつ辿れる:

`_api.get` → `_api.request` → `Client.__init__` (with) → `Client.request` →
`Client.build_request` → `Request` → `Client.send` → `Client._send_handling_auth` →
`Client._send_handling_redirects` → `Client._send_single_request` →
`Client._transport_for_url` → `HTTPTransport.handle_request` → `httpcore.ConnectionPool.handle_request` →
`Response` を組み立てて逆順に巻き戻し → ユーザーへ

(具体ファイル:行は Phase 4 で示す)
