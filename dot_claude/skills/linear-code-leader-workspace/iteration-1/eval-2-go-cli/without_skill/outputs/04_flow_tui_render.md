# TUI モード実行フロー — runTUI() から viewport に描画されるまで

CLI モードが "一発レンダして終わり" だったのに対し、TUI モードは **Bubble Tea の
ループの中で非同期にファイルを探し → 読み込み → glamour に投げ → viewport に
セットする** という多段階のメッセージパッシングになる。

## 0. TUI モードへの 3 つの入口

`main.go: execute` から呼ばれる `runTUI` 呼び出しは 3 箇所:

| 呼び出し                       | path 引数            | content 引数 |
|--------------------------------|----------------------|--------------|
| `case 0:` 引数なし             | `""`                 | `""`         |
| `case 1:` 引数がディレクトリ   | `filepath.Abs(arg)`  | `""`         |
| `executeCLI` の `--tui` 経路   | ファイルパス or `""` | レンダ前の生 markdown |

3 つ目だけは **content が既にあるので一覧画面をスキップして直接 pager に行く**。
他の 2 つは "一覧画面 (stash) からスタートして、ユーザが選んだら pager に
遷移する" 流れ。

## 1. `runTUI(path, content)` (`main.go:349-374`)

```go
cfg, err := env.ParseAs[ui.Config]()   // ① 環境変数 → ui.Config struct
                                       //    (caarlos0/env が `env:"..."` タグを読む)
if err := validateStyle(cfg.GlamourStyle); err != nil {
    cfg.GlamourStyle = style           // env 経由のスタイルが無効なら CLI 引数で上書き
}

cfg.Path             = path
cfg.ShowAllFiles     = showAllFiles
cfg.ShowLineNumbers  = showLineNumbers
cfg.GlamourMaxWidth  = width
cfg.EnableMouse      = mouse
cfg.PreserveNewLines = preserveNewLines

if _, err := ui.NewProgram(cfg, content).Run(); err != nil { ... }
```

`ui.Config` (`ui/config.go`) の `env` タグ:
- `GOPATH`, `HOME` → そのまま読む
- `GLAMOUR_STYLE` → スタイル名
- `GLOW_HIGH_PERFORMANCE_PAGER` (default `true`) → 高速ページャ有効
- `GLOW_ENABLE_GLAMOUR` (default `true`) → false にすると glamour を通さず素の Markdown を出す (デバッグ用)

## 2. `ui.NewProgram(cfg, content)` (`ui/ui.go:32-49`)

```go
config = cfg                            // ← package-level 変数に保存 (glamourRender が参照)
opts := []tea.ProgramOption{tea.WithAltScreen()}
if cfg.EnableMouse {
    opts = append(opts, tea.WithMouseCellMotion())
}
m := newModel(cfg, content)
return tea.NewProgram(m, opts...)
```

`tea.WithAltScreen()` は vim 等と同じ "代替画面バッファ" の使用。終了時に元の
画面に戻る。

## 3. `newModel(cfg, content)` (`ui/ui.go:133-184`)

ここで **初期状態を決定** する重要なロジック:

```go
initSections()      // stash の paginator section をマップに初期化

// スタイルが auto なら、termenv の HasDarkBackground() で dark/light を確定
if cfg.GlamourStyle == styles.AutoStyle {
    if te.HasDarkBackground() {
        cfg.GlamourStyle = styles.DarkStyle
    } else {
        cfg.GlamourStyle = styles.LightStyle
    }
}

common := commonModel{cfg: cfg}
m := model{
    common: &common,
    state:  stateShowStash,
    pager:  newPagerModel(&common),
    stash:  newStashModel(&common),
}

// ★ 入口で分岐
path := cfg.Path
if path == "" && content != "" {
    // executeCLI から --tui で来たケース
    m.state = stateShowDocument
    m.pager.currentDocument = markdown{Body: content}
    return m
}
if path == "" { path = "." }
info, err := os.Stat(path)
if info.IsDir() {
    m.state = stateShowStash     // 一覧モード
} else {
    cwd, _ := os.Getwd()
    m.state = stateShowDocument  // 単一ファイルモード
    m.pager.currentDocument = markdown{
        localPath: path,
        Note:      stripAbsolutePath(path, cwd),
        Modtime:   info.ModTime(),
    }
}
```

