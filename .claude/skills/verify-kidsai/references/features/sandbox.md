# 沙盒

「猜猜帽時間」儀式之後，猜猜帽（AI，藍色帽子）對每張卡說出猜測，孩子對猜測做反應；每張卡都玩一次，最後點點念結語。猜測只從本機、已核准的猜測庫來。反應鈕在猜測念完後出現（念反應題時依序標亮），出現後一直留到換卡。

## Sub-features

- `sandbox-ritual`：儀式頁，猜猜帽大圖＋「猜猜帽時間」。
- `sandbox-open`：沒有對錯（單元 1、4）：每張卡自動選好，猜測→反應→揭曉句。
- `sandbox-unsure-tag`：猜測是 unsure 時顯示並念「我不確定」。
- `sandbox-multi-card`：單元 2 一個主題兩張句子卡：孩子先選一張，第二張自動選好；兩張都玩完，「我想要的貓」與兩張猜猜帽畫的圖外框同尺寸排成一列（圖用同一倍率，保留大小關係）並念揭曉句。
- `sandbox-graded`：單元 3 有對錯：AI 說錯要按「抓到了」、說對要按「同意」；選錯只讓那一顆變淡；「我不確定」第一次不算答錯、第二次直接揭曉；答對或揭曉後才有「下一步」。
- `sandbox-ai-drawing`：猜猜帽畫的圖用藍框＋小帽子，和「我想要的」中性框分開。
- `sandbox-closing`：最後一張之後的結語頁。

## How to get to it (user POV)

- 各單元的儀式之後（單元 1–3 `--beat 5`；單元 4 `--beat 4`）。
- 在沙盒裡點反應鈕；單元 2 先點一張句子卡。
- 儀式頁（單元 1 `--beat 4`）按「下一步」進第一個主題。
- 單元 1 的三個主題依序玩：天氣 → 早餐 → 動物影子；每張卡反應完按「下一步」換下一張，三張都玩完才進結語頁。

## Driving it with control-kidsai

Preconditions:

- baseline；`doctor` 通過。

