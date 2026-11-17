# このフォークについて（azooKey Shift）

[azooKey/azooKey-Desktop](https://github.com/azooKey/azooKey-Desktop) の個人用フォークです。日本語入力中に **Shift+英字で一時的な英字入力に入る機能**を加えています。公式リポジトリへの提案（PR）は目的としていません。

## 追加した機能

- 日本語入力中に Shift+英字（A–Z）を押すと、一時英字入力に入る。Shift を離しても英字入力が続く（例：`Shift+S` `h` `i` `f` `t` → `Shift`）。
- Enter / F10 / かなキーで確定して日本語入力に戻る。Escape でキャンセルする。Backspace で英字が空になると終了する。
- 日本語の未確定文字列があるときは、表示中の文字列を確定してから一時英字入力に入る。
- 英字は変換エンジンに渡さないため、一時英字入力中はかな漢字変換・ライブ変換・学習が動かない。
- 標準ローマ字と AZIK でだけ有効。かな入力とカスタム入力テーブルでは従来どおり。
- 隠し設定 `…preference.temporaryEnglishInputByShift` で無効にできる。

実装は `InputState.temporaryEnglish(String)`（`Core/Sources/Core/InputUtils/InputState.swift`）を中心にしています。テストは `Core/Tests/CoreTests/InputUtilsTests/InputStateTemporaryEnglishTests.swift` にあります。

## ブランチ

| ブランチ | 内容 |
|---|---|
| `feature/shift-english`（既定） | 上流の main に、この機能のコミットを重ねたもの |
| `main` | 上流の main をそのまま映すだけ（独自のコミットは載せない） |

このフォークの既定ブランチは `feature/shift-english` です。スケジュール実行と手動実行のワークフローは、既定ブランチ上のものしか動かないためです。

## CI

| ワークフロー | 実行のタイミング | 内容 |
|---|---|---|
| `fork-ci.yml` | `feature/shift-english` への push、手動 | macos-26（Xcode 26 系）で SwiftLint `--strict`、Core のビルドとテスト、Release ビルド（署名なし） |
| `upstream-check.yml` | 毎週、手動 | 上流 main の更新を検出し、更新があればランナー上だけで rebase して、テストとビルドを行う（書き戻しはしない） |
| `swift.yml`（上流のもの） | （このフォークでは無効） | 上流の CI（macos-15 / Xcode 16.3、Ubuntu）。ファイルは変更していない |

上流の `swift.yml` は、このフォークの Actions 設定で無効にしています（macos-15 ランナーの混雑でジョブが開始されないことがあり、確認内容は `fork-ci.yml` がより新しい Xcode で担っているため）。ファイル自体は変更していないので、上流の更新とは衝突しません。

どのワークフローも署名はせず、証明書や Secrets を使いません。

## 上流の更新を取り込む

```bash
git fetch upstream
git switch main && git merge --ff-only upstream/main && git push origin main
git switch feature/shift-english && git rebase upstream/main
swift test --package-path Core
swiftlint --quiet --strict
git push --force-with-lease origin feature/shift-english
```

rebase で衝突した場合は、上流の変更を優先して読み、`InputState` の遷移表と `azooKeyMacInputController` の接続部分を合わせ直してください。

## ライセンス

上流と同じ MIT License です（[LICENSE](LICENSE)）。同梱するモデル（zenz）は CC-BY-SA-4.0 です。
