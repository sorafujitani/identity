# CLI モード実行フロー — main() から Markdown が画面に出るまで

このドキュメントは "glow README.md" のように **1 ファイルを引数で渡した場合**
の実行フローを、対応するソース位置とともに追う。一番シンプルな道。

> 行番号は `git clone --depth=1` 時点 (master) のもの。

## 0. プロセス起動前: `init()` (`main.go:389-429`)

Go のプロセスは `main()` より先に各パッケージの `init()` を呼ぶ。
glow では `main.go` の `init()` で:

1. `tryLoadConfigFromDefaultPlaces()` (`main.go:431`)
   - `gap.NewScope(gap.User, "glow")` で XDG 準拠の config dir を列挙
   - `XDG_CONFIG_HOME` / `GLOW_CONFIG_HOME` を最優先に前置
   - viper に search path を全部突っ込み、`glow.yaml` を読みに行く
   - ファイルが無ければ `ensureConfigFile()` で `defaultConfig` (yaml 文字列) を
     `~/.config/glow/glow.yml` などに書き出す (`config_cmd.go:56-88`)。
2. `Version` / `CommitSHA` の埋め込み (goreleaser がリンク時に注入)
3. **`rootCmd` への flag 登録** (`main.go:402-411`)
   - `--config`, `--pager`, `--tui`, `--style`, `--width`, `--all`,
     `--line-numbers`, `--preserve-new-lines`, `--mouse` (hidden)
4. **viper への flag バインド** (`main.go:414-422`)
   - これにより flag が CLI / 環境変数 / config ファイルの統合 lookup になる
5. `rootCmd.AddCommand(configCmd, manCmd)` で `glow config` と `glow man` を追加

`url.go:22-27` の `init()` も同時に動き、`https://github.com` / `https://gitlab.com`
を `url.URL` としてプリパースしておく (`sync.Once` で 1 回だけ)。

## 1. `main()` (`main.go:376-387`)

```go
func main() {
    closer, err := setupLog()        // ① ログ初期化
    if err != nil { ...; os.Exit(1) }
    if err := rootCmd.Execute(); err != nil {  // ② cobra のメインループ
        _ = closer()
        os.Exit(1)
    }
    _ = closer()
}
```

- `setupLog()` (`log.go:21`) は `~/.cache/glow/glow.log` を `os.O_APPEND` で
  開いて `log.SetOutput(f)` する。ファイル作成失敗時は **黙ってログ無効化**。
  返り値 `closer` は最後に `f.Close()` を呼ぶ。
- `rootCmd.Execute()` は cobra 標準。

## 2. cobra のライフサイクル

`rootCmd` の定義 (`main.go:48-66`) で重要なのは:
- `PersistentPreRunE: func(cmd, _) error { return validateOptions(cmd) }`
- `RunE: execute`
- `Args: cobra.MaximumNArgs(1)` — 引数は 0 or 1 個

cobra は次の順で呼ぶ:
```
PersistentPreRunE → validateOptions → RunE → execute
```

### `validateOptions` (`main.go:167-211`)

ここで **viper の値を package-level の変数にコピー** している:

```go
width  = viper.GetUint("width")
mouse  = viper.GetBool("mouse")
pager  = viper.GetBool("pager")
tui    = viper.GetBool("tui")
showAllFiles      = viper.GetBool("all")
preserveNewLines  = viper.GetBool("preserveNewLines")
showLineNumbers   = viper.GetBool("showLineNumbers")
```

そのあとで:
- `pager && tui` の同時指定はエラー
- `validateStyle(style)` (`main.go:155`): "auto" 以外で `styles.DefaultStyles`
  にないなら **JSON ファイルパス** と解釈し、`utils.ExpandPath` で `~` 展開して
  `os.Stat` で存在確認
- `term.IsTerminal(os.Stdout.Fd())` で TTY 判定。**非 TTY なら style="notty"** に
  自動切替 (パイプ先で ANSI を吐かないため)。
- width 未指定なら `term.GetSize` で取得し、120 以上なら 120 にクランプ、
  取得失敗時は 80。

## 3. `execute(cmd, args)` (`main.go:224-263`)

