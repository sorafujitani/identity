# HTTPX (encode/httpx) — 総合理解ドキュメント

> 半日想定の linear-code-leader ガイド (Phase 0〜6) による読解結果。
> 目的: 公開 API ↔ 内部トランスポート層の経路を把握する。
> 代表フロー: `httpx.get('https://example.com')` から `Response` 返却まで。

## 1. 1 段落サマリ

HTTPX は Python 3.9+ 向けの汎用 HTTP クライアントライブラリで、`requests` 互換の高水準
モジュール関数 (`httpx.get` 等) と `Client` / `AsyncClient` のセッション型 API を提供する。
内部では `httpcore` (h11 / h2 依存) を **トランスポート** として呼び出し、HTTPX 自身は
URL/ヘッダ/Cookie/認証/リダイレクト/タイムアウト/ボディエンコード/レスポンスデコード/
イベントフック/プロキシ振り分けを担う。**ヘキサゴナル風に `BaseTransport.handle_request`
を 1 つの I/O 境界に固定**しているのが設計上の核で、同期と非同期、実ネットワーク (httpcore)
とプロセス内 (WSGI/ASGI)、モックの差し替えがすべてこの境界の置換だけで成立する。

## 2. アーキテクチャ (Phase 2 抜粋)

```mermaid
graph LR
  api[_api.py<br/>get/post/request/stream] --> client[_client.py<br/>Client / AsyncClient]
  client --> models[_models.py<br/>Request / Response / Headers / Cookies]
  client --> auth[_auth.py<br/>Auth ジェネレータ]
  client --> base[_transports/base.py<br/>BaseTransport]
  base -. impl .-> http[_transports/default.py<br/>HTTPTransport]
  base -. impl .-> mock[_transports/mock.py]
  base -. impl .-> wsgi[_transports/wsgi.py]
  base -. impl .-> asgi[_transports/asgi.py]
  http --> httpcore[httpcore<br/>(external)]
```

スタイル: **2 層 + プラガブルトランスポート**。ユーザー側 (`_api`/`_client`/`_models`/`_auth`/`_config`)
と外界 (`_transports/*`) を `BaseTransport` という 1 メソッド抽象で分離。詳細は `02_architecture.md`。

## 3. ドメインモデル (Phase 3 抜粋)

| 型 | 役割 |
|---|---|
| `Client` / `AsyncClient` | セッション状態 + トランスポート保持。`request()` / `send()` のオーケストレーション |
| `Request` | method / url / headers / extensions / stream |
| `Response` | status_code / headers / stream / history / extensions。`_request` で双方向 |
| `BaseTransport` | `handle_request(Request) -> Response` (+ close) の最小抽象 |
| `HTTPTransport` | `httpcore.ConnectionPool` を内包する実ネットワーク実装 |
| `Auth` | `auth_flow(Request) -> Generator[Request, Response, None]` で多段認証を表現 |
| `Timeout` / `Limits` / `Proxy` | `_config.py`。Timeout は connect/read/write/pool の 4 軸 |
| `URLPattern` | `mounts` のマッチング (URL パターン → Transport の辞書) |

`ClientState`: `UNOPENED → OPENED → CLOSED` (`_client.py:125`)。詳細と用語集は `03_domain.md`。

## 4. 代表フロー (Phase 4 抜粋) — `httpx.get('https://example.com')`

主要呼び出しチェーン (ファイル:行 関数名):

1. `httpx/_api.py:174` `get()` → `httpx/_api.py:39` `request()`
2. `httpx/_api.py:102` `with Client(...) as client` → `httpx/_client.py:639` `Client.__init__` → `httpx/_client.py:718` `_init_transport` → `httpx/_transports/default.py:135` `HTTPTransport.__init__` → `httpx/_transports/default.py:156` `httpcore.ConnectionPool(...)`
3. `httpx/_client.py:771` `Client.request` → `httpx/_client.py:340` `BaseClient.build_request` → `httpx/_models.py:382` `Request.__init__`
4. `httpx/_client.py:879` `Client.send` → `httpx/_client.py:930` `_send_handling_auth` (`httpx/_auth.py:62` `sync_auth_flow`) → `httpx/_client.py:964` `_send_handling_redirects` → `httpx/_client.py:1001` `_send_single_request`
5. `httpx/_client.py:760` `_transport_for_url` (mounts 走査) → `httpx/_transports/default.py:230` `HTTPTransport.handle_request`
6. `httpx/_transports/default.py:237-248` `httpx.Request → httpcore.Request` 変換 → `httpx/_transports/default.py:250` `self._pool.handle_request(req)` (httpcore 領域)
7. 戻りで `httpx/_transports/default.py:254-259` `Response` 構築 → `httpx/_client.py:1019` `BoundSyncStream` でラップ → `httpx/_client.py:1022` cookie 取り込み → `httpx/_client.py:1025` ログ
8. `httpx/_client.py:921` `response.read()` → `httpx/_models.py:876` 本文取得
9. `httpx/_client.py:1293` `__exit__` で `close()` 連鎖 (`HTTPTransport.close` → `pool.close`)

エラーパス: `httpcore.ConnectError` などは `httpx/_transports/default.py:95` `map_httpcore_exceptions()`
で **`httpx.ConnectError` に再写像** され、`__cause__` に元例外が chain される。

シーケンス図と全注釈は `04_flow.md` を参照。

## 5. 横断的関心事 (Phase 5 抜粋)

