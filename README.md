# KidsAI

給 5–8 歲孩子的 iOS App，讓孩子理解「AI 會猜、會錯、可以被教」。協作規則見 [AGENTS.md](AGENTS.md)。

## 在模擬器執行

需要 Xcode 16 以上與 [XcodeGen](https://github.com/yonaskolb/XcodeGen)（`brew install xcodegen`）。

1. `cd app && xcodegen generate`
2. 打開產生的 `app/KidsAI.xcodeproj`（接續上一步可用 `open KidsAI.xcodeproj`）
3. 在 Xcode 上方選一台 iOS 模擬器，按 Run（⌘R）

`.xcodeproj` 由 XcodeGen 產生、不進 git。專案設定只改 `app/project.yml`，改完重跑第 1 步。

## 尚未加入

- 麥克風與語音辨識的用途說明（`NSMicrophoneUsageDescription`、`NSSpeechRecognitionUsageDescription`）等隱私 key：隨 ASR spike 一起加入。
