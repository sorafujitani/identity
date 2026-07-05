# 半日 (4-5h) 読み進めプラン

公開 API → 内部 transport を **腑に落ちる** レベルまで持っていくための時間配分。

## Phase 0 — 5 分 — ファイル俯瞰

```bash
cd /tmp/eval-3/httpx
wc -l httpx/*.py httpx/_transports/*.py | sort -n
```

行数だけで「`_client.py` が異常にデカい (2019)、次に `_models.py` (1277)」「`_transports/*` は全部足しても 900 行程度」が見えれば OK。**重い読み物は `_client.py` だけ**、と心構えできる。

## Phase 1 — 30 分 — エントリーポイント

1. `httpx/__init__.py` (106 行) ── public 名のリスト。**ここに無いものは internal**
2. `httpx/_api.py:39-120` ── `request()` ── これが「毎回 Client を作る」薄ラッパだと確認
3. `httpx/_api.py:174-` ── `get` / `post` 等は全部 `request()` のショートカット

ここまでで「モジュール関数は本質ではない、本質は `Client`」と納得する。

## Phase 2 — 60 分 — Transport 抽象

順番に読む:

1. `_transports/base.py` (86 行) ── 抽象。`handle_request(Request) -> Response` だけが契約
2. `_transports/mock.py` (43 行) ── 「テストでどう使うか」が分かる最小実装
3. `_transports/default.py` (406 行) ── 本番。`__init__` のプロキシ分岐 → `handle_request` の詰め替えを精読
4. `_transports/asgi.py` (187 行) ── 関心があれば。ASGI プロトコルの良い実例
5. `_transports/wsgi.py` (149 行) ── 同上。PEP 3333 の良い実例

**`_transports/default.py:230-259` の `handle_request` を音読できるくらいに読む** のがこのフェーズのゴール。
httpx と httpcore の境界がここに集約されている。

## Phase 3 — 90 分 — Client 本体

`_client.py` の以下「だけ」を読む (順序が大事):

1. `BaseClient.__init__` と setter 群 (188-339) ── どの引数がどこに保持されるか
2. `BaseClient.build_request` (340-389) ── Request 構築 + extensions["timeout"]
3. `BaseClient._merge_url` / `_merge_headers` / `_merge_cookies` / `_merge_queryparams` (391-443)
4. `BaseClient._build_request_auth` (457-473) ── Auth が無くても URL の username:password で BasicAuth が組まれる、を確認
5. `BaseClient._build_redirect_request` (475-582) ── Authorization 剥がし、Host 書換、Cookie 消し
6. `Client.__init__` (639-716) ── transport インスタンス化と `_mounts` の組立て
7. `Client._init_transport` (718-738) ── ユーザ指定 transport が無ければ `HTTPTransport()` を作る
8. `Client._transport_for_url` (760-769) ── mounts ルックアップ
9. `Client.request` / `Client.send` (771-928) ── 全部読む
10. `Client._send_handling_auth` (930-962) ── auth ジェネレータと flow.send(response) パターン
11. `Client._send_handling_redirects` (964-999) ── redirect ループ + event hooks
12. `Client._send_single_request` (1001-1034) ── ★Transport 境界★

`AsyncClient` (1307-) は **`Client` を読み終わってから**眺める。
クラスごとの差分しか無い (`def` → `async def`, `next` → `__anext__`, `.send` → `.asend`)。完全対称なので 10 分で確認できる。

## Phase 4 — 45 分 — モデル層

`_models.py` は 1277 行あるが、読むべきは:

1. `Request.__init__` (382-440) ── content/data/files/json → stream の組立て
2. `Request._prepare` / `read` / `aread` (441-494)
3. `Response.__init__` (515-569) ── レスポンス側はもっとシンプル
4. `Response.iter_bytes` / `iter_raw` / `read` / `close` (876-972) ── ストリーミング消費の仕組み
5. `Response.has_redirect_location` (772) ── リダイレクトループの判定条件

`Headers` (139) や `Cookies` (1079) は **必要になったら見る** スタンスで OK。
クラスの API はテストを 1, 2 個眺めれば想像つく。

## Phase 5 — 30 分 — 周辺

時間が余ったらここ:

- `_auth.py:22-110` ── `Auth` の ジェネレータパターン (生成 → next → send (response) → StopIteration)
- `_auth.py:175-` ── `DigestAuth` の challenge-response 実装。auth_flow がジェネレータな理由が体感できる
- `_config.py:72-` ── `Timeout` の `as_dict()` で transport へ伝わる仕組み
- `_utils.py:120-209` ── `URLPattern` 。mounts の挙動が気になっているなら
- `_decoders.py` ── gzip/brotli/zstd のストリーミングデコーダ。1 ファイルで完結
- `_multipart.py` ── ファイルアップロード時に何が起きるか

## Phase 6 — 30 分 — 動かして確かめる

仮説検証は実際に走らせるのが速い:

```python
import httpx, logging
logging.basicConfig(level=logging.DEBUG)

# 1) Mock で「Transport 抽象が本当に handle_request だけで成立する」を確認
def handler(req):
    print("got:", req.method, req.url, req.headers.raw)
    return httpx.Response(200, json={"echo": req.url.path})

with httpx.Client(transport=httpx.MockTransport(handler)) as c:
    r = c.get("https://example.org/hello")
    print(r.json())

# 2) event_hooks で _send_handling_redirects のフックがどこに刺さるか確認
def on_req(r): print("REQ:", r.method, r.url)
def on_res(r): print("RES:", r.status_code, r.url)
with httpx.Client(event_hooks={"request": [on_req], "response": [on_res]}) as c:
    r = c.get("https://httpbin.org/redirect/2", follow_redirects=True)

# 3) follow_redirects=False で response.next_request が何になるか
with httpx.Client() as c:
    r = c.get("https://httpbin.org/redirect/1")
    print(r.status_code, r.next_request)   # 302, <Request>
```

`HTTPX_LOG_LEVEL=DEBUG` 環境変数を入れると httpcore 側の接続ログも出るので、本物の transport を貫通させてもよい (`docs/logging.md` 参照)。

## 達成チェックリスト

半日後、こんな質問にスラスラ答えられたら成功:

- [ ] `httpx.get("...")` が `httpcore.ConnectionPool.handle_request` に達するまで、いくつの関数を経由するか?
- [ ] `Client(transport=MyTransport())` を渡せるのは何故? どの ABC を満たせばいい?
- [ ] `mounts={...}` のキーはどう解釈される? マッチングはどこで?
- [ ] `Auth` のサブクラスを書くときの「契約」は何?
- [ ] `Response.iter_bytes()` と `iter_raw()` の違いは?
- [ ] `Timeout` はどうやって transport まで届く?
- [ ] `httpx` 例外と `httpcore` 例外の関係は?
- [ ] sync と async でロジックを 2 重実装しているが、唯一の構造差はどこ?

## 読まなくていいもの (半日では)

- `_urlparse.py` (527 行) ── RFC 3986 のフルパーザ。挙動を疑った時だけ
- `_main.py` (506 行) ── CLI。本体理解には不要
- `_status_codes.py` ── enum テーブル
- `tests/` ── 必要に応じて pinpoint で
- `docs/` ── 読み物としては良いが、コードリーディングの最中には逸れる

## メンタルモデルを 1 文に圧縮

> **httpx = (requests風 API + sync/async両対応 + transport 差替可能) × ピュアな orchestration 層。実 I/O は httpcore に丸投げ。**
