# KidsAI

給 5–8 歲孩子的 iOS App，讓孩子理解「AI 會猜、會錯、可以被教」。協作規則見 [AGENTS.md](AGENTS.md)。

## 在模擬器執行

需要 Xcode 16 以上與 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

1. `cd app && xcodegen generate`
2. 打開產生的 `app/KidsAI.xcodeproj`（接續上一步可用 `open KidsAI.xcodeproj`）
3. 在 Xcode 上方選一台 iOS 模擬器，按 Run（⌘R）

`.xcodeproj` 由 XcodeGen 產生、不進 git。專案設定只改 `app/project.yml`，改完重跑第 1 步。

## 語音辨識 spike（ASRSpike，只給大人在實機測試）

`ASRSpike` 是獨立的測試 App，不上架、不併入 KidsAI。測試步驟與規則見 [docs/spikes/asr-spike-protocol.md](docs/spikes/asr-spike-protocol.md)。

1. 複製 `app/Local.xcconfig.example` 成 `app/Local.xcconfig`，填入你的 Apple Developer Team ID（免費的個人帳號即可；這個檔不進 git）。Team 只在這個檔設，不要在 Xcode 的專案設定裡填，否則會套到 KidsAI。
2. `cd app && xcodegen generate && open KidsAI.xcodeproj`
3. 用傳輸線接上 iPhone，在 Xcode 上方選 **ASRSpike** scheme 和你的 iPhone，按 Run（⌘R）。第一次要在 iPhone 的「設定 → 一般 → VPN 與裝置管理」信任你的開發者帳號。

## 尚未加入

- 正式 App（KidsAI）的麥克風與語音辨識功能、隱私 key（`NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription`）：等 spike 結果由 Michael 定案後另案（L3）加入。目前這兩個 key 只在 ASRSpike。
