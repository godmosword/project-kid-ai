# 設計對照（design map）

功能 → Notion mid-fi 屏號與版本 → App 目前和設計稿的差異。改到畫面時，拿證據對照這裡的設計稿，列出**新的**差異；審查者（Codex、Grok）也照這份對照。

- 設計稿：[`design/midfi/`](../../../../design/midfi/)（mid-fi v1.2.2，2026-09-23；來源與版本見該資料夾的 README）。
- 內容以 repo 的 `content/` 為準（AGENTS.md：內容的唯一真實版本）；設計稿上的文字和內容 JSON 不同時，以內容 JSON 為準，不算差異。
- 差異分三類：
  - **有出處**：已有決定，寫明出處。
  - **待確認**：App 和設計稿不同，但找不到決定的出處；要 Michael 確認是保留 App 的做法、改 App，還是改設計。
  - **尚未實作**：設計稿有、App 還沒有的畫面或功能。

## 對照表

| mid-fi 屏 | 對到的功能與進入點 | 設計稿 |
|---|---|---|
| 01 地圖首頁（v1.2） | [map](./features/map.md)：`app-launch`、`map-unlock` | ![01](../../../../design/midfi/01-map.png) |
| 02 單元 1 跟讀（v1.2.1） | [say-together](./features/say-together.md)：`button`（單元 1 `--beat 3`） | ![02](../../../../design/midfi/02-readalong.png) |
| 03 沙盒 A｜猜猜帽（v1.2） | [sandbox](./features/sandbox.md)：`sandbox-ritual`＋單元 1 沙盒開頭（`--unit 0 --beat 4`、`--beat 5`） | ![03](../../../../design/midfi/03-sandbox-hat.png) |
| 04 沙盒 B｜猜對示範（v1.2.2） | [sandbox](./features/sandbox.md)：`sandbox-open` 的反應畫面（單元 1 `--beat 5`）— **對應待 Michael 確認** | ![04](../../../../design/midfi/04-sandbox-judge.png) |
| 04b 沙盒 B｜猜錯變體（v1.2.2） | 同 04 — **對應待 Michael 確認** | ![04b](../../../../design/midfi/04b-sandbox-judge-wrong.png) |
| 05 家長閘（v1.2） | 沒有對到的功能（尚未實作） | ![05](../../../../design/midfi/05-parent-gate.png) |
| 06 家長本週摘要＋匯出（v1.2.2） | 沒有對到的功能（尚未實作） | ![06](../../../../design/midfi/06-parent-week.png) |

沒有對到設計稿的功能：[choice-question](./features/choice-question.md)、[drag](./features/drag.md)、[story](./features/story.md)、[review-and-sticker](./features/review-and-sticker.md)、[system-states](./features/system-states.md)、[observer-menu](./features/observer-menu.md)。這些畫面沒有 mid-fi，只對照功能檔與 `design/tokens/kidsai.tokens.json`。

## 差異

### 01 地圖首頁

- **待確認**：設計稿左上有家長齒輪、上方有時間晶片「還有 12 分」、右下有「貼紙本」；App 地圖沒有這三個。
- **待確認**：設計稿點點的問句框在上方、島是一條直的路徑清單；App 的問句框在下方。
- **有出處**：第三島設計稿叫「查證」，App 叫「檢查島」— 以內容 JSON（`unit_3_verify` 的標題「檢查島：當個小偵探」）為準。

### 02 單元 1 跟讀

- **有出處**：設計稿有麥克風（點一下開始、自動結束）；App 本版只有「一起說」。語音辨識是 L3，要等 ASR spike 定案（`docs/spikes/`、AGENTS.md 的語音辨識規則）。
- **待確認**：設計稿頂列是「←」＋單元晶片「① 認識」＋齒輪；App 頂列是長按 1.5 秒才離開的 X、進度點、🔊。

### 03 沙盒 A｜猜猜帽

- **待確認**：設計稿是孩子從三張卡（晴天／牛角麵包／狐狸）選一張給猜猜帽猜；App 單元 1 的三個主題（天氣／早餐／動物）每張卡自動選好、依序玩。
- **待確認**：設計稿儀式與選卡在同一頁（「猜猜帽登場／輪到 AI 來猜」＋卡片）；App 的儀式是獨立一關（`--beat 4`「猜猜帽時間」）。

### 04／04b 沙盒 B｜判斷

對應提案（Plan v3 P6，待 Michael 在 PR 裡確認）：04 與 04b 是單元 1 沙盒的反應畫面（mid-fi 版本紀錄寫「單元1 兩鈕」），04 是猜測和孩子的卡一致、04b 是不一致。另一個可能是對到單元 3 有對錯的沙盒（AI 說對→同意、說錯→抓到了）。

- **待確認**：設計稿只有兩個鈕「猜對了／猜錯了」（v1.2 拿掉「不知道」）；App 單元 1 是三個反應「好像對／好像錯／不知道」，來自內容 v1（`docs/content-schema-v1-mapping.md` 單元 1 沙盒列，2026-09-25 核准）。兩者衝突，要決定以哪個為準。
- **待確認**：設計稿有三欄「你選的／AI 看到的（只看到一點點，馬賽克）／AI 猜的」；App 是主題圖＋猜猜帽框裡的猜測（可能附「我不確定」標籤），沒有「AI 看到的」欄。
- **有出處**：旁白文字設計稿是「猜猜帽猜完了。你覺得呢？」，App 是「你覺得 AI 猜得怎樣？」— 以內容 JSON 的 `reaction_prompt` 為準。

### 05 家長閘、06 家長本週摘要＋匯出

- **尚未實作**：App 沒有家長區、家長閘、摘要或匯出。目前唯一給大人的內容是貼紙頁的「給大人」卡（見 review-and-sticker）。
- 備註：TODOS.md 記有「請 Grok 修正 Notion 線框裡已過時的地方：家長閘…」；家長閘是否仍照 05 做，待 Michael 確認。
- 06 的「匯出」會把資料傳出裝置，屬於 AGENTS.md 的兒童資料規則與 L3（資料流），要另外走 `/agent-plan`。
