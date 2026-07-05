# 呼び出しグラフとリファレンス

## 1. CLI モード コールグラフ

```
main()  [main.go:376]
  │
  ▼
setupLog()  [log.go:21]
  │
  ▼
rootCmd.Execute()  (cobra)
  │
  ├─ PersistentPreRunE: validateOptions()  [main.go:167]
  │     ├─ viper.Get*  (flag / env / yaml)
  │     ├─ validateStyle()  [main.go:155]
  │     │    └─ styles.DefaultStyles / utils.ExpandPath / os.Stat
  │     ├─ term.IsTerminal(os.Stdout.Fd())  →  style="notty" 切替
  │     └─ term.GetSize / width クランプ
  │
  └─ RunE: execute()  [main.go:224]
        ├─ stdinIsPipe()  [main.go:213]
        │
        ├─ [stdin pipe]  → executeCLI(cmd, src=Stdin, Stdout)
        │
        ├─ [args=0]      → runTUI("", "")
        │
        ├─ [args=1 & dir] → runTUI(absPath, "")
        │
        └─ [args=1 file]
              executeArg()  [main.go:265]
                ├─ sourceFromArg(arg)  [main.go:75]
                │    ├─ arg=="-"          → stdin
                │    ├─ readmeURL()      [url.go:29]
                │    │    ├─ findGitHubREADME  [github.go:14]
                │    │    └─ findGitLabREADME  [gitlab.go]
                │    ├─ http.Get
                │    ├─ os.Stat + filepath.Walk (dir 内 README 探索)
                │    └─ os.Open (普通のファイル)
                │
                └─ executeCLI()  [main.go:275]
                      ├─ io.ReadAll
                      ├─ utils.RemoveFrontmatter()    [utils/utils.go:18]
                      ├─ utils.IsMarkdownFile()       [utils/utils.go:53]
                      ├─ glamour.NewTermRenderer(
                      │      utils.GlamourStyle(),   [utils/utils.go:73]
                      │      WithWordWrap, WithBaseURL, WithPreservedNewLines)
                      ├─ utils.WrapCodeBlock()       [utils/utils.go:44]  (isCode 時)
                      ├─ r.Render(content)            (glamour 内部)
                      └─ switch:
                            ├─ pager:  exec.Command(PAGER) ← strings.NewReader(out)
                            ├─ tui:    runTUI(path, content)
                            └─ else:   fmt.Fprint(w, out)
```

## 2. TUI モード コールグラフ

```
runTUI(path, content)  [main.go:349]
  ├─ env.ParseAs[ui.Config]()
  ├─ validateStyle / cfg フィールド埋め
  └─ ui.NewProgram(cfg, content).Run()  [ui/ui.go:32]
        ├─ newModel(cfg, content)  [ui/ui.go:133]
        │    ├─ initSections()
        │    ├─ HasDarkBackground → GlamourStyle 決定
        │    ├─ newPagerModel  [pager.go:108]
        │    │    ├─ viewport.New(0,0)
        │    │    └─ initWatcher (fsnotify)
        │    ├─ newStashModel  [stash.go:376]
        │    │    ├─ spinner.New
        │    │    ├─ textinput.New
        │    │    └─ paginator 初期化
        │    └─ state 決定 (Path が dir / file / 空 で分岐)
        │
        └─ tea.Program.Run()
             ├─ Init()  [ui/ui.go:186]
             │    ├─ spinner.Tick
             │    ├─ [stash] findLocalFiles  [ui/ui.go:357]
             │    │           └─ gitcha.FindFiles{,All}Except → chan
             │    └─ [doc]   os.ReadFile + renderWithGlamour
             │
             ├─ Update(WindowSizeMsg)  [ui/ui.go:264]
             │    ├─ stash.setSize
             │    └─ pager.setSize
             │
             ├─ Update(KeyMsg)
             │    ├─ ctrl+c → tea.Quit
             │    ├─ ctrl+z → tea.Suspend
             │    ├─ esc/h/left/delete → unloadDocument
             │    └─ 子モデルに委譲:
             │         ├─ stash.update  [stash.go:412]
             │         │    ├─ handleDocumentBrowsing  [stash.go:461]
             │         │    │    ├─ k/j/up/down/g/G  → moveCursor*
             │         │    │    ├─ enter → openMarkdown → loadLocalMarkdown
             │         │    │    ├─ "/"   → filterState=filtering
             │         │    │    ├─ e     → openEditor
             │         │    │    └─ F     → findLocalFiles (再検索)
             │         │    └─ handleFiltering  [stash.go:601]
             │         │         └─ filterMarkdowns  (sahilm/fuzzy)
             │         │
             │         └─ pager.update  [pager.go:181]
             │              ├─ g/G/d/u/home/end → viewport scroll
             │              ├─ e → openEditor  [editor.go:10]
             │              ├─ c → termenv.Copy + clipboard.WriteAll
             │              ├─ r → loadLocalMarkdown
             │              └─ ? → toggleHelp
             │
             ├─ Update(initLocalFileSearchMsg)  → findNextLocalFile
             │
             ├─ Update(foundLocalFileMsg)
             │    ├─ stash.addMarkdowns + sortMarkdowns
             │    └─ findNextLocalFile (再帰)
             │
             ├─ Update(localFileSearchFinished)  → loaded=true
             │
             ├─ Update(fetchedMarkdownMsg)
             │    └─ renderWithGlamour  [pager.go:410]
             │         └─ glamourRender  [pager.go:421]
             │              ├─ glamour.NewTermRenderer
             │              ├─ r.Render
             │              └─ 行番号付与 + lipgloss MaxWidth 切り詰め
             │
             ├─ Update(contentRenderedMsg)
             │    ├─ state = stateShowDocument
             │    ├─ pager.setContent → viewport.SetContent
             │    └─ pager.watchFile  [pager.go:490]  (fsnotify)
             │
             ├─ Update(reloadMsg)         → loadLocalMarkdown
             ├─ Update(editorFinishedMsg) → loadLocalMarkdown
             │
             └─ View()
                  ├─ stateShowStash    → stash.view  [stash.go:670]
                  └─ stateShowDocument → pager.View  [pager.go:282]
                                          └─ viewport.View + statusBarView
```

