# 系統狀態

App 對系統狀態的反應：進背景時停止旁白、畫面換成只有點點的遮罩（多工切換的縮圖不會留下孩子的選擇與家長卡），回到前景補念被打斷的句子（沒被打斷就重念目前畫面）；單元裡螢幕不會自動變暗；字級最多放大到「輔助使用 2」，大字級時選項與拖曳改成整列直排；開啟「減少動態效果」時，放大、彈跳與轉場動畫會關掉。內容檔載入失敗時，App 只顯示請大人處理的錯誤畫面。

## Sub-features

- `background-resume`：進背景 → 回前景，還在同一關，旁白補念或重念。
- `privacy-cover`：不在前景時，畫面蓋上只有點點的遮罩。
- `idle-timer`：在單元裡螢幕不會自動變暗；回地圖後恢復。
- `dynamic-type`：字級上限「輔助使用 2」；大字級時選項整列直排、拖曳改用點選放卡。
- `reduce-motion`：減少動態效果時不放大、不彈跳、換關沒有淡入淡出；拖曳卡片不滑動，改成短淡入淡出。
- `voiceover`：換畫面時 VoiceOver 焦點移到題目；家長卡不在朗讀順序裡。
- `load-error`：內容 JSON 載入失敗時，整個 App 只顯示「內容載入失敗（請大人處理）」和錯誤說明，不進地圖。

## How to get to it (user POV)

- 在單元裡按 Home 鍵或滑回主畫面，再點 App 回來（`background`）。
- 系統「設定 → 輔助使用」裡的字級、減少動態效果、VoiceOver（`settings`）。

## Driving it with control-kidsai

Preconditions:

- baseline；`doctor` 通過；真實點擊先 `build --for-testing`。

- **進背景再回來（background-resume）。** 真實按 Home 鍵再回到 App。`run new --feature system-states --entry background`，`record --flow background-resume --run $RUN`。看得到：單元 1 一起說 → 專用模擬器主畫面 → 回到同一關，「一起說」按鈕還在。
- **遮罩（privacy-cover）。** 部分證明：`background-resume` 的縮時影片在進出背景的轉場格裡看得到遮罩（空白底＋點點，沒有題目和選項），但流程沒有斷言它；沒拍到不算失敗。要完整證明需要 needs-flow（在多工切換畫面截圖）。
- **螢幕不變暗（idle-timer）。** verified-unreachable：模擬器不會自動變暗；前提「需要實機」。
- **字級（dynamic-type）。** `sim text-size --size ax2`（輔助使用 2，App 的上限）→ `run new --feature system-states --entry dynamic-type-choice-answer`，`record --flow choice-answer --run $RUN`；拖曳用 `--entry dynamic-type-drag`、`record --flow drag-tap-to-place`。看得到：選項整列直排、拖曳的卡改成長條且只用點選放卡，作答與放卡照常完成。**錄完一定要 `sim text-size --size default`**，`doctor` 的 text-size 會擋住沒改回來的狀態。
- **減少動態效果（reduce-motion）。** needs-flow：還沒有切換設定的命令，而且縮時影片（約每 0.5 秒一格）看不出動畫有沒有關掉。
- **VoiceOver（voiceover）。** verified-unreachable：模擬器的 VoiceOver 無法由流程開啟與聽取；前提「需要實機」。
- **載入失敗（load-error）。** verified-unreachable：要有壞掉的內容檔才會出現，而 App 內的內容由 CI 驗證過；前提「換成壞掉的內容 bundle」（不在驗證範圍內做）。只做 source 覆蓋（`app/KidsAI/KidsAIApp.swift` 的 `RootView`）。

## Gotchas

- 背景流程的證據一定會出現專用模擬器主畫面：除了 Apple 內建圖示，還會有本專案的 KidsAI 與 UI 測試 runner（KidsAIUITests-Runner）圖示，這是允許的（2026-09-28 定）；有通知或別的 App 內容就重錄。
- 用 `--unit/--beat` 冷啟動時，App 會觸發一次「回到前景」而重念；這是啟動參數造成的，不是 `background-resume` 的證明。
- App 只支援 iPhone、鎖直向（首版範圍，2026-10-01）；轉橫手機畫面不會跟著轉。
- 字級、減少動態效果這類模擬器設定改過之後要改回來，否則之後每個 run 的證據都會不同。
