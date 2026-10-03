# 單元 1 美術證據覆蓋（E1 前置）

日期：2026-10-03。基準：`992925f` 加本分支（`art/e1-unit1-evidence`）。對應[下一階段計畫](next-stage-plan.md)的 **E1 驗證覆蓋前置**，不是 D0 風格定案、不是 P1–P4 接入，也**不核准任何圖**。

這份回答一件事：**單元 1 的每一張圖與每個角色位置，有沒有「孩子真的點」的自動化流程可以錄證據**；哪些還只能靠人工或實機。

## 這份能證明與不能證明的

- 流程測試（XCUITest 真實點擊）能證明：孩子從可點的元素走得到那個畫面、那一刻畫面上有哪些元素與文字、哪些按鈕還不能按。
- 流程測試**不能**證明：圖畫得對不對、教學線索成不成立（例如「只露一隻尖耳朵」）、小尺寸下輪廓與留白夠不夠清楚、顏色、旁白聲音。這些依 [asset-cues](asset-cues.md) 的驗收問題與 [art-spec](art-spec.md) 的檢查表另做，通過成人檢查仍要 Michael 核准，孩子試玩是另一層驗證。
- 本輪沒有生成任何素材、沒有新增 Asset Catalog、沒有改內容 JSON、沒有改 harness 防護或上限。風格 A／B／C 與表情規格都還沒定案。

## 狀態說明（兩件不同的事）

| 標記 | 意思 |
|---|---|
| **已執行、已錄製與本機審查** | 六條新增流程已在 iPhone 17e／iOS 27.0 專用模擬器執行，xcresult 確認 6 通過、0 失敗、0 跳過；另以 CLI 錄成影片、GIF 與最終截圖，逐張檢查後通過 `evidence review --ok`。證據留在本機、未發布；只證明本輪暫代版本，不代表定稿圖通過教學驗收。 |
| **已驗證（舊 build）** | [驗證基準線](../release/verification-baseline.md)在 `af48ad0` 上跑過的 17 條。美術換上去之後**必須用新 build 重錄**，舊證據不算（SKILL.md 的 Proof bar）。 |

本分支新增的 6 條全部已執行、錄製與本機審查。App 與 UI test runner 的新 build、install、doctor 均通過；本機測試摘要存於 `.verify/e1-unit1-test-summary.json`，錄製摘要存於 `.verify/e1-recording-summary.json`（均不進 git）。下表的新增流程依上述六條實測結果標記；既有流程仍保留舊 build 標記。

## 單元 1 的 14 個 key

「畫出來的大小」是 App 目前實際傳給 `ArtView` 的 `size`（pt）；暫代圖有自己的放大倍率（`PlaceholderArt.widthScale`），括號是實際畫出的寬。「流程能斷言」只列測試真的檢查的東西；沒有無障礙標籤的圖是裝飾性元素（`accessibilityHidden`），只能在錄影與截圖裡看到，不能被斷言。

| key | 進入點（畫面） | 大小 | 流程（`record --flow`） | 測試類別 | 流程能斷言 | 狀態 |
|---|---|---|---|---|---|---|
| `img_card_family` | 第 1 關聲音選項列（`--beat 1`） | 48 | `choice-answer`、`choice-reveal` | `FlowChoiceAnswer`、`FlowChoiceReveal` | 只有選項卡（`option.family`）本身：可點、變淡；圖是裝飾性元素 | 已驗證（舊 build） |
| `img_card_toy` | 同上 | 48 | `choice-reveal` | `FlowChoiceReveal` | 同上（`option.toy`） | 已驗證（舊 build） |
| `img_card_ai` | 同上（暫代圖＝猜猜帽） | 48 | `choice-answer`、`choice-reveal` | 同上 | 同上（`option.ai` 打勾） | 已驗證（舊 build） |
| `img_box_peek_cat_ear` | 第 2 關舞台圖（`--beat 2`） | 90（箱子畫 144 寬） | **`choice-box`** | `FlowChoiceBox` | 有標籤：`箱子只露出一小角，看得到尖尖的耳朵` 這個元素在畫面上 | 已執行、已錄製與本機審查 |
| `img_box_reveal_cat` | 第 2 關選項 | 56 | **`choice-box`** | `FlowChoiceBox` | `option.cat` 可點、點了標成「你選的」；圖是裝飾性元素 | 已執行、已錄製與本機審查 |
| `img_box_reveal_car` | 同上 | 56 | **`choice-box`** | `FlowChoiceBox` | `option.car` 可點、作答後不變淡、沒有第二個標記 | 已執行、已錄製與本機審查 |
| `img_box_reveal_banana` | 同上 | 56 | **`choice-box`** | `FlowChoiceBox` | `option.banana` 同上 | 已執行、已錄製與本機審查 |
| `img_slot_weather` | 沙盒主題 1（`--beat 5`） | 110 | `sandbox-open`、**`sandbox-ritual`** | `FlowSandboxOpen`、`FlowSandboxRitual` | 有標籤：`天氣卡`；同畫面的猜測「我猜今天會出太陽」與「我不確定」 | open 已驗證（舊 build）；ritual 已執行、已錄製與本機審查 |
| `img_slot_breakfast` | 沙盒主題 2 | 110 | **`sandbox-breakfast`** | `FlowSandboxBreakfast` | 有標籤：`早餐卡`；且同時要求 `天氣卡` 已不在（證明真的換了主題，不是重用同一顆反應鈕） | 已執行、已錄製與本機審查 |
| `img_slot_animal` | 沙盒主題 3 | 110（影子畫 143 寬） | **`sandbox-animal`** | `FlowSandboxAnimal` | 有標籤：`動物影子卡`；且 `早餐卡` 已不在；猜測「我猜是一隻狐狸」 | 已執行、已錄製與本機審查 |
| `img_hint_bed` | 故事提示圖（`--beat 6`） | 44 | `story-ending` | `FlowStoryEnding` | `story.choice.hint_bed` 可點、點了走到結局；圖是裝飾性元素 | 已驗證（舊 build） |
| `img_hint_bag` | 同上 | 44 | **`story-hint-bag`** | `FlowStoryHintBag` | 三張提示圖（`hint_bed`／`hint_bag`／`hint_bath`）同時可點，再點「書包」走到結局 | 已執行、已錄製與本機審查 |
| `img_hint_bath` | 同上 | 44 | **`story-hint-bath`** | `FlowStoryHintBath` | 同上，走另一條路（自己找）再點「浴室」 | 已執行、已錄製與本機審查 |
| `img_sticker_can_guess` | 貼紙頁（`--beat 8`） | 110（圓框 180） | `sticker` | `FlowSticker` | 流程只斷言「回地圖」與地圖解鎖；貼紙圖有標籤 `會猜貼紙`，但目前沒有被斷言，只在錄影與截圖裡 | 已驗證（舊 build），斷言待補 |

