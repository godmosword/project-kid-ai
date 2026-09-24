# Agent 工作流程：風險分級與審查

本檔是風險分級、`/agent-plan`、`/agent-action` 的唯一來源。總規則仍以 [AGENTS.md](../AGENTS.md) 為準；兩者衝突時，列出衝突並詢問 Michael。

[.claude/commands/agent-plan.md](../.claude/commands/agent-plan.md) 與 [.claude/commands/agent-action.md](../.claude/commands/agent-action.md) 只負責 Claude Code 這邊怎麼呼叫模型。

## 風險分級

| 級別 | 判準 | 計畫與審查 |
|---|---|---|
| **L0** | 一條命令、機械檢查、少量設定 | 直接做，事後回報 |
| **L1** | 單檔、低風險、路徑明確 | 一個執行者完成，事後回報 |
| **L2** | 多檔、會改到孩子或家長看得到的行為、一般資料流 | Plan 經 Michael 核准，並做一次獨立工程審 |
| **L3** | 見下方「至少 L3」 | Plan 經 Michael 核准，並做工程、對抗、設計三審 |

L0／L1 是 AGENTS.md「先計畫再動手」的例外：可直接做，但做完要回報改了什麼。拿不準級別時，往高一級算。

### 至少 L3

- 語音辨識、麥克風、錄音
- 任何網路請求，或變更網路白名單
- 兒童資料的儲存、刪除、事件紀錄
- Info.plist 隱私 key、Privacy Manifest
- `content/schema/`（跨 App 與 pipeline 的契約）
- `app/project.yml` 的相依套件或簽署設定
- TestFlight、App Store 送審、任何發布
- pipeline 呼叫外部模型或付費 API

### 一定要做設計審

改到以下任一項，不論級別都要加 Opus 設計審：

- SwiftUI 動畫、轉場（`animation`、`transition`、`matchedGeometryEffect` 等）
- Reduce Motion、Dynamic Type、VoiceOver
- 觸控目標大小、字級、間距（孩子的手指與閱讀能力）

## `/agent-plan`：只規劃，不實作、不 commit

- **使用時機**：L2／L3，或 Michael 明確要求 Plan。L0／L1 不建 Plan。
- **Plan 內容**：Goal、Scope／Out of scope、Task DAG、Files、Verification、Risks／rollback。
- **L2 審查**：至少一個 readonly 工程審。prompt 要寫明「你未撰寫此 Plan」，並逐條反駁 DAG，至少 3 點。
- **L3 審查**：三審都要做；委員缺席時記錄原因。
- **收尾**：標記「待 Michael 核准」或「待決策」，列出最小驗證命令，提示核准後改用 `/agent-action`。

## `/agent-action`：執行與驗證

- **輸入**：L2／L3 必須有 Michael 核准的 Plan。
- **依級別路由**：
  - L0：直接跑命令。
  - L1：一個執行者完成；路徑不明時先唯讀探索。
  - L2：Grok 可提供唯讀建議，由 Claude Code 寫進檔案；必要時加一次 Codex 工程審。
  - L3：Claude Code 實作，並做三審。
- **同一檔案**：不能讓多個 agent 同時修改；顧問一律 readonly，不得改檔。
- **子任務 prompt**：必須包含 Goal、Context paths、Constraints、Do NOT、Verification、Deliverable。
- **驗證**：挑最小集合。
  - 只改文件或規則：確認連結與路徑正確。
  - 改到 `app/`：`cd app && xcodegen generate`，再 `xcodebuild -project KidsAI.xcodeproj -scheme KidsAI -destination 'generic/platform=iOS Simulator' build`。
  - 有測試 target 之後：加跑 `xcodebuild test`。
  - L3 或發布：另在模擬器實際啟動並截圖確認。
- **commit／push**：預設不做。Michael 明確要求時，只 stage 本次相關的檔案，不用 `git add -A`。

## 模型（Claude Code 這邊）

- 工程審：`codex exec -m gpt-5.6-luna -c model_reasoning_effort="medium" "<prompt>" </dev/null`
- 對抗審：`cursor-agent --model cursor-grok-4.5-high-fast`；失敗時改用 `grok -m grok-4.6`
- 設計審：Agent tool `model: "opus"`，readonly
- 任何路由都不能用 Fable 5（`claude-fable-5-*`）。

## 紅線

- **送給外部模型的內容**：審查 prompt 會送到 OpenAI（Codex）與 xAI（Grok）。只能放程式碼、規格與彙總數字；不得放兒童姓名、錄音、照片、測試紀錄或任何金鑰。
- **CRITICAL 問題**：遇到資料遺失、安全或隱私漏洞，或需要明確授權的修改時，以 `CRITICAL-n` 列出，並給 A（現在修）／B（暫不修）／C（誤判略過）三個選項；Michael 回 A 才改檔。
- **收尾分配表**：只列實際參與的角色。L0／L1 不需要；L3 要列出所有委員和缺席原因。
- **scope 外的想法**：列為後續項目，不順手加進這次的 diff。