`newPagerModel` (`pager.go:108-121`) は `viewport.New(0, 0)` を作り、
`HighPerformanceRendering = config.HighPerformancePager` を立て、fsnotify
ウォッチャを初期化する。

`newStashModel` (`stash.go:376-400`) は spinner / textinput / paginator
sections を組み立て。

## 4. `tea.Program.Run()` → メインループ開始

Bubble Tea のランタイムが:
1. `model.Init()` を呼んで初期 Cmd を発射
2. `tea.WindowSizeMsg` を 1 回送って初期サイズを通知
3. 以後、キー入力・Cmd の戻り値などの Msg をひたすら `Update` に流す
4. 毎フレーム `View()` を呼んで描画

## 5. `model.Init()` (`ui/ui.go:186-203`)

```go
cmds := []tea.Cmd{m.stash.spinner.Tick}    // スピナーのアニメ開始

switch m.state {
case stateShowStash:
    cmds = append(cmds, findLocalFiles(*m.common))
case stateShowDocument:
    content, err := os.ReadFile(m.common.cfg.Path)
    if err != nil { ... return errMsg{err} }
    body := string(utils.RemoveFrontmatter(content))
    cmds = append(cmds, renderWithGlamour(m.pager, body))
}
return tea.Batch(cmds...)
```

**2 つのルートに枝分かれ**:
- 一覧モード → `findLocalFiles` Cmd (= ファイル検索を別 goroutine で開始)
- 単一ファイルモード → 即座に `os.ReadFile` → `renderWithGlamour` Cmd

ここでは **単一 Markdown ファイルを `glow README.md` のように開いた場合では
なく、引数なし or ディレクトリ指定で一覧モードに入った場合** を中心に追う。

## 6. 一覧モード: ファイル発見の生産者-消費者パターン

### 6.1 `findLocalFiles` Cmd (`ui/ui.go:357-398`)

```go
return func() tea.Msg {
    cwd, _ := os.Getwd()       // or cfg.Path を解決
    var ch chan gitcha.SearchResult
    if m.cfg.ShowAllFiles {
        ch, err = gitcha.FindAllFilesExcept(cwd, markdownExtensions, nil)
    } else {
        ch, err = gitcha.FindFilesExcept(cwd, markdownExtensions, ignorePatterns(m))
    }
    return initLocalFileSearchMsg{ch: ch, cwd: cwd}
}
```

`gitcha` は **`.gitignore` を尊重しながら** walk するライブラリで、`chan
gitcha.SearchResult` を返す。Walk は goroutine 内で進み、チャネルにヒットを
push してくる。

`ignorePatterns` は OS 別 (`ignore_general.go` / `ignore_darwin.go`) で
`.DS_Store` や `node_modules` 等の除外パターンを返す。

### 6.2 `initLocalFileSearchMsg` を受信 (`ui/ui.go:270-273`)

```go
case initLocalFileSearchMsg:
    m.localFileFinder = msg.ch          // チャネルを Model に保持
    m.common.cwd = msg.cwd
    cmds = append(cmds, findNextLocalFile(m))   // 1 個取り出すループへ
```

### 6.3 `findNextLocalFile` Cmd (`ui/ui.go:400-412`)

```go
return func() tea.Msg {
    res, ok := <-m.localFileFinder
    if ok {
        return foundLocalFileMsg(res)              // 見つかった
    }
    return localFileSearchFinished{}               // チャネルが閉じた
}
```

