# 待辦事項

更新：2026-09-26。依 Notion「開發路線圖 v1」的步驟排列；做完就打勾，並在後面註明日期或 commit。

## 進度

| 路線圖步驟 | 狀態 |
|---|---|
| 0–1 範圍、玩法骨架 | ✅ |
| 2 關卡腳本 | ✅ 單元 1–4 JSON 通過驗證，AI 猜測已核准 |
| 3 低保真原型＋孩子試玩 | 🟡 mid-fi 有，還沒找孩子試玩 |
| 4 合規 | 🟡 Checklist v1 完成；律師上架前再問 |
| 5 技術骨架 | ✅ Milestone 0 |
| 6 關卡引擎 | 🟡 引擎 v2 完成，單元 1–4 可在模擬器從頭玩到尾；語音辨識 spike 與實機試玩等 iPhone 配對 |
| 7 美術 | 🟡 規格書、token、風格樣張完成，等生圖 |
| 8–12 | ⬜ |

## Michael 要做的

### 語音辨識 spike（步驟 6）
- [ ] 把 ASRSpike 裝到 iPhone（用 Grok bot 帶著做；Team ID 已設在本機 `app/Local.xcconfig`）
- [ ] 簽核 [測試步驟](docs/spikes/asr-spike-protocol.md) 的門檻
- [ ] 照測試步驟實測（飛航模式、全新安裝後照 B → C → A 的順序），只把「彙總」的數字交給 Claude
- [ ] 測完檢查 App 資料夾、當天刪除 ASRSpike
- [ ] 找一支 iOS 17 或 18 的 iPhone，補測一輪，才能決定最低 iOS 版本

### 美術（步驟 7）
- [ ] 用 Codex／Grok 生 3 個風格方向（[生圖 prompt](docs/art/generation-prompts.md) 第 1 步），存到 `design/art/style-a|b|c/`
- [ ] 打開 [風格樣張](design/style-tile/index.html) 第 6 區比較，選定一個方向，也確認色票
- [ ] 生點點、猜猜帽的設定圖；每張定稿圖都記到 [provenance.md](docs/art/provenance.md)
- [ ] 確認 Codex、Grok 的使用條款允許商用

### 實機試玩（等 iPhone 配對）
- [ ] 解決 Xcode 的 iPhone 配對問題（CoreDeviceError 4001）
- [ ] 在 iPhone 上玩單元 1–4，特別看：拖曳手感（5 歲孩子拖不拖得準）、VoiceOver 的「放到〇〇」動作、系統語音聽不聽得懂
- [ ] 配對前可以先用 Xcode 模擬器玩（選 KidsAI 和 iPhone 模擬器，按 ▶），檢查流程順不順

### 其他
- [ ] 決定旁白要用 AI 配音（在電腦上先錄好）還是真人配音；點點和猜猜帽要聽得出是不同角色
- [ ] 請 Grok 在 [風格樣張](design/style-tile/index.html) 補上新色票 `card-stroke`、`speaking`（已在 `design/tokens/kidsai.tokens.json`）
- [ ] 找 1–2 位 6–8 歲孩子試玩 mid-fi 15–30 分鐘，記下卡住的地方和笑點（步驟 3；只記彙總，孩子用代號）
- [ ] 把 Notion 路線圖狀態的更新 prompt 貼給 Grok（如果還沒貼）
- [ ] 請 Grok 修正 Notion 線框裡已過時的地方：家長閘、Sign in with Apple、按住說話、「給點點猜」、垃圾桶
- [ ] 修正電腦的全域 git 身分（目前是範本預設值「你的名稱」）；本 repo 已單獨設好
- [ ] Figma 額度恢復或升級後通知 Claude
- [ ] 上架前諮詢律師（T1）

## Claude 要做的（等上面的輸入）

- [ ] 收到 spike 數字 → 整理 [報告](docs/spikes/asr-spike-report.md) 與建議路徑，Michael 定案
- [ ] spike 定案後，提 L3 計畫：正式 App 加入跟讀功能與隱私權限說明
- [ ] 風格選定後，提 L2 計畫：把圖片放進 App 的 Asset Catalog，並加一支檢查「內容用到的素材 key 都有對應圖檔」的驗證
- [ ] Figma 可用後：匯入 token，建元件與地圖首頁的高保真
- [x] 關卡引擎 v1：單元 1 可試玩（`ba810ac`）
- [x] 關卡引擎 v2：單元 2–4 可試玩（`f75c4e4`、`6f6aa01`）
- [x] GitHub Actions：每次 push 自動跑內容驗證與正反例（`56af6be`）
- [ ] 配音方式定案後，提 L2 計畫：預錄旁白接口（有音檔就播、沒有退回系統語音；補「我不確定」等寫死字串的音檔 key；一起說的逐字亮起）

## 之後再議（已記錄，不擋目前進度）

- 事件紀錄格式（`emit`），定案前內容不允許出現（D6）
- 依 spike 的「命中第幾個詞」數據，決定要不要收緊內容裡的關鍵詞（「猜」「貓」「一起」「可以」）（D27）
- 如果「只偵測出聲」夠用，把「裝置不支援辨識」的退路改成「有出聲就算」（D24）
- 單元 3 是否加「逐筆念出正確答案」的欄位，等試玩結果（D14）
- 單元 2 第 2 關難度偏低（格式不能放干擾卡）；單元 4 點子與結局方向的對應沒有欄位
- 單元 3 的錯誤猜測換成真模型的真實錯誤（S4，步驟 8；需要先定網路白名單）
- 排序格要不要念出「第 1 格」這類引擎文字（目前只給 VoiceOver，引擎只寫死「我不確定」）
