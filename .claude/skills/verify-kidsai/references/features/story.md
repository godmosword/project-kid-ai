# 故事

每個單元的第 6 關（`--beat 6`）是一段有分歧的小故事。每個節點有一位說話者：點點（旁白，框旁是點點頭像）或猜猜帽（AI，框旁是猜猜帽、藍色框線）。同一節點的句子念完，才出現分歧選項或「下一步」；孩子點一個選項，故事走到對應的節點，最後走到結局。

## Sub-features

- `story-lines`：節點的句子畫在說話者的框裡；正在念的那句框線變粗，點點與猜猜帽的框分得出來。
- `story-next`：沒有分歧的節點念完出現「下一步」，點了往下一個節點。
- `story-branch`：有分歧的節點念完出現選項（大按鈕，有的附小圖）；點了走到對應節點，選項消失。
- `story-ending`：結局節點念完，「下一步」進回顧。

## How to get to it (user POV)

- 各單元第 6 關（`--beat 6`）：單元 1–3 在沙盒之後，單元 4 在一起說之後。
- 單元 1：找襪子（「再猜一次／自己找」→「一起找／給它提示圖」→ 提示圖三選一）；單元 2：「拿那個來／拿小鏟子」；單元 3：「相信／檢查一下」；單元 4：「讓它全寫」→「就這樣／我來改」，「我來選結局」則直接到自選結局。

## Driving it with control-kidsai

Preconditions:

- baseline；`doctor` 通過；真實點擊先 `build --for-testing`。

- **看故事開頭（前置狀態）。** `launch --unit 0 --beat 6`。看得到：點點框「猜猜帽第一次幫忙找襪子。」「會不會在沙發下？」，念完後下方「下一步」。
- **下一步＋分歧（story-next、story-branch）。** 真實點擊 `unit.next` → 第一個 `story.choice.*`。`run new --feature story --entry branch`，`record --flow story-branch --run $RUN`。看得到：點「下一步」（橘框）→ 猜猜帽框「我猜在沙發下！咦，沒有。」「接下來呢？」＋兩個選項 → 點第一個選項（橘框）→ 選項消失、故事到下一個節點。
- **走到結局（story-ending）。** needs-flow（還沒有走完整條故事的流程）。
- **看某個分歧（前置狀態）。** `launch --unit 0 --beat 6 --events "next"`。只用來看分歧畫面，不是孩子點的證明。

## Gotchas

- 選項和「下一步」都要等句子念完才出現；沒有 zh-TW 語音時會立刻出現。
- 單元 4 的故事開頭就是分歧（沒有先「下一步」）；`story-branch` 流程只適用單元 1。
- 選項 identifier 是 `story.choice.<選項 id>`（例如 `story.choice.guess_again`）；流程用「第一個 `story.choice.` 開頭的元素」，所以選項順序變了，證據裡點到的會不同。