```go
if yes, err := stdinIsPipe(); err != nil { ... } else if yes {
    src := &source{reader: os.Stdin}
    return executeCLI(cmd, src, os.Stdout)   // ← stdin pipe ルート
}
switch len(args) {
case 0:
    return runTUI("", "")
case 1:
    info, err := os.Stat(args[0])
    if err == nil && info.IsDir() {
        return runTUI(absPath, "")            // ← ディレクトリ → TUI
    }
    fallthrough
default:
    for _, arg := range args {
        if err := executeArg(cmd, arg, os.Stdout); err != nil { return err }
    }
}
```

`stdinIsPipe()` (`main.go:213-222`) は `os.Stdin.Stat()` の `Mode & ModeCharDevice == 0`
**もしくは** `Size > 0` で判定。前者がパイプ判定、後者はリダイレクト用ガード。

ここでは **1 引数でファイルを渡したケース** を追うので、`fallthrough` で
`executeArg` に進む。

## 4. `executeArg` (`main.go:265-273`)

```go
func executeArg(cmd, arg, w) error {
    src, err := sourceFromArg(arg)
    if err != nil { return err }
    defer src.reader.Close()
    return executeCLI(cmd, src, w)
}
```

`source` は `main.go:69-72`:
```go
type source struct {
    reader io.ReadCloser
    URL    string
}
```

## 5. `sourceFromArg(arg)` (`main.go:75-151`)

引数の種別を上から順に試す **多段ディスパッチ**:

| 優先度 | 条件                              | 結果                                                |
|--------|-----------------------------------|-----------------------------------------------------|
| 1      | `arg == "-"`                      | stdin                                               |
| 2      | `readmeURL(arg)` 成功             | GitHub/GitLab API 経由で README をフェッチ          |
| 3      | `url.ParseRequestURI` 成功 & `://` 含む | `http.Get` で HTTP/HTTPS をダウンロード         |
| 4      | `os.Stat(arg).IsDir()`            | `filepath.Walk` で README.md らしきものを探す       |
| 5      | それ以外                          | `os.Open(arg)` で普通のファイルとして開く           |

`readmeURL` (`url.go:29-59`):
- `github://owner/repo` 形式と `gitlab://owner/repo` 形式をサポート
- それ以外でも `https://` を付けてホスト名で GitHub/GitLab を判定
- マッチすれば `findGitHubREADME` / `findGitLabREADME` に委譲。GitHub の場合
  `https://api.github.com/repos/{o}/{r}/readme` を叩いて `download_url` を取り、
  さらに `http.Get` して `*source{Body, URL}` を返す (`github.go:14-57`)。

**今回のケース (ローカルファイル)** は 5 段目に落ちて `os.Open(arg)` で
`*os.File` (= `io.ReadCloser`) を取得、`filepath.Abs(arg)` で絶対パスを URL
フィールドに入れる。

## 6. `executeCLI(cmd, src, w)` (`main.go:275-347`)

**ここが描画の本体**。

### 6.1 全部読み込む
```go
b, err := io.ReadAll(src.reader)        // ファイル/HTTP body をメモリに展開
b = utils.RemoveFrontmatter(b)          // YAML フロントマターを剥がす
```

`utils.RemoveFrontmatter` (`utils/utils.go:18-32`):
```go
var yamlPattern = regexp.MustCompile(`(?m)^---\r?\n(\s*\r?\n)?`)
```
を `FindAllIndex(c, 2)` で **2 個** マッチさせ、両方の `---` で囲まれた範囲を
切り落とす。**ファイル先頭がフロントマターでないなら何もしない** (matches[0][0] != 0
チェック)。

### 6.2 baseURL の決定
```go
u, err := url.ParseRequestURI(src.URL)
if err == nil {
    u.Path = filepath.Dir(u.Path)
    baseURL = u.String() + "/"
}
```
relative 画像リンクなどを解決するための base。ローカルファイルでも URL として
パースを試みている (失敗しても baseURL は空のまま進む)。

### 6.3 ファイル種別判定
```go
isCode := !utils.IsMarkdownFile(src.URL)
```

`utils.IsMarkdownFile` (`utils/utils.go:53-70`):
- 拡張子なし → markdown 扱い (true)
- `.md .mdown .mkdn .mkd .markdown` のいずれか → true
- それ以外 → false (=コードファイル扱い)

つまり `glow main.go` のように **コードファイルを渡すと、glow は内容を
` ```go ... ``` ` でラップしてシンタックスハイライト** する。