## 3. メッセージ型早見表

| Msg 型                       | 定義場所             | 発生源                                  | ハンドラ                          |
|------------------------------|----------------------|-----------------------------------------|-----------------------------------|
| `tea.KeyMsg`                 | bubbletea            | キー入力                                | `ui.go:216`, `pager.go:188`, `stash.go:468` |
| `tea.WindowSizeMsg`          | bubbletea            | 起動 / resize                           | `ui.go:264`, `pager.go:269`       |
| `spinner.TickMsg`            | bubbles              | spinner 自己 tick                       | `stash.go:428`                    |
| `errMsg`                     | `ui.go:51`           | 任意の Cmd エラー時                     | `ui.go:207` (fatalErr に保存)     |
| `initLocalFileSearchMsg`     | `ui.go:56`           | `findLocalFiles`                        | `ui.go:270`                       |
| `foundLocalFileMsg`          | `ui.go:63`           | `findNextLocalFile`                     | `ui.go:292`                       |
| `localFileSearchFinished`    | `ui.go:64`           | チャネルクローズ                        | `ui.go:284`                       |
| `statusMessageTimeoutMsg`    | `ui.go:65`           | `time.Timer` 経由                       | `pager.go:272`, `stash.go:435`    |
| `fetchedMarkdownMsg`         | `stash.go:55`        | `loadLocalMarkdown`                     | `ui.go:275`                       |
| `filteredMarkdownMsg`        | `stash.go:54`        | `filterMarkdowns`                       | `ui.go:303`, `stash.go:423`       |
| `contentRenderedMsg`         | `pager.go:81`        | `renderWithGlamour`                     | `ui.go:281`, `pager.go:248`       |
| `reloadMsg`                  | `pager.go:82`        | fsnotify Watcher                        | `pager.go:258`                    |
| `editorFinishedMsg`          | `editor.go:8`        | `tea.ExecProcess` 完了                  | `pager.go:264`                    |

## 4. 主要 Cmd ファクトリ早見表

| 関数                          | 場所                | 戻り値の Msg                           |
|-------------------------------|---------------------|-----------------------------------------|
| `findLocalFiles(commonModel)` | `ui.go:357`         | `initLocalFileSearchMsg` / `errMsg`     |
| `findNextLocalFile(model)`    | `ui.go:400`         | `foundLocalFileMsg` / `localFileSearchFinished` |
| `loadLocalMarkdown(*markdown)`| `stash.go:852`      | `fetchedMarkdownMsg` / `errMsg`         |
| `filterMarkdowns(stashModel)` | `stash.go:868`      | `filteredMarkdownMsg`                   |
| `renderWithGlamour(pagerModel, string)` | `pager.go:410` | `contentRenderedMsg` / `errMsg`     |
| `openEditor(path, lineno)`    | `editor.go:10`      | `editorFinishedMsg` (via tea.ExecProcess) |
| `waitForStatusMessageTimeout(ctx, timer)` | `ui.go:414` | `statusMessageTimeoutMsg`         |

## 5. キーバインド早見表

### stash (一覧画面)
| キー        | 動作                          |
|-------------|-------------------------------|
| `k` / `↑`   | カーソル上                    |
| `j` / `↓`   | カーソル下                    |
| `g` / home  | 先頭                          |
| `G` / end   | 末尾                          |
| `b` / `u`   | ページ戻る                    |
| `f` / `d`   | ページ進む                    |
| `tab` / `L` | セクション切替                |
| `Enter`     | 選択ファイルを開く            |
| `/`         | filter (fuzzy) モード         |
| `e`         | EDITOR で開く                 |
| `F`         | ファイル一覧を再検索          |
| `r`         | 再起動 (Init を呼び直す)      |
| `?`         | 全ヘルプ                      |
| `q`         | 終了                          |
| `ctrl+c`    | 終了 (どこでも)               |
| `ctrl+z`    | サスペンド                    |

### pager (本文画面)
| キー        | 動作                          |
|-------------|-------------------------------|
| `j/k/↑/↓/page/space` | スクロール (viewport が処理) |
| `g` / home  | 先頭にジャンプ                |
| `G` / end   | 末尾にジャンプ                |
| `u`         | 半ページ上                    |
| `d`         | 半ページ下                    |
| `e`         | EDITOR で現在の行から開く     |
| `c`         | 本文をクリップボードにコピー  |
| `r`         | リロード                      |
| `?`         | ヘルプトグル                  |
| `esc/h/←/delete` | 一覧に戻る              |
| `q`         | 終了                          |
