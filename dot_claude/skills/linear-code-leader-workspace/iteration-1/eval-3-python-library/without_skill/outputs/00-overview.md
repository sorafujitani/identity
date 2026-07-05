# httpx を読む — オーバービュー

対象リビジョン: `git clone --depth=1 https://github.com/encode/httpx.git` (master, depth=1)
作業ディレクトリ: `/tmp/eval-3/httpx`

このセットは「`httpx.get(url)` のような公開 API が、内部のトランスポート (httpcore / ASGI / WSGI / Mock) まで降りていく経路」を、半日で掴むためのガイドです。

## 読者前提

- `requests` 経験あり → `Client` / `Response` / `Headers` の語彙は通用する。違いは Session 相当が「コンテキストマネージャ前提」「sync/async 二系統」「transport を差し替えられる」点。
- `asyncio` 経験あり → `AsyncClient` は `Client` と完全パラレルだが、`handle_async_request` 経由で `httpcore.AsyncConnectionPool` を呼ぶ。

## ファイル一覧 (出力)

| ファイル | 内容 |
| --- | --- |
| `00-overview.md` | この案内。読む順序の地図 |
| `01-architecture-layers.md` | レイヤ構造 / 主要モジュール役割表 |
| `02-call-path-public-to-transport.md` | `httpx.get` → `httpcore.ConnectionPool` までの呼び出しトレース |
| `03-transport-abstraction.md` | `BaseTransport` 抽象と 4 実装 (Default/Mock/ASGI/WSGI) の比較 |
| `04-key-objects-quickref.md` | Request / Response / Auth flow / URLPattern のスニペットつきリファレンス |
| `05-reading-plan-half-day.md` | 半日想定の読み進めプラン (時間配分付き) |

## 一行で言うと

httpx は **「`requests` 風のユーザ API」 + 「`urllib3` の代わりに [httpcore](https://github.com/encode/httpcore) を呼ぶ薄い変換層」 + 「sync/async ミラーリング」 + 「transport を差し替え可能にした testability」** で構成されている。

httpx 自身は HTTP/1.1 や HTTP/2 のプロトコルパーズ・コネクションプール・ソケット I/O を **持たない**。そこは httpcore の仕事。httpx が担うのは:

1. ユーザフレンドリな URL/Headers/Cookies/QueryParams のモデル
2. `Auth` 抽象 (ジェネレータでチャレンジ/レスポンスを表現)
3. リダイレクト・タイムアウト・event hooks のオーケストレーション
4. content/json/files/multipart のエンコード、gzip/brotli/zstd デコード
5. transport を URL パターン (mounts) で振り分け