14 個 key 全部有真實點擊的進入點（本分支補齊 8 個：箱子 4 張、沙盒 2 張、提示圖 2 張，其中 `img_slot_weather` 多一條儀式進入）。

## 角色出現的位置與尺寸

單元 1 沒有 `image` 的猜測（`unit_1_recognize.guesses.json` 沒有 `image` 欄），所以單元 1 **不會**出現猜猜帽畫的圖（`AIDrawing`）；28pt 的小帽徽只出現在單元 2／3 的沙盒。

| 位置 | 大小 | 進入點 | 流程 | 狀態 |
|---|---|---|---|---|
| 說話框旁的點點 | 52 | 每一句旁白、回饋 | 全部流程 | 已驗證（舊 build） |
| 說話框旁的猜猜帽 | 52 | 猜測、故事的 AI 句 | `sandbox-open`、`story-branch`、**`sandbox-breakfast`／`sandbox-animal`／`sandbox-ritual`** | 既有舊 build；新增已執行、已錄製與本機審查 |
| 開場的點點大圖 | 120 | 單元 1 `--beat 0` | `hold-to-exit`（開場畫面在錄影裡） | 已驗證（舊 build） |
| 儀式的猜猜帽大圖 | 140 | 單元 1 `--beat 4` | **`sandbox-ritual`**（斷言這個元素在畫面上） | 已執行、已錄製與本機審查 |
| 沙盒結語的猜猜帽 | 120 | 三個主題都玩完之後 | 無 → `needs-flow`（見下） | 未覆蓋 |
| 猜猜帽畫的圖上的小帽徽 | 28 | 單元 2／3 沙盒 | `sandbox-pick-and-react`、`sandbox-compare`、`sandbox-graded` | 已驗證（舊 build），非單元 1 |
| 進背景遮罩的點點 | 96 | 按 Home | `background-resume` | 已驗證（舊 build） |
| 聲音選項裡的 `img_card_ai`（猜猜帽） | 48 | 第 1 關 | `choice-answer` | 已驗證（舊 build） |

D1 要看的 28／52／120–140pt 都有對應的畫面；**但這些流程只證明元素在畫面上、孩子走得到**，輪廓與留白是否在那個尺寸還看得清楚，要用等尺寸預覽與實機人工檢查。

## 本分支新增的 6 條流程

每條都是「啟動參數只準備所在關卡 → 真實點擊 → 等畫面上看得到的最終狀態」，不用固定秒數、不用 `--events` 跳狀態。要證明的那個動作一定在錄影裡：前置用不截圖的真實點擊（`prepareTap`／`prepareUntil`），因為 `Frames` 的 `tap`／`until` 一呼叫就會寫一格，連 `Frames.begin()` 之前也算。