**重要なイディオム**: 1 個取り出すごとに新しい Cmd を作って Bubble Tea に
返すことで、`Update → Cmd → Msg → Update → Cmd → ...` のテールコール的な
ループを Bubble Tea に組み込む。ブロッキング受信をそのまま Cmd の中でやって
いいのは、Bubble Tea が各 Cmd を独立した goroutine で実行するから。

### 6.4 `foundLocalFileMsg` 受信 (`ui/ui.go:292-301`)

```go
case foundLocalFileMsg:
    newMd := localFileToMarkdown(m.common.cwd, gitcha.SearchResult(msg))
    m.stash.addMarkdowns(newMd)
    if m.stash.filterApplied() {
        newMd.buildFilterValue()
    }
    if m.stash.shouldUpdateFilter() {
        cmds = append(cmds, filterMarkdowns(m.stash))
    }
    cmds = append(cmds, findNextLocalFile(m))    // ★ 次を取りに行く再帰
```

`localFileToMarkdown` (`ui/ui.go:426-432`) は `*markdown` を組み立てる:
- `localPath` = 絶対パス
- `Note` = `stripAbsolutePath` で cwd を取った相対パス (画面表示用)
- `Modtime` = `os.FileInfo.ModTime()`

`stash.addMarkdowns` (`ui/stash.go:295-306`) は markdowns に append し、
filter 適用中でなければ `sortMarkdowns` で **修正時刻降順** にソート、
最後に `updatePagination()` でページ数を再計算。

ここまでで stash 画面のリストはユーザに見える状態。

### 6.5 `localFileSearchFinished` (`ui/ui.go:284-290`)

```go
case localFileSearchFinished:
    stashModel, cmd := m.stash.update(msg)   // stash の loaded フラグを true に
    m.stash = stashModel
    return m, cmd
```

`stash.update` 側 (`stash.go:419-421`) で `m.loaded = true` にして spinner を
止める。

## 7. ファイル選択 → 読み込み (Enter キー)

### 7.1 stash の Enter ハンドラ (`stash.go:530-540`)

```go
case keyEnter:
    m.hideStatusMessage()
    if numDocs == 0 { break }
    md := m.selectedMarkdown()         // ページ位置 + cursor から選択を取得
    cmds = append(cmds, m.openMarkdown(md))
```

### 7.2 `openMarkdown` (`stash.go:319-323`)

```go
func (m *stashModel) openMarkdown(md *markdown) tea.Cmd {
    m.viewState = stashStateLoadingDocument         // スピナーを出す
    cmd := loadLocalMarkdown(md)
    return tea.Batch(cmd, m.spinner.Tick)
}
```

### 7.3 `loadLocalMarkdown` Cmd (`stash.go:852-866`)

```go
return func() tea.Msg {
    if md.localPath == "" {
        return errMsg{errors.New("could not load file: missing path")}
    }
    data, err := os.ReadFile(md.localPath)
    if err != nil { return errMsg{err} }
    md.Body = string(data)
    return fetchedMarkdownMsg(md)
}
```

`md` はポインタなので、**Cmd の中で Body を書き換えて同じポインタを Msg として
返している**。ここが Bubble Tea 流儀的に少し違和感あるが glow ではそうしている。

### 7.4 `fetchedMarkdownMsg` 受信 (`ui/ui.go:275-279`)

```go
case fetchedMarkdownMsg:
    m.pager.currentDocument = *msg
    body := string(utils.RemoveFrontmatter([]byte(msg.Body)))
    cmds = append(cmds, renderWithGlamour(m.pager, body))
```

**ここで初めて pager に Markdown 本文が渡る**。同時に `RemoveFrontmatter` で
YAML を剥がす (CLI モードでも同じ処理をしている)。

## 8. `renderWithGlamour` (`pager.go:410-419`)

```go
return func() tea.Msg {
    s, err := glamourRender(m, md)
    if err != nil { return errMsg{err} }
    return contentRenderedMsg(s)
}
```

