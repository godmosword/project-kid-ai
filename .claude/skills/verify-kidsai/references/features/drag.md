# 拖曳

配對（單元 2）、分組（單元 3）、排序（單元 4）。上面是目標（空格、組、1／2／3 號位），下面是卡片區。點卡片＝選起來並念出（有聲音的念句子）；再點目標＝放上去。配對與排序的單卡目標放到已有卡時會交換；分組目標可以放多張卡。全部放好、沒有選著卡時，0.6 秒後自動檢查：放對的固定、放錯的滑回卡片區；答錯兩次自動排好並揭曉。輔助使用字級時只用點選，不開手指拖曳。

## Sub-features

- `drag-select`：點卡片選起來（綠框、浮起），並念卡名或句子；再點一次取消。
- `drag-tap-to-place`：選起卡後點目標放上去；點卡片區空白處放回。
- `drag-swap`：放到已有卡的單卡格子（配對、排序）會交換，原本那張回到新卡的來處；分組目標可容納多張卡，不會交換。
- `drag-check`：全部放好後自動檢查；選著卡時不檢查，3 秒沒動作自動放下選取。
- `drag-partial`：答錯時放對的固定（深色框）、放錯的退回，重播退回的有聲卡。
- `drag-reveal`：答錯兩次自動排到正確位置並揭曉。
- `drag-finger`：手指拖曳（放開時落到重疊最多的目標，外擴 24pt）。
- `drag-voiceover`：VoiceOver 使用者對卡片用動作「放到〇〇」「放回卡片區」；放上去時念「〇〇，放到〇〇」，位子已有卡時念「這個位子已經有卡片」。

## How to get to it (user POV)

- 單元 2 第 3 關（配對，`--unit 1 --beat 2`）、單元 3 第 3 關（分組，`--unit 2 --beat 2`）、單元 4 第 3 關（排序，`--unit 3 --beat 2`）。
- 點卡片、點目標；或用手指拖。

## Driving it with control-kidsai

Preconditions:

- baseline；`build --for-testing` 過，`doctor` 的 ui-tests 一致。

- **點選放卡（tap-to-place）。** 單元 2 配對：點 `drag.card.cup_star` → `drag.target.blank_what` → `drag.card.place_table` → `drag.target.blank_where`。`record --flow drag-tap-to-place --run $RUN`。看得到：兩張卡放進空格、自動檢查後出現回饋（`feedback`）與「下一步」。
- **答錯退回、揭曉（前置狀態）。** `launch --unit 2 --beat 2 --events "place:fish:keep;place:square_moon:keep;place:hot_ice:fix;place:bright_sun:keep;check"`：看得到方月亮退回卡片區、其他三張固定、回饋「再聽一次，說得通嗎？」。只是前置狀態，不是點擊的證明。
- **手指拖曳、分組與排序的點擊。** needs-flow（手指拖曳留給實機；分組、排序還沒有流程）。
- **VoiceOver 動作（drag-voiceover）。** verified-unreachable：模擬器的 VoiceOver 無法由流程開啟與聽取；前提「需要實機」（TODOS 的實機試玩項目）。

## Gotchas

- 目標空著時是一個元素（`drag.target.<id>`），點它就是點目標；配對與排序目標只容納一張卡，放到已占用的格子會交換；分組目標可容納多張卡。
- 自動檢查有 0.6 秒緩衝；選著卡時不檢查，要等 3 秒自動放下選取。截最終狀態前要等 `feedback` 出現。
- 模擬器上的「點」是 XCUITest 合成的點擊，證明不了 5 歲孩子的手指能不能拖準；手指拖曳要實機試玩。
- 輔助使用字級範圍都只提供點選放卡，不提供手指拖曳。
- 開啟「減少動態效果」時，卡片不再從原位滑過去（`matchedGeometryEffect` 關掉），放上、交換、退回改成 0.2 秒淡入淡出，讓孩子仍看得出哪張卡回來了；這是刻意的，不是動畫沒關。縮時影片看不出差別，要手動在設定裡切換後試玩。
