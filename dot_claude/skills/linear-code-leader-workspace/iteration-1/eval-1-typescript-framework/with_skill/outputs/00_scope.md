# Phase 0: スコープ宣言

> フォローアップ質問不可のバッチ実行のため、ユーザーの状況 (TS+Express 経験者 / Hono 初見 / 来週から Hono で API を書く / 半日想定) から妥当な判断としてスコープを宣言する。

```
スコープ:   honojs/hono リポジトリの src/ 配下のうち、コアフレームワーク部分
            すなわち src/{hono.ts, hono-base.ts, compose.ts, context.ts, request.ts,
            router.ts, router/(smart-router, reg-exp-router), http-exception.ts}
            アダプタ群 (src/adapter/*) ・ JSX (src/jsx/*) ・ クライアント (src/client/*)
            ・ 個別ミドルウェア実装は概念紹介のみで深追いしない。
目的:       来週から Hono で Web API を書き始めるための事前理解。
            「app.get('/foo', handler) が動く仕組み」と「ミドルウェア合成・型」を
            自分の言葉で説明できる状態を目指す。
時間:       半日。Phase 4 (代表フロー = 1 HTTP リクエストの処理) に時間を厚く配分。
前提:       TypeScript + Express の経験あり (ミドルウェアパターン・ルーティング・
            req/res の概念は既知)。Hono と Web Standards (Request/Response) は初見。
非目標:     全ルーターアルゴリズム (TrieRouter/RegExpRouter の内部実装) の解読、
            JSX レンダラ、SSG、各ランタイムアダプタの個別差分、client/ の型推論詳細。
```

## なぜこの範囲か

- ユーザーは「API を書き始める」段階のため、フレームワーク利用者目線で `Hono` クラス→ルーティング→ミドルウェア合成→ `Context` の API の流れを把握できれば実用上十分。
- Router の選定戦略 (SmartRouter) は触れるが、各 Router の正規表現組み立てやトライ木構造は別途必要時に読めばよい。
- アダプタ層は「fetch(request) を入口とする」という事実だけ押さえれば、Cloudflare/Bun/Deno/Node どれでも同じ書き味になることを納得できる。
