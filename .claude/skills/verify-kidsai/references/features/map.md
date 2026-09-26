# 地圖

打開 App 會看到地圖：四個島（認識島、提問島、檢查島、創作島），每個島有顏色、圖示和文字；還沒解鎖的島有鎖、變淡、點不了。下方點點的框寫著並念出「我們去哪個島？」。完成一個單元回到地圖後，該島出現星星，下一個島解鎖。

## Sub-features

- `map-islands`：四個島依序排列，第一個可點，其他有鎖。
- `map-question`：點點的框顯示「我們去哪個島？」，一進地圖就念出來。
- `map-unlock`：完成單元 N 後，單元 N 的島出現星星、單元 N+1 解鎖。
- `map-unlock-all`：Debug 啟動參數 `-unlockAll` 讓四個島都可點（試玩用，不寫入完成進度）。

## How to get to it (user POV)

- 從主畫面點 KidsAI 圖示打開 App（`app-launch`）。
- 在單元的貼紙頁按「回地圖」，或長按左上 X 1.5 秒離開單元。
- Debug build 以 `-unlockAll` 啟動（`unlock-all`，只用於試玩）。

## Driving it with control-kidsai

Preconditions:

- baseline（README）；`doctor` 通過。
- 這次 run 已 `run new --feature map --entry app-launch`，得到 `$RUN`。

- **打開 App（app-launch）。** 從主畫面打開。先 `record start --run $RUN --name map-launch`，再 `launch`。看得到：地圖上四個島，「認識島」全彩、其他三個有鎖並變淡；下方點點的框寫著「我們去哪個島？」。
- **最終狀態截圖。** 等上面的畫面出現後 `screenshot --run $RUN --name map-islands`，再 `record stop --run $RUN --name map-launch`。截圖 1170×2532。
- **全部解鎖（unlock-all）。** 新開一個 run（`--entry unlock-all`），`launch --unlock-all`。看得到：四個島都全彩、沒有鎖。這只證明 Debug 參數有效，不是孩子的路徑。
- **點島進單元（tap-island）。** needs-V2-driver。
- **完成單元後出現星星（map-unlock）。** needs-V2-driver（要走完一個單元）。

## Gotchas

- 錄影從主畫面開始（`launch` 會先關掉 App），畫面上會出現專用模擬器主畫面的 Apple 內建 App 圖示。這是允許的（打開 App 的真實路徑）；審查時確認沒有通知、沒有別的 App 內容。
- 地圖的問句是用系統語音念；模擬器沒有 zh-TW 語音時沒有聲音，但字一定在畫面上。
- 進度只在記憶體：每次 `launch` 都回到「只有認識島可點」。
- `-unlockAll`、`-openUnit`、`-beat`、`-events` 只在 Debug build 有效；Release build 忽略它們。
