---
description: KidsAI Agent Plan：依 docs/AGENT-WORKFLOW.md 風險分級產生 Plan，只規劃不實作
---

# Agent Plan（Claude Code 適配）

規則以 [`docs/AGENT-WORKFLOW.md`](../../docs/AGENT-WORKFLOW.md) 為準，本檔只寫 Claude Code 怎麼呼叫模型。只產生 Plan，不實作、不 commit。

任務：$ARGUMENTS

## 流程

1. 讀 `AGENTS.md` 與 `docs/AGENT-WORKFLOW.md`，判定 L0–L3。L0／L1 不建 Plan，直接說明並建議改用 `/agent-action`。
2. 起草 Plan：Goal、Scope／Out of scope、Task DAG、Files、Verification、Risks／rollback。
3. 依級別派審查（全部 readonly；prompt 不得含兒童資料或金鑰）：
   - 工程審：`codex exec -m gpt-5.6-luna -c model_reasoning_effort="medium" "<prompt>" </dev/null`。prompt 寫明「你未撰寫此 Plan」，逐條反駁 DAG，至少 3 點。
   - 對抗審（L3）：`cursor-agent --model cursor-grok-4.5-high-fast`；失敗時改用 `grok -m grok-4.6`。
   - 設計審（L3，或碰到設計審觸發項）：Agent tool `model: "opus"`。
4. 綜合審查意見修訂 Plan，標記「待 Michael 核准」或「待決策」，列出最小驗證命令，提示核准後使用 `/agent-action`。

## 禁止

- 不得使用 Fable 5（`claude-fable-5-*`）。
- 不得實作、改檔（Plan 本身除外）或 commit。
