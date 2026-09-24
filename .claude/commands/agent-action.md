---
description: KidsAI Agent Action：依 docs/AGENT-WORKFLOW.md 執行已核准的 Plan 並驗證
---

# Agent Action（Claude Code 適配）

規則以 [`docs/AGENT-WORKFLOW.md`](../../docs/AGENT-WORKFLOW.md) 為準，本檔只寫 Claude Code 怎麼呼叫模型。L2／L3 必須有 Michael 核准的 Plan；沒有就停下來，建議先用 `/agent-plan`。

任務：$ARGUMENTS

## 執行

- L0：直接跑最小命令。
- L1：Claude Code 單獨完成；路徑不明時先唯讀探索。
- L2：可用 `cursor-agent -p --trust --mode ask --model grok-4.7-high-fast` 取得唯讀建議，由 Claude Code 寫檔；必要時加一次 `codex exec -m gpt-6-luna -s read-only -c model_reasoning_effort="medium" "<prompt>" </dev/null` 工程審。
- L3：Claude Code 實作，工程、對抗、設計（Agent tool `model: "opus"`，Opus 5.5，effort high）三審。

顧問一律 readonly；同一檔案不讓多個 agent 同時修改。子任務 prompt 必須包含 Goal、Context paths、Constraints、Do NOT、Verification、Deliverable，且不得含兒童資料或金鑰。

## 驗證與收尾

依 `docs/AGENT-WORKFLOW.md` 的驗證清單挑最小集合。收尾只列實際參與的角色；L3 列所有委員和缺席原因。預設不 commit／push；Michael 明確要求時只 stage 本次相關檔案，不用 `git add -A`。
