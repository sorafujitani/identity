# Phase 0: スコープ宣言

ユーザーからフォローアップ質問ができないため、ガイド役の判断でスコープを以下の通り宣言する。

```
スコープ: httpx パッケージのコア (httpx/ 配下、特に同期 API 経路)
        — _api.py / _client.py / _models.py / _transports/*.py
        — _auth.py / _config.py / _exceptions.py は横断的関心事として軽く参照
        — _urls.py, _content.py, _decoders.py, _multipart.py, _main.py(CLI) はスコープ外
        — 非同期 (AsyncClient) と HTTP/2 拡張は対称関係を指摘するのみで深追いしない

目的: httpx の「公開 API → 内部トランスポート層 (httpcore 境界) まで」の経路把握。
      requests 経験者が中身を読むためのオンボーディング。

時間: 半日 (30〜45分 subagent ターン内)。Phase 4 を最重要、Phase 5-6 は要点のみ。

前提: ユーザーは Python の requests と async に経験あり、httpx 内部は初見。
      httpcore / h11 / h2 は「外部依存」として黒箱扱いし、境界面 (httpcore.ConnectionPool
      と httpcore.Request/Response) までを追う。

代表フロー: httpx.get('https://example.com') を呼んでから Response が返るまで。
```

## スコープから外す範囲と理由

| 範囲 | 扱い | 理由 |
|---|---|---|
| `_main.py` (CLI / click 統合) | スコープ外 | 公開 API → トランスポート層の経路と独立 |
| `_urls.py` / `_urlparse.py` | API シグネチャ理解にのみ参照 | パーサ実装の深掘りは時間対効果が低い |
| `_content.py` / `_multipart.py` / `_decoders.py` | Phase 5 で名前だけ言及 | ボディエンコード/圧縮解凍は副次的関心事 |
| `AsyncClient` / `AsyncHTTPTransport` | 対応関係のみ示す | 同期と完全対称、命名が `a`/`async_` プレフィックスで区別される |
| `HTTP/2` / SOCKS / WSGI / ASGI 経路 | Phase 2 のマップ上で位置付けるのみ | 代表フロー (HTTPS GET) に乗らない |
| httpcore / h11 / h2 内部 | 黒箱 | リポジトリ外、別ライブラリ |

## 終了条件

ガイド役 (Claude) がこのスコープに従って Phase 1〜6 を実施し、出力ディレクトリに
7 つの成果物 .md を書き出すこと。
