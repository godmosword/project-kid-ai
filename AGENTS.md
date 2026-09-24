# Project KidsAI — Agent 規則

本檔是所有 AI agent（Claude Code、Codex、Grok）的共同規則。規則只改這一份，`CLAUDE.md` 只負責匯入本檔。

## 專案一句話
給 5–8 歲孩子（商店年齡帶 6–8、5 歲共玩）的 iOS App，讓孩子理解「AI 會猜、會錯、可以被教」。

## 角色
- **寫程式：** Claude Code（唯一寫手）
- **審 PR：** Codex、Grok
- **Notion 與 mid-fi HTML：** Grok 執行（`design/` 內的 HTML 仍依本檔規則）
- **定案：** Michael（人類）。遇到需要決定的事，停下來問，不要自行決定。

## 工作流程
- **先計畫再動手：** 每個任務先提出計畫（要改哪些檔、怎麼驗證、有什麼風險），等 Michael 同意後才寫程式。
- **Git：** 可直接 commit 並 push 到 `main`，也可走分支＋PR；不得 force push。
- **一個 PR 只做一件事。** PR 描述寫清楚：做了什麼、怎麼驗證、已知限制。
- **不確定就問，不要猜。** 規格互相衝突時，列出衝突並詢問 Michael。

## 技術硬規則
- **客戶端：** SwiftUI 原生 iOS。
- **最低 iOS 版本：** 暫定 iOS 17（語音 spike 後定案）。不得使用高於最低版本的 API，除非用 `if #available` 包起來並提供退路。
- **專案檔：** 由 XcodeGen 產生。只改 `app/project.yml`，不要手改 `.xcodeproj`；`.xcodeproj` 不進 git。
- **第三方套件：** 一律不得加入（SPM、CocoaPods 皆同），除非 Michael 在 PR 中明確同意。
- **分析／廣告／崩潰回報 SDK：** 一律禁止（App Store Kids Category 規定）。
- **網路：** App 預設不發出任何網路請求。例外只限白名單內的自家端點（目前：無）。
- **語音辨識：** 只允許裝置端辨識（例如 `requiresOnDeviceRecognition = true`）。裝置端不可用時退回「一起說」，絕不改走雲端。
- **兒童資料：** 只存本機。不得收集或傳出姓名、聲音檔、照片、裝置識別碼。錄音不落盤。
- **事件紀錄：** 只寫本機，事件與欄位以 `content/schema/` 的事件集為準。
- **公開 repo：** 本 repo 是 public。不得 commit 任何金鑰、token、`.env` 或憑證；金鑰只放本機環境變數。不得出現兒童姓名、錄音、照片或可識別個人的測試紀錄；spike 報告只寫彙總數字，孩子以代號表示。

## 目錄
- `app/` — SwiftUI 客戶端（XcodeGen）
- `content/` — 單元 JSON＋JSON Schema，內容的唯一真實版本
- `pipeline/` — 離線猜測生成（Python）
- `design/` — mid-fi HTML，參考用，不打包進 App
- `docs/` — spike 報告與決策紀錄

## 文件來源
- **決策：** 以 Notion「專案架構定稿 v1」中的「需 Michael 確認」區塊為準。
- **程式與內容：** 以本 repo 為準。
