# Phase 1: 鳥瞰 (Orientation)

## リポジトリの種類 (1 行)

Python 製の汎用 HTTP クライアントライブラリ。**`requests` 互換の高水準 API** をユーザー面に、
**`httpcore` を低水準ネットワーク実装** として用いる薄いラッパー兼コーディネーション層。

## 1 段落要約

HTTPX は Python 3.9+ 向けの「次世代 HTTP クライアント」で、`requests` に準拠した
モジュール関数 (`httpx.get` 等) と `Client` / `AsyncClient` のセッション型 API を提供する。
内部では `httpcore` (h11 / h2 に依存) を **トランスポート** として呼び出し、
HTTPX 自体は **URL 解析、ヘッダ/Cookie/認証/リダイレクト/タイムアウト/ボディエンコード
/レスポンスデコード/イベントフック/プロキシ振り分け** といった「ユーザー側の便利機能と
セッション状態管理」を担う。同期と非同期、HTTP/1.1 と HTTP/2、WSGI/ASGI 直結など、
**透過交換可能な `BaseTransport` 抽象**を中心に据えた構造になっている。

## 技術スタックとパッケージマニフェスト

`pyproject.toml` (要点):
- ビルドシステム: `hatch`
- ランタイム依存:
  - **`httpcore`** — 低水準 HTTP 実装 (本ライブラリの「トランスポート層」)
  - `certifi` — CA バンドル
  - `idna` — IDN
  - `anyio` — 非同期抽象 (テスト用途中心)
- オプション extras: `http2` (h2), `socks` (socksio), `cli` (click + rich + pygments),
  `brotli`, `zstd`
- エントリポイント: `[project.scripts] httpx = "httpx:main"` (CLI / スコープ外)

## ディレクトリツリー (役割注釈付き)

```
httpx/
├── README.md
├── CHANGELOG.md
├── pyproject.toml           # 依存・extras・ビルド設定
├── docs/                    # MkDocs ドキュメント (今回は読まない)
├── tests/                   # 100% カバレッジを謳うテスト群
├── scripts/                 # check / docs / install などの開発スクリプト
└── httpx/                   # ★ 本体パッケージ
    ├── __init__.py          # 公開 API の集約 (re-export)
    ├── __version__.py
    ├── _api.py              # ★ モジュール関数 API (get/post/.../request/stream)
    ├── _client.py           # ★ Client / AsyncClient / BaseClient (セッション)
    ├── _models.py           # ★ Request / Response / Headers / Cookies
    ├── _transports/         # ★ トランスポート抽象と実装
    │   ├── base.py          #   BaseTransport / AsyncBaseTransport (ABC 相当)
    │   ├── default.py       #   HTTPTransport / AsyncHTTPTransport (httpcore ラッパ)
    │   ├── mock.py          #   テスト用 MockTransport
    │   ├── wsgi.py          #   WSGI アプリ直結
    │   └── asgi.py          #   ASGI アプリ直結
    ├── _auth.py             # 認証フロー (BasicAuth / DigestAuth / NetRCAuth)
    ├── _config.py           # Timeout / Limits / Proxy / create_ssl_context
    ├── _content.py          # リクエストボディエンコード (encode_request)
    ├── _decoders.py         # gzip/deflate/brotli/zstd レスポンスデコード
    ├── _multipart.py        # multipart/form-data エンコード
    ├── _exceptions.py       # 例外階層 (HTTPError → RequestError → TransportError ...)
    ├── _status_codes.py     # 列挙 (codes.OK 等)
    ├── _types.py            # 型エイリアス (RequestContent, AuthTypes など)
    ├── _urls.py             # 公開 URL / QueryParams / Headers ラッパ
    ├── _urlparse.py         # URL パーサ実装 (RFC 3986)
    ├── _main.py             # CLI (click)。スコープ外
    └── _utils.py            # 諸雑用 (環境プロキシ取得など)
```

(`_` プレフィックスは「内部実装」のサインで、`httpx/__init__.py` が必要なものを
公開 `__all__` に集約する。)

## 公開 API のエントリポイント (Phase 4 で深く追う)

- **`httpx/_api.py`** にモジュール関数 `request`, `get`, `post`, `put`, `patch`, `delete`,
  `head`, `options`, `stream` が定義されている。これらはすべて **使い捨ての `Client`
  をその場で生成し、`client.request(...)` に委譲** する薄いラッパ。
- セッションを使う場合は `httpx/_client.py` の `Client` / `AsyncClient`。

## 終了条件 (Phase 1)

「HTTPX は何のライブラリか?」に対し:

> requests 風の使い勝手を保ったまま、内部の HTTP 実装を `httpcore` に委ね、
> 公開 API ⇄ トランスポート の境界を `BaseTransport.handle_request(Request) → Response`
> という単一の抽象で固定した HTTP クライアントライブラリ。同期/非同期、HTTP/1.1 と HTTP/2、
> モック/WSGI/ASGI への差し替えが、この抽象の置換だけで成立する。

を 1 段落で言える状態。
