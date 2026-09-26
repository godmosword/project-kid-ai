# KidsAI 驗證地圖

這個資料夾是驗證 KidsAI 使用者看得到的行為時的維護來源。操作 App 前先讀這份索引，再用對應的功能檔當作步驟。

文中的 `control-kidsai` 指 `.claude/skills/verify-kidsai/control-kidsai`，一律在 repo 根目錄執行（例如先設 `C=.claude/skills/verify-kidsai/control-kidsai`，再用 `$C doctor`）。

## Baseline preconditions

- 專用模擬器 `KidsAI-Verify`（iPhone 17e 或 16e，390×844 pt，直向）已開機，status bar 已覆寫。
- 已用 `control-kidsai build && control-kidsai install` 裝上**目前原始碼**的 Debug build。
- `control-kidsai doctor` 回傳 `"ok": true`（`fresh-build` 通過）。
- App 狀態只在記憶體：每次 `launch` 都從地圖開始，單元 2–4 還沒解鎖（除非加 `--unlock-all`）。
- 不要操作不是這次 run 啟動的 App 或模擬器。

## Driving conventions

- 從 baseline 開始，除非功能檔的 Preconditions 另有寫明。
- 啟動參數（`--unit`、`--beat`、`--unlock-all`、`--events`）只能準備前置狀態；要證明的操作本身一定要是孩子真的做的動作。V1 還沒有點擊自動化，這類步驟標 `needs-V2-driver`。
- 單元編號（`--unit`，0 起算）與關卡編號（`--beat`）：

| `--unit` | 單元 | `--beat` 0–8 |
|---|---|---|
| 0 | 認識島（unit_1_recognize） | 0 intro、1 聽聲音選擇、2 箱子猜猜看、3 一起說、4 儀式、5 沙盒、6 故事、7 回顧、8 貼紙 |
| 1 | 提問島（unit_2_prompt） | 0 intro、1 誰說得清楚、2 拖曳配對、3 一起說、4 儀式、5 沙盒（兩張卡）、6 故事、7 回顧、8 貼紙 |
| 2 | 檢查島（unit_3_verify） | 0 intro、1 哪張怪怪的、2 拖曳分組、3 一起說、4 儀式、5 沙盒（有對錯）、6 故事、7 回顧、8 貼紙 |
| 3 | 創作島（unit_4_create） | 0 intro、1 誰來決定結局、2 拖曳排序、3 儀式、4 沙盒、5 一起說（依選擇）、6 故事、7 回顧、8 貼紙 |

- 旁白時間不固定：等功能檔寫的最終狀態出現，再截圖。
- 模擬器剛開機後的第一次 `launch` 比較慢，前幾秒畫面可能還是白的；等最終狀態出現，不要把白畫面當證據。
- 每個命令照字面執行；名稱只用小寫英數與連字號。

## Proof and skip reporting

- 同一段錄影裡要有觸發動作和最終狀態；另外截一張最終狀態。
- 每個證據都記 feature id 與進入點（`run new --feature <id> --entry <entry>`）。
- 走不到的進入點：寫明進入點、試過的命令和缺的前提（例如 `needs-V2-driver`）。不得用別的進入點代替後宣稱已驗證。
- 截圖與錄影證明不了語音（模擬器可能沒有 zh-TW 語音，錄影沒有聲音）。
- 發布前逐張看過畫面內容（SKILL.md 的 Evidence）。

## Full sweep

回歸掃描時依下表由上而下走；V1 只有標「V1 可證明」的格子能產生證據，其他照實回報 `needs-V2-driver`。

| 功能 | 進入點 | V1 |
|---|---|---|
| [map](./map.md) | `app-launch`：從主畫面打開 App → 地圖 | **V1 可證明** |
| map | `unlock-all`：Debug `--unlock-all` 啟動 → 四個島都可進 | **V1 可證明**（Debug 前置狀態，只證明地圖外觀） |
| map | `tap-island`：點島進單元 | needs-V2-driver |
| [unit-flow](./unit-flow.md) | `from-map` 點島 → 單元開場 | needs-V2-driver |
| unit-flow | `next`、`replay`、`hold-to-exit` | needs-V2-driver |
| [say-together](./say-together.md) | `button`：按「一起說」 | needs-V2-driver |
| [sandbox](./sandbox.md) | `open`、`multi-card`、`graded` 的反應 | needs-V2-driver |
| [review-and-sticker](./review-and-sticker.md) | `answer`、`finish` | needs-V2-driver |

之後要補的功能檔（V3）：選擇題（choice-question）、拖曳（drag）、故事（story）、觀察員選單（observer-menu）、系統狀態（system-states：進背景、VoiceOver、最大字級）。

## Feature entry contract

每個功能檔以 H1 標題和一段使用者看得到的行為描述開始，接著依序是四個 H2：

1. `Sub-features`：短 ID，每個行為一行。
2. `How to get to it (user POV)`：列出每個使用者進入點。
3. `Driving it with control-kidsai`：先寫 `Preconditions:`，再用有標籤的項目配對「使用者動作 → 確切命令 → 看得到的結果」。
4. `Gotchas`：會浪費或讓驗證失效的陷阱。

不寫實作細節；只寫使用者路徑、穩定的辨識方式、需要的狀態、命令和看得到的證明。

## Features

- [地圖](./map.md)：打開 App、四個島、鎖與完成星星、念出問句。
- [單元共通流程](./unit-flow.md)：頂列（長按離開、進度點、重念）、下一步、進背景再回來。
- [一起說](./say-together.md)：固定句、依前面選擇決定的句子、再說一次。
- [沙盒](./sandbox.md)：猜猜帽猜測、反應、多張卡比較、有對錯的看圖檢查。
- [回顧與貼紙](./review-and-sticker.md)：回顧題、貼紙頁、家長卡、回地圖。