### 6.4 glamour レンダラ初期化
```go
r, err := glamour.NewTermRenderer(
    glamour.WithColorProfile(lipgloss.ColorProfile()),
    utils.GlamourStyle(style, isCode),
    glamour.WithWordWrap(int(width)),
    glamour.WithBaseURL(baseURL),
    glamour.WithPreservedNewLines(),
)
```

`utils.GlamourStyle(style, isCode)` (`utils/utils.go:73-113`) が結構トリッキー:
- **markdown のとき** は `glamour.WithAutoStyle()` (auto) または
  `glamour.WithStylePath(style)` を返すだけ
- **コードのとき** は、auto/dark/light/pink/notty/dracula/tokyo-night の組込み
  `StyleConfig` をコピーし、`CodeBlock.Margin = 0` にしてから
  `glamour.WithStyles(styleConfig)` を返す。これで `WrapCodeBlock` で囲んだ
  時の余計なインデントを潰している。

### 6.5 レンダリング
```go
content := string(b)
ext := filepath.Ext(src.URL)
if isCode {
    content = utils.WrapCodeBlock(string(b), ext)   // ```go ... ```
}
out, err := r.Render(content)                       // ← 実際の変換
```

`r.Render` の内部は glamour が goldmark で AST にパース → `ansi` レンダラで
ANSI エスケープ付き文字列を生成する。glow はこれを **不透明な文字列として
受け取る** だけ。中身を見たいなら `glamour` リポジトリを別途読む。

### 6.6 出力先の分岐
```go
switch {
case pager || cmd.Flags().Changed("pager"):
    pagerCmd := os.Getenv("PAGER")
    if pagerCmd == "" { pagerCmd = "less -r" }
    fields, _ := shell.Fields(pagerCmd, os.Getenv)   // "less -r" → ["less", "-r"]
    c := exec.Command(fields[0], fields[1:]...)
    c.Stdin  = strings.NewReader(out)                // ★ レンダ結果を pager に流す
    c.Stdout = os.Stdout
    c.Run()

case tui || cmd.Flags().Changed("tui"):
    path := ""
    if !isURL(src.URL) { path = src.URL }
    return runTUI(path, content)                     // 04 番ドキュメント参照

default:
    fmt.Fprint(w, out)                               // ← stdout に書く (99% これ)
}
```

`shell.Fields` は `mvdan.cc/sh/v3/shell` 製で、`PAGER="less -r --quit-at-eos"`
のような shell っぽい記法を正しく分解できる。

## 7. CLI モードのコールスタック (まとめ)

```
main()                                           main.go:376
└─ rootCmd.Execute()                             cobra
   └─ PersistentPreRunE → validateOptions        main.go:167
   └─ RunE → execute                             main.go:224
      └─ executeArg                              main.go:265
         ├─ sourceFromArg                        main.go:75
         │  └─ os.Open / http.Get / readmeURL    main.go / url.go / github.go
         └─ executeCLI                           main.go:275
            ├─ io.ReadAll
            ├─ utils.RemoveFrontmatter           utils/utils.go:18
            ├─ utils.IsMarkdownFile              utils/utils.go:53
            ├─ glamour.NewTermRenderer(...)      external
            │  └─ utils.GlamourStyle             utils/utils.go:73
            ├─ utils.WrapCodeBlock (isCode 時)   utils/utils.go:44
            ├─ r.Render(content)                 external (glamour)
            └─ switch { pager / tui / stdout }
```

## 8. ありがちな読み迷いポイント

- **`width` などが package-level 変数**。`init` で flag に紐付け、`validateOptions`
  で viper から再読込、`executeCLI` 内では package-level を直接参照。テストし
  にくい設計だが、CLI のグローバル設定として割り切っている。
- **`source.URL` は URL とは限らない**。ローカルファイルなら絶対パス、
  stdin なら空文字列。baseURL 計算と isCode 判定の両方で使い回している。
- **`glamour.WithBaseURL` は relative リンクの解決用**で、表示テキストには
  影響しない。リンク先 URL の組み立てだけ。
- **`exec.Command` の Stdin を `strings.NewReader(out)` にしている** ことで、
  `less` に直接パイプしている。stdout/stderr は親プロセスのものをそのまま。
