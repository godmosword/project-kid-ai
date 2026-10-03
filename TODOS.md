# 待辦事項

更新：2026-10-03。首版範圍見 [docs/first-release-scope.md](docs/first-release-scope.md)。依 Notion「開發路線圖 v1」的步驟排列；做完就打勾，並在後面註明日期或 commit／PR。

## 進度

| 路線圖步驟 | 狀態 |
|---|---|
| 0–1 範圍、玩法骨架 | ✅ 首版範圍定案：不含語音辨識、進度只在記憶體、家長區只有家長卡、只做 iPhone 直向（#9、#12） |
| 2 關卡腳本 | ✅ 單元 1–4 JSON 通過驗證，AI 猜測已核准 |
| 3 低保真原型＋孩子試玩 | 🟡 mid-fi 有（01、02 已對齊 App）；試玩步驟與彙總表完成（#10）；等 iPhone 配對後找孩子試玩 |
| 4 合規 | 🟡 Checklist v1；隱私權政策草稿、送審資料、Privacy Manifest 完成（#16）；律師、聯絡資訊、網址待定 |
| 5 技術骨架 | ✅ Milestone 0；CI 每次 PR 建置 App、跑 69 個 App 單元測試與 103 個驗證工具測試（#11） |
| 6 關卡引擎 | 🟡 引擎 v2，單元 1–4 可在模擬器從頭玩到尾；版面掃描（iPhone SE、大字級）的問題已修（#8、#13）；語音辨識 spike 與實機試玩等 iPhone 配對 |
| 7 美術 | 🟡 規格書、token、風格樣張、每張圖的教學線索與驗收表（#17）完成；等生圖 |
| 驗證層（agent 用） | ✅ V1–V4（#3–#6）：17 支真實點擊流程、證據 repo、每日自動維護（#18 補強被中斷時的紀錄） |
| 8–12 | ⬜ |

## Michael 要做的

### 實機與試玩（先處理 iPhone 配對）
- [ ] 解決 Xcode 的 iPhone 配對問題（CoreDeviceError 4001）
- [ ] 找 1–2 位 6–8 歲孩子在 iPhone 上試玩 App 單元 1，照 [試玩步驟](docs/playtests/unit1-protocol.md) 記錄，填 [彙總表](docs/playtests/unit1-report.md)（只記合計，孩子用代號）
- [ ] 在 iPhone 上玩單元 1–4，特別看：拖曳手感（5 歲孩子拖不拖得準）、VoiceOver 的「放到〇〇」動作、系統語音聽不聽得懂、「減少動態效果」下的拖曳
- [ ] 配對前可以先用 Xcode 模擬器玩（選 KidsAI 和 iPhone 模擬器，按 ▶），檢查流程順不順

### 語音辨識 spike（步驟 6，可以和試玩並行）
- [ ] 把 ASRSpike 裝到 iPhone（用 Grok bot 帶著做；Team ID 已設在本機 `app/Local.xcconfig`）
- [ ] 簽核 [測試步驟](docs/spikes/asr-spike-protocol.md) 的門檻
- [ ] 照測試步驟實測（飛航模式、全新安裝後照 B → C → A 的順序），只把「彙總」的數字交給 Claude
- [ ] 測完檢查 App 資料夾、當天刪除 ASRSpike
- [ ] 找一支 iOS 17 或 18 的 iPhone，補測一輪，才能決定最低 iOS 版本

### 美術與配音（步驟 7）
- [ ] 用 Codex／Grok 生 3 個風格方向（[生圖 prompt](docs/art/generation-prompts.md) 第 1 步），存到 `design/art/style-a|b|c/`
- [ ] 打開 [風格樣張](design/style-tile/index.html) 第 6 區比較，選定一個方向，也確認色票
- [ ] 生點點、猜猜帽的設定圖；每張定稿圖都要通過 [教學線索與驗收](docs/art/asset-cues.md)，並記到 [provenance.md](docs/art/provenance.md)
- [ ] 確認 Codex、Grok 的使用條款允許商用
- [ ] 決定旁白要用系統語音、AI 配音（在電腦上先錄好）還是真人配音；點點和猜猜帽要聽得出是不同角色。比較與建議見 [配音方式的決策表](docs/voice-options.md)（建議：單元 1 試玩先用系統語音，看結果再定）

### 上架前（步驟 4 合規）
- [ ] 定開發者名稱、聯絡信箱、隱私權政策網址與支援網址，填進 [隱私權政策](docs/release/privacy-policy.md) 的佔位符（清單見 [送審資料](docs/release/app-store-submission.md)「還沒準備好的」）
- [ ] 諮詢律師（Checklist T1）：隱私權政策、未成年人個資，以及 Kids Category 勾 6–8 但描述寫「5 歲可共玩」是否妥當
- [ ] 實機確認 iPad 相容模式的橫向（審查員常用 iPad 測）