### `glamourRender` (`pager.go:421-480`) ─ "This is where the magic happens."

CLI モードの `executeCLI` とほぼ同じだが、TUI 用の差分がある:

```go
trunc := lipgloss.NewStyle().MaxWidth(m.viewport.Width - lineNumberWidth).Render
if !config.GlamourEnabled {
    return markdown, nil           // デバッグ用バイパス
}

isCode := !utils.IsMarkdownFile(m.currentDocument.Note)
width  := max(0, min(int(m.common.cfg.GlamourMaxWidth), m.viewport.Width))
if isCode { width = 0 }

options := []glamour.TermRendererOption{
    utils.GlamourStyle(m.common.cfg.GlamourStyle, isCode),
    glamour.WithWordWrap(width),
}
if m.common.cfg.PreserveNewLines {
    options = append(options, glamour.WithPreservedNewLines())
}
r, _ := glamour.NewTermRenderer(options...)

if isCode {
    markdown = utils.WrapCodeBlock(markdown, filepath.Ext(m.currentDocument.Note))
}
out, _ := r.Render(markdown)
if isCode { out = strings.TrimSpace(out) }

// 行番号付与 or 切り詰め
lines := strings.Split(out, "\n")
var content strings.Builder
for i, s := range lines {
    if isCode || m.common.cfg.ShowLineNumbers {
        content.WriteString(lineNumberStyle(fmt.Sprintf("%4d", i+1)))
        content.WriteString(trunc(s))
    } else {
        content.WriteString(s)
    }
    if i+1 < len(lines) { content.WriteRune('\n') }
}
return content.String(), nil
```

CLI モードと違って **viewport の幅を考慮した word-wrap**、**行番号付与**、
**1 行ごとの MaxWidth 切り詰め (`lipgloss MaxWidth`)** が入る。

## 9. `contentRenderedMsg` 受信

### 9.1 トップレベル (`ui/ui.go:281-282`)

```go
case contentRenderedMsg:
    m.state = stateShowDocument        // 一覧から pager 画面に切替
```

その後 `switch m.state` 部分 (`ui/ui.go:312-322`) で `m.pager.update(msg)` を
呼ぶ。

### 9.2 pager (`pager.go:248-255`)

```go
case contentRenderedMsg:
    log.Info("content rendered", "state", m.state)
    m.setContent(string(msg))                    // viewport.SetContent
    if m.viewport.HighPerformanceRendering {
        cmds = append(cmds, viewport.Sync(m.viewport))
    }
    cmds = append(cmds, m.watchFile)             // fsnotify 監視開始
```

`m.setContent` (`pager.go:135-137`) は `m.viewport.SetContent(s)` を呼ぶだけ。
`viewport.Sync` は HighPerformanceRendering モード時の即時再描画リクエスト。

## 10. 画面に出る: `View()` (`ui/ui.go:327-338`)

毎フレーム Bubble Tea が呼ぶ。

```go
switch m.state {
case stateShowDocument:
    return m.pager.View()    // pager.go:282
default:
    return m.stash.view()    // stash.go:670
}
```

`pagerModel.View` (`pager.go:282-294`):
```go
fmt.Fprint(&b, m.viewport.View()+"\n")   // ★ glamour が作った文字列がここで出る
m.statusBarView(&b)                       // 下部のステータスバー描画
if m.showHelp { fmt.Fprint(&b, "\n"+m.helpView()) }
return b.String()
```

`m.viewport.View()` が bubbles 提供。SetContent された文字列をスクロール位置に
従って **画面に収まる行だけ切り出して返す**。bubbletea がそれを差分付きで
ターミナルに書き出す (alternate screen)。

## 11. 単一ファイルモードの差分 (おさらい)

`newModel` で `info.IsDir() == false` の場合は `m.state = stateShowDocument`
にして `m.pager.currentDocument` に localPath / Note / Modtime をセット。

