# 回顧與貼紙

單元的最後兩關。回顧是一或多題有答案的選擇題（答對念成功句；答錯變淡再試；達上限揭曉並標 ✓）。貼紙頁顯示本單元的貼紙和點點說的話，下方有標「給大人」的家長卡（不念、不進孩子的 VoiceOver 朗讀順序、不擋路），按「回地圖」結束單元。

## Sub-features

- `review-answer`：回顧題作答；答對、答錯變淡、達上限揭曉。
- `review-next-question`：多題時依序出現下一題。
- `sticker-page`：貼紙大圖（圓形框）＋點點說「完成〇〇島！」「你得到〇〇貼紙」。
- `sticker-parent-card`：深藍色「給大人」卡，文字不念。
- `sticker-back-to-map`：按「回地圖」→ 地圖上本島出現星星、下一島解鎖。

## How to get to it (user POV)

- 各單元的倒數第二關（回顧，`--beat 7`）與最後一關（貼紙，`--beat 8`）。
- 在貼紙頁按下方「回地圖」。

## Driving it with control-kidsai

Preconditions:

- baseline；`doctor` 通過。

- **看回顧題（前置狀態）。** `launch --unit 0 --beat 7`。看得到：題目「AI 比較像？」與兩個選項卡。
- **看貼紙頁（前置狀態）。** `launch --unit 0 --beat 8`。看得到：星星貼紙圓框、點點框「完成認識島！」「你得到「會猜貼紙」」、深藍「給大人」卡、下方「回地圖」。
- **回地圖（finish）。** 真實點擊 `unit.backToMap`。`record --flow sticker --run $RUN`。看得到：回到地圖、提問島可以點。
- **回顧題作答（answer）。** 單元 1：真實點擊 `option.know_all`（錯）→ `option.helper`（對）。`run new --feature review-and-sticker --entry answer`，`record --flow review-answer --run $RUN`。看得到：「什麼都知道」變淡，「會猜的幫手」打勾，出現「下一步」。第 1 關選擇題的 `choice-answer` 是另一個進入點，不能代替。

## Gotchas

- 單元 1 的會猜貼紙是正式圖（猜猜帽本人，2026-10-03，P4）；其他單元的貼紙仍是暫代圖。
- 家長卡的文字不會被念出來，也不在孩子的 VoiceOver 朗讀順序裡；這是設計（D32'），不是缺漏。
- 用 `--beat 8` 直接進貼紙頁再按回地圖，當次會完成該單元並解鎖下一個島；進度只在記憶體，重啟後回到初始狀態，不會解鎖更後面的島。
- 貼紙圖有自己的無障礙標籤（例如 `會猜貼紙`），但 `sticker` 流程沒有斷言它，只在錄影與截圖裡看得到；換成正式貼紙圖之後要逐張看證據，或另案補上斷言（2026-10-03：貼紙圖還是暫代圖）。
- 證據裡看得到家長卡的文字；它是內容文字，不是兒童資料。
