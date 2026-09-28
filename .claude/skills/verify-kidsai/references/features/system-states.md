# 系統狀態

App 對系統狀態的反應：進背景時停止旁白、畫面換成只有點點的遮罩（多工切換的縮圖不會留下孩子的選擇與家長卡），回到前景補念被打斷的句子（沒被打斷就重念目前畫面）；單元裡螢幕不會自動變暗；字級最多放大到「輔助使用 2」，大字級時選項與拖曳改成整列直排；開啟「減少動態效果」時，放大、彈跳與轉場動畫會關掉。

## Sub-features

- `background-resume`：進背景 → 回前景，還在同一關，旁白補念或重念。
- `privacy-cover`：不在前景時，畫面蓋上只有點點的遮罩。
- `idle-timer`：在單元裡螢幕不會自動變暗；回地圖後恢復。
- `dynamic-type`：字級上限「輔助使用 2」；大字級時選項整列直排、拖曳改用點選放卡。
- `reduce-motion`：減少動態效果時不放大、不彈跳、換關沒有淡入淡出。
- `voiceover`：換畫面時 VoiceOver 焦點移到題目；家長卡不在朗讀順序裡。

## How to get to it (user POV)

- 在單元裡按 Home 鍵或滑回主畫面，再點 App 回來（`background`）。
- 系統「設定 → 輔助使用」裡的字級、減少動態效果、VoiceOver（`settings`）。

## Driving it with control-kidsai

Preconditions:

- baseline；`doctor` 通過；真實點擊先 `build --for-testing`。

- **進背景再回來（background-resume）。** 真實按 Home 鍵再回到 App。`run new --feature system-states --entry background`，`record --flow background-resume --run $RUN`。看得到：單元 1 一起說 → 專用模擬器主畫面 → 回到同一關，「一起說」按鈕還在。
- **遮罩（privacy-cover）。** needs-flow：遮罩只在 App 不在前景時畫出來（多工切換畫面），流程截圖拍不到那一刻。
- **螢幕不變暗（idle-timer）。** verified-unreachable：模擬器不會自動變暗；前提「需要實機」。
- **字級（dynamic-type）。** needs-flow：`control-kidsai` 還沒有調整模擬器字級的命令。
- **減少動態效果（reduce-motion）。** needs-flow：還沒有切換設定的命令，而且縮時影片（約每 0.5 秒一格）看不出動畫有沒有關掉。
- **VoiceOver（voiceover）。** verified-unreachable：模擬器的 VoiceOver 無法由流程開啟與聽取；前提「需要實機」。

## Gotchas

- 背景流程的證據一定會出現專用模擬器主畫面（只允許 Apple 內建圖示；有通知或別的 App 內容就重錄）。
- 用 `--unit/--beat` 冷啟動時，App 會觸發一次「回到前景」而重念；這是啟動參數造成的，不是 `background-resume` 的證明。
- 字級、減少動態效果這類模擬器設定改過之後要改回來，否則之後每個 run 的證據都會不同。