その後 `Init()` (`ui.go:193-200`) が:
```go
content, _ := os.ReadFile(m.common.cfg.Path)
body := string(utils.RemoveFrontmatter(content))
cmds = append(cmds, renderWithGlamour(m.pager, body))
```
を返すので、stash を経由せず **いきなり renderWithGlamour に飛ぶ**。
あとは 9 番以降の流れと同じ。

## 12. リサイズ・ファイル変更・編集後の再描画

### `tea.WindowSizeMsg` (`ui/ui.go:264-268`, `pager.go:269-270`)

トップレベルで stash と pager 両方に `setSize` し、pager 側では追加で
`renderWithGlamour(m, m.currentDocument.Body)` を返す。**幅が変わると
glamour のラップ幅も変わるので再レンダ**。

### fsnotify 経由の `reloadMsg`

`watchFile` (`pager.go:490-520`) は **`tea.Cmd` ではなく `tea.Msg` を返す
"待ち受け Cmd"** として contentRendered 時に発射される。

```go
for {
    select {
    case event := <-m.watcher.Events:
        if event.Name != m.currentDocument.localPath { continue }
        if !event.Has(fsnotify.Write) && !event.Has(fsnotify.Create) { continue }
        return reloadMsg{}                       // ← Msg を返してループ終了
    case err := <-m.watcher.Errors:
        ...
    }
}
```

`reloadMsg` を pager が受け取ると `loadLocalMarkdown(&m.currentDocument)` を
再発射 (`pager.go:258-259`)。`r` キーでも同じ Cmd が走る。

### `editorFinishedMsg`

`e` キーで `tea.ExecProcess(editor.Cmd("Glow", path, ...))` を発射し
(`editor.go:10-19`), `editor` プロセスが終了すると `editorFinishedMsg` が
帰ってきて、pager がそれを `loadLocalMarkdown` に変換 (`pager.go:264-265`)。

## 13. TUI モードのコールスタック (まとめ)

```
runTUI(path, content)                         main.go:349
└─ ui.NewProgram(cfg, content)                ui/ui.go:32
   └─ newModel                                 ui/ui.go:133
└─ tea.Program.Run()                          (bubbletea ランタイム)

   ┌── Init                                    ui/ui.go:186
   │    ├─ stash.spinner.Tick
   │    └─ findLocalFiles                      ui/ui.go:357
   │         └─ gitcha.FindFiles* → chan
   │              ↓ Msg
   ├── Update(initLocalFileSearchMsg)          ui/ui.go:270
   │    └─ findNextLocalFile                   ui/ui.go:400
   │         └─ <-chan
   │              ↓ Msg
   ├── Update(foundLocalFileMsg)               ui/ui.go:292
   │    ├─ stash.addMarkdowns
   │    └─ findNextLocalFile (再帰)
   │              ...
   ├── Update(localFileSearchFinished)         ui/ui.go:284
   │
   │  [ユーザが Enter]
   ├── Update(tea.KeyMsg "enter")
   │    └─ stash.handleDocumentBrowsing        stash.go:461
   │         └─ openMarkdown                    stash.go:319
   │              └─ loadLocalMarkdown          stash.go:852
   │                   └─ os.ReadFile
   │                        ↓ Msg
   ├── Update(fetchedMarkdownMsg)               ui/ui.go:275
   │    └─ renderWithGlamour                    pager.go:410
   │         └─ glamourRender                   pager.go:421
   │              └─ glamour.NewTermRenderer + r.Render
   │                   ↓ Msg
   ├── Update(contentRenderedMsg)               ui/ui.go:281
   │    ├─ state = stateShowDocument
   │    └─ pager.update → viewport.SetContent   pager.go:248
   │         └─ watchFile (fsnotify)            pager.go:490
   │
   └── View → pager.View                        ui/ui.go:327, pager.go:282
        └─ viewport.View()
```
