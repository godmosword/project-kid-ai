# 單元共通流程

每個單元是一連串關卡。畫面上方是頂列：左邊長按 1.5 秒才會離開的 X（輕點會提示「按住不放」）、中間的進度點、右邊重念的 🔊。旁白念完、作答完才出現下方的「下一步」；按下後有短暫冷卻，連點不會跳關。要念的字一定先顯示在說話者的框裡（點點或猜猜帽）。

## Sub-features

- `unit-intro`：開場，點點說三句話（最後一句是本單元金句）。
- `unit-next`：旁白念完、作答後才出現「下一步」；連點不會跳過下一個畫面。
- `unit-replay`：右上 🔊 重念目前畫面。
- `unit-progress`：進度點顯示第幾關。
- `unit-hold-to-exit`：長按 X 1.5 秒回地圖；輕點出現「按住不放」。
- `unit-voiceover-exit`：VoiceOver 使用者可對左上 X 執行「回地圖」動作，不必長按。

## How to get to it (user POV)

- 在地圖點一個已解鎖的島（`from-map`）。
- 任一關的頂列與下方主按鈕。
- 開啟 iOS VoiceOver 後，在單元頂列聚焦左上 X（`voiceover-exit`）。

## Driving it with control-kidsai

Preconditions:

- baseline；`doctor` 通過。

- **打開單元（from-map）。** 點「認識島」。`record --flow map-to-unit1 --run $RUN`。看得到：單元 1 開場、頂列 X。
- **看開場畫面（前置狀態）。** `launch --unit 0 --beat 0`。看得到：點點的大頭像、三個點點說話框（「我是點點，不是 AI 喔。」等）、頂列 X／進度點（第 1 格）／🔊。這只是前置狀態截圖，不能當「點島進單元」的證明。
- **下一步（next）。** `record --flow story-branch --run $RUN`（念完才出現 `unit.next`，點了之後故事往下走）。
- **長按離開（hold-to-exit）。** 真實長按 `unit.exit` 2 秒。`run new --feature unit-flow --entry hold-to-exit`，`record --flow hold-to-exit --run $RUN`。看得到：單元 1 開場 → 長按 X（橘框）→ 回到地圖。
- **VoiceOver 離開（voiceover-exit）。** needs-flow：目前沒有流程開啟 VoiceOver 並執行 X 的「回地圖」動作；需要手動開啟 VoiceOver、聚焦 X 並執行該動作，確認回到地圖。
- **重念（replay）。** needs-flow：點 `unit.replay` 做得到，但要證明的是重念的聲音，證據沒有聲音。
- **進背景再回來。** 見 [system-states](./system-states.md) 的 `background-resume`。

## Gotchas

- 「下一步」要等旁白念完才出現；沒有 zh-TW 語音時會立刻出現。截圖前等畫面穩定，不要依固定秒數判斷行為。
- VoiceOver 使用者可在左上 X 的動作選單執行「回地圖」，不必長按 1.5 秒；一般觸控仍需長按，輕點會提示「按住不放」。
- 用 `--unit/--beat` 直接開啟時，App 冷啟動會觸發一次「回到前景」而重念目前畫面；這是啟動參數造成的，孩子從地圖進入時不會發生。
- Debug build 左上方進度點上方有觀察員選單的隱形入口（兩指長按 3 秒），單指操作不會打開。
