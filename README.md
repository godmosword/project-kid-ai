# KidsAI

給 5–8 歲孩子的 iOS App，讓孩子理解「AI 會猜、會錯、可以被教」。協作規則見 [AGENTS.md](AGENTS.md)。

## 在模擬器執行

需要 Xcode 16 以上與 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

1. `cd app && xcodegen generate`
2. 打開產生的 `app/KidsAI.xcodeproj`（接續上一步可用 `open KidsAI.xcodeproj`）
3. 在 Xcode 上方選一台 iOS 模擬器，按 Run（⌘R）

`.xcodeproj` 由 XcodeGen 產生、不進 git。專案設定只改 `app/project.yml`，改完重跑第 1 步。

## 驗證層（agent 用）

改到孩子或家長看得到的畫面時，agent 照 [verify-kidsai](.claude/skills/verify-kidsai/SKILL.md) 在專用模擬器上真的點過一遍，錄下縮時影片與最終截圖，推到公開的證據 repo [project-kid-ai-evidence](https://github.com/godmosword/project-kid-ai-evidence)，再放進 PR 描述（手機上就看得到）。每個功能怎麼走、哪些還驗證不到，見 [Feature Map](.claude/skills/verify-kidsai/references/features/README.md)；和 mid-fi 設計稿的對照見 [design-map](.claude/skills/verify-kidsai/references/design-map.md)。

### 每日自動維護

每天 03:17 在這台 Mac 上自動檢查功能地圖是否還對得上 App。**裝好之後會自動 push 分支並開 draft PR**（只改驗證 skill 的文件），給 Michael 審；失敗時跳 macOS 通知。建議先用 `maintain install --no-push` 試跑一兩天（只寫本機分支與 log），再正式安裝。安裝、查看、移除（在 repo 根目錄）：

```bash
.claude/skills/verify-kidsai/control-kidsai maintain install      # 先加 --dry-run 看會寫什麼
.claude/skills/verify-kidsai/control-kidsai maintain status
.claude/skills/verify-kidsai/control-kidsai maintain uninstall
```

每天會用掉一次完整維護的 Claude Code 額度。細節見 [SKILL.md 的 Maintain](.claude/skills/verify-kidsai/SKILL.md)。

## 語音辨識 spike（ASRSpike，只給大人在實機測試）

`ASRSpike` 是獨立的測試 App，不上架、不併入 KidsAI。測試步驟與規則見 [docs/spikes/asr-spike-protocol.md](docs/spikes/asr-spike-protocol.md)。

1. 複製 `app/Local.xcconfig.example` 成 `app/Local.xcconfig`，填入你的 Apple Developer Team ID（免費的個人帳號即可；這個檔不進 git）。Team 只在這個檔設，不要在 Xcode 的專案設定裡填，否則會套到 KidsAI。
2. `cd app && xcodegen generate && open KidsAI.xcodeproj`
3. 用傳輸線接上 iPhone，在 Xcode 上方選 **ASRSpike** scheme 和你的 iPhone，按 Run（⌘R）。第一次要在 iPhone 的「設定 → 一般 → VPN 與裝置管理」信任你的開發者帳號。

## 尚未加入

- 正式 App（KidsAI）的麥克風與語音辨識功能、隱私 key（`NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription`）：等 spike 結果由 Michael 定案後另案（L3）加入。目前這兩個 key 只在 ASRSpike。