- **沒有對錯的沙盒（前置狀態）。** `launch --unit 0 --beat 5`。看得到：主題「天氣」與圖、猜猜帽框「我猜今天會出太陽」＋「我不確定」標籤、點點框「你覺得 AI 猜得怎樣？」；旁白念完後出現「好像對／好像錯／不知道」。
- **有對錯的沙盒（前置狀態）。** `launch --unit 2 --beat 5`。看得到：「數數腳」、四隻腳分開的小狗圖、「小狗有三隻腳。」、三個反應鈕排成一列。
- **有對錯：答錯一次（前置狀態）。** `launch --unit 2 --beat 5 --events "react:agree"`。看得到：「同意」變淡、小狗圖加粗框、點點框「再看看圖，想一想。」。
- **兩張卡比較（前置狀態）。** `launch --unit 1 --beat 5 --events "pick:prompt_vague;react:closer;next;react:closer"`。看得到：「我想要的貓」、站著的大白貓（貓＋我不確定）、坐著的小黃貓（坐著的小黃貓），外框同尺寸一列；點點框「說得越清楚，它越知道你要哪種貓。」。
- **兩張都玩完、三圖比較（compare）。** 真實點擊。`run new --feature sandbox --entry compare`，`record --flow sandbox-compare --run $RUN`：點 `option.prompt_vague` → `option.closer` → `unit.next` → 第二張卡點 `option.closer` → 出現 `sandbox.comparison`。看得到：「我想要的貓」和兩張猜猜帽畫的圖外框同尺寸、排成一列，念完揭曉句出現「下一步」。
- **多卡主題：選卡、反應、第二張卡（multi-card）。** `record --flow sandbox-pick-and-react --run $RUN`：點 `option.prompt_vague` → 等反應鈕 → 點 `option.closer` → 點 `unit.next` → 第二張卡自動選好、反應鈕出現。
- **有對錯：點錯再點對（graded）。** 真實點擊 `option.agree` → `option.catch`。`run new --feature sandbox --entry graded`，`record --flow sandbox-graded --run $RUN`。看得到：「小狗有三隻腳。」→ 點「同意」（橘框）→「同意」變淡、點點框「再看看圖，想一想。」、還沒有「下一步」→ 點「抓到了」（橘框）→ 下方「下一步」。
- **沒有對錯的反應（open）。** 單元 1 第一張卡（天氣）：猜猜帽猜完後真實點擊 `option.seem_right`。`run new --feature sandbox --entry open`，`record --flow sandbox-open --run $RUN`。看得到：「好像對」選起來，出現「下一步」。
- **儀式 → 第一個主題（ritual-to-sandbox）。** 真實點擊儀式頁的 `unit.next`（前置只用 `--unit 0 --beat 4` 準備所在關卡）。`run new --feature sandbox --entry ritual-to-sandbox`，`record --flow sandbox-ritual --run $RUN`。看得到：儀式頁的猜猜帽大圖與「猜猜帽時間」→ 點「下一步」（橘框）→ 天氣卡、「我猜今天會出太陽」＋「我不確定」、三個反應鈕都可點，而「猜猜帽時間」已不在。
- **換到第二個主題：早餐（slot-breakfast）。** 前置用真實點擊把天氣卡玩完（不錄影：流程用 `prepareTap`／`prepareUntil`）。`run new --feature sandbox --entry slot-breakfast`，`record --flow sandbox-breakfast --run $RUN`。看得到：點「下一步」（橘框）→ 早餐卡在、天氣卡已不在、「我猜是麵包配牛奶」、反應鈕還沒被選、還沒有「下一步」→ 點「好像對」（橘框）→ 點點框「AI 會猜，有時猜對，有時猜錯。」與「下一步」。
- **換到第三個主題：動物影子（slot-animal）。** 前置把天氣、早餐兩張卡都真的玩完（不錄）。`run new --feature sandbox --entry slot-animal`，`record --flow sandbox-animal --run $RUN`。看得到：點「下一步」（橘框）→ 動物影子卡在、早餐卡已不在、「我猜是一隻狐狸」、反應鈕還沒被選 → 點「好像錯」（橘框）→ 揭曉句與「下一步」。
- **結語頁（sandbox-closing）。** needs-flow：三個主題都玩完後的結語頁（猜猜帽大圖）還沒有流程；要在 `sandbox-animal` 的最終狀態之後再按一次「下一步」，另案補或擴充該流程。

## Gotchas

- 三圖比較的三個外框一樣大（D37），都是 `cell - 8` 的方框；三張圖用同一個倍率畫，最寬的那張剛好塞進框，所以圖之間的大小關係不變（站著的大白貓比坐著的貓大）。猜猜帽的圖另有藍框和右上的小帽子。
- 以上 `--events` 只是把畫面推到某個狀態，**不是**「孩子點了反應」的證明。
- iPhone SE 等窄螢幕上，有對錯的沙盒會自動捲到主題圖的頂端；截圖前等捲動結束。
- 猜猜帽的猜測念完之前反應鈕不會出現；沒有 zh-TW 語音時會立刻出現。
- 單元 4 的三個世界都玩完才進結語；最後一個世界的反應決定下一關跟讀的句子（見 say-together）。
- 三個主題共用同一組反應鈕 identifier（`option.seem_right`／`option.seem_wrong`／`option.unsure`），只看鈕分不出有沒有換主題：換主題一律同時要求新主題的卡在、舊主題的卡不在、反應鈕還沒被選、「下一步」不在，免得把舊狀態當成換了畫面。
- 認得出是哪一張主題卡，靠的是內容 JSON 的 `a11y_label`（天氣卡／早餐卡／動物影子卡）；猜測句來自本機猜測庫，可以一起斷言。圖本身是裝飾性元素，換圖後的教學線索要人工驗收。