- **例外**: `HTTPError` 階層。`httpcore` 例外は `HTTPTransport` 境界で必ず再写像。
- **認証**: ジェネレータベース。Digest auth の challenge-response も同一抽象で表現。
- **ロギング**: `logging.getLogger('httpx')`。`logger.info('HTTP Request: ...')` を 1 リクエストにつき 1 回。
- **設定**: `Timeout(5.0)` / `Limits(100, 20)` / `MAX_REDIRECTS=20` がデフォルト。`trust_env=True` で環境変数とプロキシを尊重。
- **非同期**: 同期と完全対称。`a` / `async_` プレフィックスで命名規約が一貫。
- **テスト**: `MockTransport` でネットワーク不要。100% カバレッジを謳う。

詳細は `05_concerns.md`。

## 6. 設計上の **要点**

1. **`BaseTransport.handle_request` という 1 メソッド抽象** が設計の核。これがあるおかげで、
   ユーザーは「実ネット / モック / WSGI / ASGI / カスタム」を `Client(transport=...)`
   だけで差し替えられる。
2. **`httpx.Request/Response` ⇄ `httpcore.Request/Response` の変換層** は `HTTPTransport.handle_request`
   の中に閉じている (`_transports/default.py:237-259`)。`httpcore` の存在は外向き API には漏れない。
3. **認証はジェネレータ**。これによって 401 → challenge → 認証付き再送、のような多段フローが
   `auth_flow.send(response)` 1 行で表現できる。同期/非同期両方で機能する。
4. **httpcore は遅延 import**。`HTTPTransport.__init__` の中で `import httpcore` するため、
   `httpx` をインポートしただけでは `httpcore` がロードされない (パッケージング上の配慮)。
5. **`Response.stream`** は 3 段で包まれている: `httpcore` の iterable → `ResponseStream` (例外マップ付き)
   → `BoundSyncStream` (elapsed 計測付き)。

## 7. 未解決の疑問 / 仮説リスト

| # | 疑問 | 仮説 / 次にどこを読むか |
|---|---|---|
| Q1 | `urlparse` (`_urlparse.py:527 行`) は IDN / IPv6 / userinfo まで自前パーサで処理しているのか? | `_urlparse.py` の冒頭 RFC 番号コメントを確認。`idna` 依存は import 行で見える |
| Q2 | `extensions` dict のキーは全列挙されているか? (`timeout`, `http_version`, `reason_phrase`, `sni_hostname`, `target` ...) | `_types.py` の `RequestExtensions` TypedDict と httpcore 側 README 参照 |
| Q3 | `Cookies` の RFC 6265 準拠度 (Set-Cookie の path/domain/expiration マッチング) | `_models.py:1079` 以降と `tests/client/test_cookies.py` |
| Q4 | HTTP/2 経路ではフローのどこが変わるか? | `HTTPTransport(http2=True)` 時の `httpcore.ConnectionPool` の挙動は `httpcore` 側 |
| Q5 | `event_hooks['response']` は **デコード前のレスポンス** に対して呼ばれるのか? | `_client.py:976` 付近の `event_hooks['response']` 実行タイミングを精読 |
| Q6 | `mounts` の URL パターンマッチの優先順 (`all://` と `https://example.com` の重なり) | `_client.py:716` `self._mounts = dict(sorted(self._mounts.items()))` と `URLPattern.__lt__` |
| Q7 | `BoundSyncStream.close()` の `elapsed` 計測は **本文を消費しきる前** に閉じた場合どうなるか? | `_client.py:156-159` と `tests/` の elapsed 関連テスト |

## 8. Phase 6 自己検証 (別フローの予測)

**選んだ別フロー**: `client.post('https://api.example.com/items', json={'a': 1})` (POST + JSON + sessionful)

自己予測:
- `_client.py:1123` `Client.post` → `Client.request('POST', url, json=..., ...)` → `build_request` → `Request.__init__` でこの `json` 引数が `encode_request()` (`_content.py`) によって `application/json` ボディと `Content-Type: application/json` / `Content-Length` ヘッダにエンコードされる
- 残りは GET と同じ: `_send_handling_auth` → `_send_handling_redirects` → `_send_single_request` → `HTTPTransport.handle_request` → `httpcore`

確認: 上記予測は `_client.py:1123-1156` `Client.post` のシグネチャと `_models.py:408` `encode_request(...)` 呼び出しと整合する。GET と異なる分岐点は **Request 構築時のみ**であり、トランスポート以降は同一。

→ **代表フロー図は「パターン」として機能している**。Phase 4 の成果物は別フロー予測に再利用できる。

## 9. このドキュメントの使い方

- 新しい機能 (例えば「リトライミドルウェアを追加したい」) を考えるとき、
  まず `_send_single_request` (`_client.py:1001`) の前後どちらに挟むかを Phase 4 図で検討する。
- 例外を投げる場所を探すときは Phase 5 の **例外マップ** (`_transports/default.py:74-92`) から逆引きする。
- カスタムトランスポート (テスト用 fake、AWS sigv4 用 wrapper など) を書くときは
  `BaseTransport`/`AsyncBaseTransport` (`_transports/base.py`) を継承し、`handle_request` を実装する。

---

成果物リスト:
- `00_scope.md` — Phase 0 スコープ宣言
- `01_summary.md` — Phase 1 鳥瞰
- `02_architecture.md` — Phase 2 アーキテクチャマップ
- `03_domain.md` — Phase 3 ドメインモデル
- `04_flow.md` — Phase 4 代表フロー (シーケンス図 + ファイル:行注釈)
- `05_concerns.md` — Phase 5 横断的関心事
- `UNDERSTANDING.md` — 本ファイル (Phase 6 統合)