### Grok 與 Notion
- [x] commit Grok 對 mid-fi 01、02 的更新（2026-10-03）
- [x] 請 Grok 依首版範圍把 mid-fi 01 地圖、02 頂列改成 App 現況（2026-10-01）
- [ ] 請 Grok 依 [首版範圍](docs/first-release-scope.md) 同步 Notion
- [ ] 把 Notion 路線圖狀態的更新 prompt 貼給 Grok（如果還沒貼）
- [ ] 請 Grok 修正 Notion 線框裡已過時的地方：家長閘、Sign in with Apple、按住說話、「給點點猜」、垃圾桶
- [ ] 請 Grok 把 mid-fi 04／04b 的反應改成內容 v1 的三個鈕「好像對／好像錯／不知道」（2026-09-28 定，見 [design-map](.claude/skills/verify-kidsai/references/design-map.md)）
- [ ] 請 Grok 在 [風格樣張](design/style-tile/index.html) 補上新色票 `card-stroke`、`speaking`（已在 `design/tokens/kidsai.tokens.json`）

### 其他
- [ ] 修正電腦的全域 git 身分（目前是範本預設值「你的名稱」）；本 repo 已單獨設好
- [ ] Figma 額度恢復或升級後通知 Claude
- [x] 決定沙盒三圖比較（單元 2）：照 D37 改程式，三張外框同尺寸（2026-10-01，#8）
- [x] 決定拖曳在「減少動態效果」下的動畫：保留 0.2 秒淡入淡出，只在 drag.md 寫清楚（2026-10-01）
- [x] 首版範圍三個決定：語音辨識不含、進度只在記憶體、家長區只有家長卡（2026-10-01，#9）
- [x] 首版只做 iPhone、鎖直向（2026-10-01，#12）

## Claude 要做的

### 等輸入
- [x] mid-fi 01、02 commit 後：更新 [design-map](.claude/skills/verify-kidsai/references/design-map.md) 01、02 的差異（2026-10-03；01 沒有差異，02 剩兩項待確認的小差異）
- [ ] 收到單元 1 試玩彙總 → 整理要修的地方（玩法、旁白節奏、圖像線索），Michael 排優先順序；順便決定「AI 看到的」欄（首版範圍的待決策項）
- [ ] 收到 spike 數字 → 整理 [報告](docs/spikes/asr-spike-report.md) 與建議路徑，Michael 定案
- [ ] spike 定案後，提 L3 計畫：正式 App 加入跟讀功能與隱私權限說明（隱私權政策、Privacy Manifest、送審資料要一起改）
- [ ] 風格選定後，提 L2 計畫：把圖片放進 App 的 Asset Catalog，並加一支檢查「內容用到的素材 key 都有對應圖檔」的驗證
- [ ] 配音方式定案後，提 L2 計畫：預錄旁白接口（有音檔就播、沒有退回系統語音；補「我不確定」等寫死字串的音檔 key；預錄音檔的逐字亮起時間點）。選 AI 配音的話，pipeline 呼叫外部服務另提 L3
- [ ] Figma 可用後：匯入 token，建元件與地圖首頁的高保真

### 還沒有流程的（要實機或聽聲音）
- 選擇題的提示（8 秒不動）與重聽聲音、手指拖曳、VoiceOver、減少動態效果：列在 Feature Map 的 needs-flow，實機試玩時一起看

### 已完成
- [x] 關卡引擎 v1：單元 1 可試玩（`ba810ac`）
- [x] 關卡引擎 v2：單元 2–4 可試玩（`f75c4e4`、`6f6aa01`）
- [x] GitHub Actions：內容驗證與正反例（`56af6be`）；App 建置、單元測試與驗證工具測試（#11）
- [x] 驗證層 V1–V4：verify-kidsai skill、XCUITest 流程與證據、Feature Map 與設計對照、每日自動維護（#3–#6）；每日維護被中斷時留下紀錄（#18）
- [x] Feature Map 對齊 App（#7）；流程補到 17 支（#8、#13、#14）；大字級可錄證據（#15）
- [x] 版面掃描（iPhone SE、iPad、最大字級）並修正：沙盒三圖同尺寸（#8）、首版只做 iPhone 直向（#12）、SE 分組拖曳放得下（#13）
- [x] 首版範圍與設計稿差異狀態（#9）；單元 1 試玩步驟與彙總表（#10）
- [x] 發布準備：隱私權政策草稿、送審資料、Privacy Manifest、加密申報（#16）
- [x] 美術教學線索驗收表、配音方式決策表（#17）

## 之後再議（已記錄，不擋目前進度）

- 進度保存（D30）：試玩後若跨天重玩明顯受阻，再提 L3 計畫
- iPad 專用版面、橫向：試玩後再評估
- 家長閘、本週摘要、匯出：首版延後；摘要與匯出牽涉事件紀錄與資料傳出，屬 L3
- 事件紀錄格式（`emit`），定案前內容不允許出現（D6）
- 依 spike 的「命中第幾個詞」數據，決定要不要收緊內容裡的關鍵詞（「猜」「貓」「一起」「可以」）（D27）
- 如果「只偵測出聲」夠用，把「裝置不支援辨識」的退路改成「有出聲就算」（D24）
- 單元 3 是否加「逐筆念出正確答案」的欄位，等試玩結果（D14）
- 單元 2 第 2 關難度偏低（格式不能放干擾卡）；單元 4 點子與結局方向的對應沒有欄位
- 單元 3 的錯誤猜測換成真模型的真實錯誤（S4，步驟 8；需要先定網路白名單）
- 排序格要不要念出「第 1 格」這類引擎文字（目前只給 VoiceOver，引擎只寫死「我不確定」）
- GitHub Actions 的 action 鎖到 commit SHA、XcodeGen 鎖版本（#11 Codex 審的 LOW）
