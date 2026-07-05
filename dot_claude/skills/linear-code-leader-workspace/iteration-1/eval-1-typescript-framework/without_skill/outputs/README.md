# Hono Onboarding Notes — Index

honojs/hono を「半日で全体像と中核フローを把握する」ためのオンボーディング資料。
TypeScript + Express 経験者を対象に、subagent (Claude Code) が `/tmp/eval-1/hono` (v4.12.19) を読んで作成した。

## 読む順番

1. **`00-overview.md`** — 30 秒理解 + Express との対応 + 半日プランの目次
2. **`01-architecture-map.md`** — モジュール構造の地図 (どのファイルが何をしているか)
3. **`02-core-request-flow.md`** — リクエストが流れる経路を実コードで trace
4. **`03-router-deep-dive.md`** — 5 種類の router の比較と内部メカニズム
5. **`04-context-and-middleware.md`** — 毎日触る `c.*` の API & middleware の書き方
6. **`05-typescript-and-validator.md`** — Env / Variables / Validator / `hc` client の型駆動
7. **`06-reading-roadmap.md`** — 行番号付き 4 時間プランと到達確認チェックリスト
8. **`07-express-vs-hono-cheatsheet.md`** — Express → Hono 対応表 (実装中の手元用)

## 推奨フロー

- 最初に **`00`** → **`06`** の通読 (= 半日プランの俯瞰)
- そこから `06` のフェーズに沿って **`02`** → **`04`** → **`03`** → **`05`** を実コードと並行で読む
- 来週の実装中は **`04`** と **`07`** を辞書代わりに開きっぱなしにする

## 参照しているリポジトリ

- `/tmp/eval-1/hono` (https://github.com/honojs/hono, v4.12.19, `--depth=1`)
- 全ファイル参照は `src/` を root とする相対パス + 行番号で記載

## 何をやらなかったか (意図的に省略した範囲)

- `src/jsx/` (内蔵 JSX/SSR) — API サーバ用途では基本不要
- `src/client/` の実装詳細 — 使い方は `05` で触れたが、Proxy ベースの内部は深掘りせず
- `runtime-tests/`, `perf-measures/`, `benchmarks/` — 仕様確認用のサブ
- `src/middleware/*` 各論 (cors/logger のみ言及) — 使う時に各 index.ts を読めば十分
- `src/types.ts` 全読 — 必要型のみ grep で十分

省いた領域は、必要になったタイミングで `01-architecture-map.md` の地図と `06-reading-roadmap.md` の Phase 構造を再利用すれば独力で辿れる構成にしてある。