| 流程 | 類別 | 前置（真實點擊、不錄） | 錄到的動作 | 錄到的最終狀態 |
|---|---|---|---|---|
| `choice-box` | `FlowChoiceBox` | `--unit 0 --beat 2` | 點「貓咪」 | 「貓咪」標成你選的、另兩個仍可點且沒有標記、點點念「你和 AI 都會猜，有時對有時錯。」、出現「下一步」 |
| `sandbox-ritual` | `FlowSandboxRitual` | `--unit 0 --beat 4` | 點「下一步」 | 天氣卡＋「我猜今天會出太陽」＋「我不確定」＋三個反應鈕；「猜猜帽時間」已不在 |
| `sandbox-breakfast` | `FlowSandboxBreakfast` | `--beat 5`，天氣卡真的反應一次 | 點「下一步」、點「好像對」 | 早餐卡（天氣卡已不在）、「我猜是麵包配牛奶」、揭曉句與「下一步」 |
| `sandbox-animal` | `FlowSandboxAnimal` | `--beat 5`，天氣與早餐兩張卡真的反應過 | 點「下一步」、點「好像錯」 | 動物影子卡（早餐卡已不在）、「我猜是一隻狐狸」、揭曉句與「下一步」 |
| `story-hint-bag` | `FlowStoryHintBag` | `--beat 6`，下一步 → 再猜一次 → 下一步 → 給它提示圖 | 點「書包」 | 三張提示圖都曾同時在畫面上、結局「襪子找到了！」與「下一步」 |
| `story-hint-bath` | `FlowStoryHintBath` | `--beat 6`，下一步 → **自己找** → 下一步 → 給它提示圖 | 點「浴室」 | 同上，結局與「下一步」 |

防止「舊狀態被當成換了畫面」的做法：換主題一律同時要求新主題的卡在、舊主題的卡不在，而且反應鈕還沒被選、「下一步」不在；反應鈕三個主題共用 identifier，所以不能只看鈕。

既有 17 條完全沒有改動。`story-hint-bath` 刻意走「自己找」，順便覆蓋第一個分歧的另一個選項。

## 還沒覆蓋的（照實回報，不當成已通過）

- **沙盒結語頁（猜猜帽 120）**：`needs-flow`。要在 `sandbox-animal` 的最終狀態之後再按一次「下一步」；超出本輪指定的六條範圍，另案補或擴充 `sandbox-animal`。
- **貼紙圖的斷言**：`sticker` 流程沒有斷言 `會猜貼紙` 這個元素，只在錄影與截圖裡看得到。要斷言得改既有流程（本輪不改）。
- **裝飾性圖（48／56／44pt 的選項與提示圖）**：沒有無障礙標籤，流程只能斷言它所在的按鈕；圖本身換了之後只能靠逐張看證據與人工驗收。
- **教學線索**：箱子的暫代圖畫**兩隻**耳朵，asset-cues 要求**一隻**；替換時要核對，流程不會抓到這種差異。
- **實機與人工**：手指拖曳、VoiceOver、減少動態效果、iPhone SE 與 AX2 的實機外觀、iOS 17 runtime 實際執行，都要大人在實機補驗（[驗證基準線](../release/verification-baseline.md)的「待補的輸入」）。
- **聲音**：模擬器證據沒有聲音，旁白、語速與「一起說」的發聲證明不了。
- **地圖與非內容資源**：地圖、角色設定圖等不在這 14 個 key 裡；P2／P3 要另外列非內容執行期資源清單與 bundle 解碼測試（計畫的 Verification 一節）。

## 工具整合與驗證結果

Claude 已撰寫六條流程及 CLI／文件提案；Codex 審查後套用提案並操作驗證。`FLOWS`、各流程的 `-only-testing` 路由測試、SKILL.md、Feature Map 與 design-map 都已同步，原有 17 條流程及 harness 防護／上限沒有改動。

- 驗證工具測試：`python3 -m unittest discover .claude/skills/verify-kidsai/tests`，103 通過。
- 六條新增 XCUITest：6 通過、0 失敗、0 跳過。本輪沒有重跑其餘 17 條或 App 的 69 個單元測試。
- 六次 `record --flow`：均成功，影片長度 4.5–7.8 秒；其中四次遇到 skill 已記載的 Xcode 27 收尾停滯，CLI 依測試完成旗標收尾並重開專用模擬器。
- 視覺與隱私審查：共 16 張抽出畫格、6 張最終截圖及 6 個 GIF，均只有 KidsAI 與覆寫後的 status bar，未見個人資料；六個 run 的本機 `evidence review --ok` 均通過。

| 流程 | 本機 run id | 影片秒數 |
|---|---|---|
| `choice-box` | `20261003-111743-992925f` | 4.8 |
| `sandbox-ritual` | `20261003-111813-992925f` | 4.5 |
| `sandbox-breakfast` | `20261003-111924-992925f` | 7.8 |
| `sandbox-animal` | `20261003-112110-992925f` | 7.2 |
| `story-hint-bag` | `20261003-112306-992925f` | 4.5 |
| `story-hint-bath` | `20261003-112454-992925f` | 4.5 |

以上 run 在基準 commit 加未提交測試變更的新 build 上錄製，沒有發布到證據 repo。未來 UI PR 要依當時的來源指紋重建、重錄及發布，不能拿這批當作新美術的正式證據。

目前可見的教學／版面問題仍另案處理：箱子暫代圖露出兩隻耳朵；早餐卡沒有呈現麵包與牛奶；動物影子模糊到難以辨識輪廓。箱子作答後的題目貼近頂列，需在未來版面驗收補查。這次只補測試，沒有修改這些畫面。
