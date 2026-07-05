# 03. Router Deep Dive — 5 種類の Router を一気に押さえる

Hono の特徴の半分は **router の選択肢が複数ある** こと。普段は `SmartRouter(RegExp, Trie)` で十分だが、コードを読むときに混乱しないよう全体像を 1 ページで整理する。

---

## 1. インタフェース (この 2 行を覚える)

```ts
// router.ts
export interface Router<T> {
  name: string
  add(method: string, path: string, handler: T): void
  match(method: string, path: string): Result<T>
}

// Result の形 (T = [handler, RouterRoute])
export type Result<T> =
  | [[T, ParamIndexMap][], ParamStash]   // RegExp 系: handler + 「k 番目の paramStash を使う」index map
  | [[T, Params][]]                       // Trie/Linear 系: handler + 解決済みの key→value
```

- `ParamIndexMap` 形式は、param の文字列値を **共有配列 `paramStash`** に放り込み、handler ごとには「どの index か」だけ持つ — copy を減らす最適化。
- `Params` 形式 (object) は素直な map。Trie/Linear はこちらを使う。
- どちらの形式でも `HonoRequest#param` は同じ API で吸収する (`request.ts:106-128`)。

---

## 2. 5 種の比較表

| Router | 戦略 | 登録時間 | match 時間 | 制約 | 用途 |
|---|---|---|---|---|---|
| **RegExpRouter** | 全 route を 1 つの大 regex に compile | 重い (lazy build) | **最速 / O(マッチ数)** | 衝突するパターン (例: `:a` と `*` の重複) でエラー → `UnsupportedPathError` | Hono デフォルト第一候補。Cloudflare Workers 等の "1 回起動して長時間動く" 環境で最強 |
| **TrieRouter** | 文字 trie の DFS | 軽い | 速い | 制約少ない (どんなパターンでも食う) | RegExpRouter が落ちた時のフォールバック |
| **SmartRouter** | RegExp → Trie の自動選択 | (試行ぶん) | 確定後は委譲 (関数 bind) | — | `new Hono()` (= デフォルト `hono.ts`) |
| **LinearRouter** | for ループで route 配列を線形走査 | **O(1) / 超軽量** | O(n) | — | `hono/quick` preset。**コールドスタートが極端に短い環境** (e.g. Lambda の毎回起動) 用 |
| **PatternRouter** | Web 標準 `URLPattern` API | 軽い | 中 | runtime が `URLPattern` を実装している必要あり | `hono/tiny` preset。バンドルサイズ最小 |

---

## 3. SmartRouter — どう「賢く」切り替わるか

```ts
// router/smart-router/router.ts:21-50 (要約)
match(method, path) {
  for (let i = 0; i < routers.length; i++) {
    const router = routers[i]
    try {
      // routes 配列をその router にバルク add
      for (const r of routes) router.add(...r)
      res = router.match(method, path)
    } catch (e) {
      if (e instanceof UnsupportedPathError) continue
      throw e
    }
    // ☆ 成功したら以後の match を直接そっちに委譲
    this.match = router.match.bind(router)
    this.#routers = [router]
    this.#routes = undefined
    break
  }
  return res
}
```

**ここの面白さ**:
- `this.match = router.match.bind(router)` で **自身の `match` メソッドを上書き** している。2 回目以降の呼び出しは SmartRouter のオーバーヘッドゼロ。
- `UnsupportedPathError` を catch して次の router を試すという、典型的な「easy first, fallback to robust」パターン。
- 失敗の例: `RegExpRouter` は `/:foo/*` + `/:foo/bar` のような衝突 path を扱えないので、こういう route 群があると Trie に落ちる。

---

## 4. RegExpRouter のしくみ (概要)

中身は深いので **読む順序の指針** だけ:

1. `router/reg-exp-router/index.ts` (公開 export)
2. `router/reg-exp-router/router.ts`
   - `#routes` に登録を貯める → 最初の `match` で `buildAllMatchers()` を呼んで method ごとに matcher を build。
   - `buildMatcherFromPreprocessedRoutes` (router.ts:34-) が:
     - 全 path を `Trie` (`router/reg-exp-router/trie.ts`) に入れる
     - trie から 1 つの **巨大 RegExp** を `buildRegExp()` で生成
     - 各 path に対して "param 名 → capture group の index" のマップを作る (`ParamIndexMap`)
3. `match` 時 (`matcher.ts` の `match` 関数):
   - **静的 path は `staticMap` を直接 lookup** (regex を回さない)
   - 動的な path は 1 回 regex に投げて、命中した group から `paramStash` を作る

つまり「動的 path 群を 1 つの regex に圧縮 + 静的 path は hash lookup」という二段構え。

---

## 5. TrieRouter (`router/trie-router/node.ts`)

- DOM 風の `Node` クラス。`children: Record<string, Node>` + `patterns: Pattern[]` + `methods: Record<string, HandlerSet[]>`.
- `insert(method, path, handler)`:
  - path を `/` で split し、各 segment ごとに `:label`, `:label{regex}`, `*` をパターン化して保持。
  - method ごとに handler を貯める。
- `search(method, path)`:
  - DFS で children を辿りつつ、param/regex セグメントの match を試す。
  - `*` ワイルドカードで「ここまでに通った middleware を全部拾う」挙動。
- 落ち着いて読めば JS の trie 実装としてオーソドックス。`node.test.ts` (26K) の振る舞いが網羅されていて、テストから挙動を学ぶのも有効。

---

## 6. LinearRouter (`router/linear-router/router.ts`)

- ルート配列を持つだけ。match は **for ループで全件走査**。
- 速度は劣るが、build コストが完全に 0 なので **「リクエスト 1 回で死ぬ環境」** (短命 Lambda 等) に最適。`hono/quick` プリセットがこれを使う。
- 実装は素直で読みやすい (~145 行)。最初の router 入門としては実はここから始めるのもアリ。

---

## 7. PatternRouter (`router/pattern-router/router.ts`)

- Web 標準 `URLPattern` を使う。`new URLPattern({ pathname: '/users/:id' })` をそのまま route ごとに保持。
- バンドルサイズが最も小さい (= `hono/tiny`)。
- 制約: `URLPattern` API が無い古い Node では動かない。

---

## 8. パス表記の対応表

| 書き方 | 意味 | 例 |
|---|---|---|
| `/users/:id` | 必須 param | `/users/42` → `id=42` |
| `/users/:id?` | optional param (= 内部で 2 route に展開: `/users` と `/users/:id`) | `checkOptionalParameter` (`utils/url.ts`) |
| `/users/:id{[0-9]+}` | regex 制約付き param | `/users/abc` は match しない |
| `/static/*` | wildcard (残り全部) | `/static/img/x.png` |
| `*` | catch-all (`use` で多用) | — |

---

## 9. 「読むなら何分？」目安

- インタフェース (`router.ts`) … 5 分
- `smart-router/router.ts` … 5 分 (短い)
- `linear-router/router.ts` … 10 分
- `trie-router/node.ts` の insert/search だけ … 15 分
- `reg-exp-router/` 全体 … 30〜45 分 (深掘りしないなら飛ばして OK)

普段の開発で router の内部を意識する場面はほぼ無いので、**「Smart = RegExp + Trie の自動 fallback」** とだけ覚えれば実用上十分。

---

次は `04-context-and-middleware.md` で、handler を書くときに毎日触る `c.*` の API と middleware 作成パターン。
