# 拖曳

配對（單元 2）、分組（單元 3）、排序（單元 4）。上面是目標（空格、組、1／2／3 號位），下面是卡片區。點卡片＝選起來並念出（有聲音的念句子）；再點目標＝放上去；放到已有卡的格子會交換。全部放好、沒有選著卡時，0.6 秒後自動檢查：放對的固定、放錯的滑回卡片區；答錯兩次自動排好並揭曉。最大字級時只用點選，不開手指拖曳。

## Sub-features

- `drag-select`：點卡片選起來（綠框、浮起），並念卡名或句子；再點一次取消。
- `drag-tap-to-place`：選起卡後點目標放上去；點卡片區空白處放回。
- `drag-swap`：放到已有卡的格子（配對、排序）會交換，原本那張回到新卡的來處。
- `drag-check`：全部放好後自動檢查；選著卡時不檢查，3 秒沒動作自動放下選取。
- `drag-partial`：答錯時放對的固定（深色框）、放錯的退回，重播退回的有聲卡。
- `drag-reveal`：答錯兩次自動排到正確位置並揭曉。
- `drag-finger`：手指拖曳（放開時落到重疊最多的目標，外擴 24pt）。

## How to get to it (user POV)

- 單元 2 第 3 關（配對，`--unit 1 --beat 2`）、單元 3 第 3 關（分組，`--unit 2 --beat 2`）、單元 4 第 3 關（排序，`--unit 3 --beat 2`）。
- 點卡片、點目標；或用手指拖。

## Driving it with control-kidsai

Preconditions:

- baseline；`build --for-testing` 過，`doctor` 的 ui-tests 一致。

- **點選放卡（tap-to-place）。** 單元 2 配對：點 `drag.card.cup_star` → `drag.target.blank_what` → `drag.card.place_table` → `drag.target.blank_where`。`record --flow drag-tap-to-place --run $RUN`。看得到：兩張卡放進空格、自動檢查後出現回饋（`feedback`）與「下一步」。
- **答錯退回、揭曉（前置狀態）。** `launch --unit 2 --beat 2 --events "place:fish:keep;place:square_moon:keep;place:hot_ice:fix;place:bright_sun:keep;check"`：看得到方月亮退回卡片區、其他三張固定、回饋「再聽一次，說得通嗎？」。只是前置狀態，不是點擊的證明。
- **手指拖曳、分組與排序的點擊。** needs-flow（手指拖曳留給實機；分組、排序還沒有流程）。

## Gotchas

- 目標空著時是一個元素（`drag.target.<id>`），點它就是點目標；放了卡以後，點卡片會改成「放到那張卡的位置」。
- 自動檢查有 0.6 秒緩衝；選著卡時不檢查，要等 3 秒自動放下選取。截最終狀態前要等 `feedback` 出現。
- 模擬器上的「點」是 XCUITest 合成的點擊，證明不了 5 歲孩子的手指能不能拖準；手指拖曳要實機試玩。
