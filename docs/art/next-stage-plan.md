# 下一階段開發計畫：以美術完成單元 1，再擴到四單元

日期：2026-10-03。規劃基準：`992925f`。**狀態：Michael 已指示實作本計畫；先執行不依賴美術定案的 E1。風格、表情規格及定稿素材仍待決策；執行指示不等於素材核准、發布授權或改變首版範圍。**

## Goal

讓孩子在實際 iPhone 畫面上分得出點點與猜猜帽、看得懂題目所需的線索，並保留「AI 會猜、會錯、可以被教」的教學意思。先交付角色、地圖與單元 1 的完整美術版本，完成試玩與修正，再製作單元 2–4。

## 現況與規劃依據

- [三方向預覽](../../design/art/README.md)已有 9 張 draft；Michael 尚未選定 A／B／C。[風格比較頁](../../design/style-tile/index.html)第 6 區可並排比較。這些是風格樣本，不是可直接放進 App 的定稿。
- 本輪逐一讀取四個單元及四份猜測庫的所有 `image` 引用，得到 **35 個不重複 key**：單元 1 有 14、單元 2 有 8、單元 3 有 6、單元 4 有 7。與 [asset-cues.md](asset-cues.md) 清單完全相符。角色設定圖、表情與地圖另計，不把它們混進這 35 張。
- `app/` 目前沒有 `.xcassets`。圖片集中由 [ArtView](../../app/KidsAI/UI/PlaceholderArt.swift) 顯示；角色由 [Characters.swift](../../app/KidsAI/UI/Characters.swift) 畫，地圖由 [MapView.swift](../../app/KidsAI/UI/MapView.swift) 的原生按鈕組成。
- 選項、聲音選項及拖曳列的圖片常只有 **44、48、56pt**；沙盒比較另有固定等大外框。驗收要看 App 裡的尺寸，不能只看 1024px 原圖。
- [PlaceholderArtTests](../../app/KidsAITests/PlaceholderArtTests.swift) 目前驗證暫代圖 key 和幾項暫代圖種類，不能證明 Asset Catalog 已打包，也不能判斷定稿圖的教學線索。
- 已有[模擬器驗證基準線](../release/verification-baseline.md)。[兒童試玩彙總](../playtests/unit1-report.md)仍空白；以前測試通過不代表新美術已驗收。

## Scope / Out of scope

這階段包含風格定案、角色設定與必要的靜態輸出、地圖、35 張內容圖、Asset Catalog 接入、素材完整性驗證，以及美術相關的 UI／實機／試玩驗收。App 圖示與商店截圖安排在四單元美術確認後製作；發布另走原本的流程。

沿用[首版範圍](../first-release-scope.md)：四單元、iPhone 直向、系統旁白與一起說、記憶體進度、家長卡。這次不新增 ASR、預錄配音、網路、內容 schema、進度保存或家長摘要。角色表情先做設定與輸出；目前 `DianDian`／`GuessHat` 只有尺寸參數，沒有表情狀態，第一輪接入不新增表情狀態機或角色動畫。

## 待 Michael 定案

1. ✅ **風格：A 扁平圓角**（2026-10-03 Michael 定）。原建議：A 扁平圓角：輪廓簡潔，比較容易保留小尺寸線索；這是製作建議，仍需用角色與題目實際尺寸確認，不能把草稿當核准。
2. ✅ **表情規格：照 art-spec**（2026-10-03 Michael 定；[generation-prompts.md](generation-prompts.md) 第 2 步已對齊）。原說明：[art-spec.md](art-spec.md) 第 3 節列點點 4 種、猜猜帽 5 種；[generation-prompts.md](generation-prompts.md) 的通用六表情與它不一致，缺少帽子的「不確定、道謝」。建議依 art-spec，再由 Claude 對齊 prompt 文件；未定案前不生成表情定稿。
3. 地圖的高保真稿及每張教學圖的核准。地圖首版仍需保留四島、鎖定、完成星星及下方問句；在既有版面放背景與插畫，任何重新排列按鈕的方案先另列差異供 Michael 核准。
4. ⏳ 使用工具的商用條款確認（Michael 之後確認；確認前角色與素材都只是 draft），以及試玩後是否繼續製作單元 2–4。「AI 看到的」欄仍依試玩另案決定。

## Task DAG 與交付門檻

主線：`D0 → D1 → D2 → D3 → D4 → D5 → D6`。工程接入方案 `E0` 可在 D0–D2 期間規劃；實作須經對應 L2 Plan 核准。`E0 → P2 角色接入 → P3 地圖接入 → P4 單元 1 接入` 完成後才進 D4。驗證前置 `E1` 要在各 UI PR 錄證據前完成對應部分，不能把新增流程拖到美術 PR 合併之後。

| 節點 | 工作與交付 | 前置條件 | 完成門檻／下一步 |
|---|---|---|---|
| D0 風格定案 | 比較現有 9 張，記錄風格、色票、表情規格及商用條款確認 | Michael 決策 | 明確記錄一個已選方向；同時修正 prompt 與角色規格的衝突 |
| D1 角色定稿 | 點點、猜猜帽各正／側／背面設定；依定案表情出設定圖；輸出首輪會用到的靜態正面圖 | D0 | 用等尺寸靜態預覽檢查 28pt、52pt、120–140pt 的輪廓與留白；透明背景、無圖中文字。這只核准來源圖；胸前愛心、AI 牌在實際 App 的辨識與疊字，仍須 P2 接入後驗收 |
| D2 地圖定稿 | Grok 依 App 現況做高保真構圖；製作四島地圖，留出按鈕與下方旁白位置 | D1 | 一般字級、SE 與 AX2 的設計預覽中，四島入口、鎖、完成狀態和問句都清楚；插畫不形成沒有互動的假按鈕，不把字或狀態烘焙進背景 |
| E0 圖片接入與檢查 | Claude 提 L2 Plan，新增 Asset Catalog、集中載入、編譯後素材檢查與分批遷移清單 | L2 Plan 核准；至少有已核准的測試素材 | 已核准素材可在實際 App bundle 解碼；缺圖／錯檔名會讓測試失敗；暫未製作的 key 有明確清單，不能任意以暫代圖掩蓋遺漏 |
| E1 驗證覆蓋前置 | 每個 UI PR 先列出受影響 feature／entry／素材，對照現有 flow；缺少的自動化流程另提測試與 harness PR | 實作 Plan 核准；可和 D1–D3 規劃並行 | 該 UI PR 所需的新增流程先合併，再以新 UI build 錄證據；自動化到不了的項目逐項寫原因與人工驗收方式，不得當成已通過 |
| D3 單元 1 的 14 張 | 沿用 P2 已接入的 `img_card_ai`，其餘 13 張依教學線索分組製作、核准、記來源，再放進 App | D2、E0；進 D4 前 P2／P3／P4 與各自 E1 必須完成 | 14 個 key 全部是已核准正式資源；來源與完整 prompt 可追溯；應有自動化證據的進入點都已補齊；實機或人工缺口逐項列出並排入 D4，不能籠統宣稱全覆蓋 |
| D4 單元 1 試玩與修正 | Michael 依既有 protocol 找 1–2 位 6–8 歲孩子；只交彙總；問題整理→Michael 排序→單一修正 Plan 核准→Claude 實作與工程回驗→依 Michael 決定再試玩 | D3；可用的實機 build | 記錄操作介入、角色辨識、AI 會猜／會錯的理解及看錯圖的位置；阻斷操作或教學線索錯誤須修正並回驗，必要的再試玩完成後由 Michael 同意擴批；非阻斷問題的延後須明列，不把小樣本設成統計通過率 |
| D5 單元 2–4 的 21 張 | 單元 2 的 8 張 → 單元 3 的 6 張 → 單元 4 的 7 張；每單元獨立 PR | D4 的修正確認與繼續決策 | 每單元的比較組與教學線索都驗收；全部 35 個 key 的暫代許可清單清空，CI 要求正式資源完整 |
| D6 四單元視覺收尾 | 全流程、小螢幕／AX2／實機檢查；確認資源體積；製作 App 圖示及實際 App 商店截圖 | D5 | 沒有缺圖、重要線索裁掉、角色混淆、狀態或按鈕被遮住；圖示與截圖經 Michael 核准；轉交[送審清單](../release/app-store-submission.md)，送審另提 L3 |

若 iPhone 暫時不可用，可以繼續 D0–D3 的成人素材檢查及模擬器驗證，D4 仍保持待辦；不能據此宣稱已完成孩子試玩或啟動 D5 批量定稿。

## 製圖優先順序與關鍵驗收

單元 1 先在 14 張內做高風險的教學圖：箱子只露尖耳朵、貓選項，再做天氣／早餐／動物三張不完整線索圖。接著是家人／玩具／猜猜帽、床／書包／浴室，最後貼紙。箱子以 asset-cues 的一隻耳朵為製圖基準；目前暫代圖畫兩隻，是替換時要核對的差異，不修改內容句子。

| 組別 | 必須看得出的事 | 不能因美化改掉的事 |
|---|---|---|
| 單元 1 天氣、早餐、動物影子 | 看出主題，但不能確定猜測對不對 | 不把晴天風格樣本當正式 `img_slot_weather`；不畫完整麵包牛奶或明確狐狸 |
| 單元 1 家人、玩具、猜猜帽 | 玩具是電子玩具；AI 卡與猜猜帽是同一角色 | 玩具不要畫成另一個點點；AI 牌保持 App 文字及無障礙語意 |
| 單元 2 星星杯與三張貓 | 杯上有星星；小黃貓坐著；大白貓站著且相對較大 | 三張貓用共用畫布與尺度；不可各自裁緊填滿，讓「大／小」差異消失 |
| 單元 3 蘋果組、小狗、夜晚、小車 | 同一蘋果只差眼鏡；狗有四隻可數的腳；月亮和星星；紅色小車 | 不用兩張獨立構圖的蘋果；不要遮腿、加太陽或把紅車畫成難辨識的紅形狀 |
| 單元 4 小車排序與太空野餐 | 同一台車的出門→下雨→撐傘；太空與野餐同時存在 | 不換車或場景造成其他先後線索；不能只用火箭代表野餐 |

每張先照 [art-spec](art-spec.md) 的比例、透明背景、尺寸與禁用內容檢查，再按 [asset-cues](asset-cues.md) 問一位未看過內容的大人。通過成人檢查仍需 Michael 核准；孩子試玩是另外的驗證。比較組先建立一張基準圖，再以它為參考只改指定差異；不逐張任意改構圖。

## Files 與 PR 切分

以下是候選變更範圍，由 Claude 的實作 Plan 確認實際檔名；本輪只寫本計畫。

| PR／交付 | 檔案範圍 | 風險與驗證 |
|---|---|---|
| 風格與規格紀錄 | `docs/art/art-spec.md`、`generation-prompts.md`、`provenance.md`；`design/art/` 的核准原圖與生成紀錄；`TODOS.md` 同步「已有草稿、待定案」 | 文件與素材；保留草稿及未核准標記，不改 App。來源記錄包括工具、日期、完整 prompt、參考圖、Michael 核准及衍生輸出 |
| P1 圖片載入與完整性檢查 | `app/KidsAI/Assets.xcassets/`（新）、`UI/PlaceholderArt.swift`，必要時新建集中載入 helper；`app/KidsAITests/AssetCatalogTests.swift`（新） | L2；每個階段有測試中的明確未遷移清單；對 bundle 解碼，不能只檢查資料夾名。沿用現有 CI 的 Swift 測試，不重建 CI |
| P2 角色接入 | `UI/Characters.swift`、角色 assets、`img_card_ai` 資源與共用渲染，必要時 `PlaceholderArt.swift`；非內容圖片資源清單與 bundle 測試 | L2；此 PR 一次提供 `img_card_ai`，P4 不另製作第二版。AI 卡、說話框與小徽章共用同一核准角色來源與 AI 疊字邏輯；在 App 實際尺寸驗收，並檢查 VoiceOver 語意，保留現有說話動畫與退路 |
| P3 地圖接入 | `UI/MapView.swift`、地圖 assets；非內容圖片資源清單與 bundle 測試；Grok 的地圖高保真參考 | L2；保留原生按鈕、鎖與星星、identifier、問句；若要調整字級、間距、觸控範圍或動畫，按流程加 Opus 設計審，另列規格差異 |
| P4 單元 1 接入 | 新增其餘 13 個 `img_*` imageset，沿用 P2 的 `img_card_ai`；必要的 `ArtView` 比例處理及測試；`docs/art/provenance.md` | L2；單元 1 全部 14 個 key 核准及驗收；來源圖與 App 中呈現都檢查，不改內容 JSON 或 key |
| 試玩報告／修正 | 報告只改 `docs/playtests/unit1-report.md`；每個修正另外提 Plan／PR | 彙總報告依既有 protocol，修正按實際影響分級，避免混進素材接入 PR |
| P5–P7 單元 2、3、4 | 各單元的 8／6／7 個 imageset、相關 UI 尺度與素材測試、`provenance.md` | 各自 L2；單元 2 要檢查 `SandboxViews.swift` 對 `PlaceholderArt.widthScale` 的依賴，替換後仍需保留相對尺寸；不直接改成逐張滿框 |
| P8 圖示及商店素材 | Asset Catalog 的 AppIcon；商店素材與送審文件 | 依實際範圍分級；只做素材不等於上傳。上傳／送審另提 L3，由 Michael 核准 |
| E1 的流程補齊 PR | `app/KidsAIUITests/Flows.swift`、必要的測試支援；`.claude/skills/verify-kidsai/lib/kidsai_flows.py`、相關工具測試與 Feature Map | 依實際變更分級，Claude 執行；一般工程 PR，並非每日維護。各美術 PR 前先交付相應測試能力，再用更新後 UI build 錄證據 |

所有孩子或家長看得到的 App 改動都走 PR。每個 UI PR 同步受影響的 `.claude/skills/verify-kidsai/references/features/`、`references/design-map.md`，並對照 Grok 的設計參考；若畫面沒有 mid-fi，就對照 Feature Map、token 與核准素材。

`app/project.yml` 目前已包含 `KidsAI` 來源目錄，新增其中的 catalog 後先用 XcodeGen 驗證是否自動打包；只有必要時才改 yml。不得手改 `.xcodeproj`，不得新增套件。原檔留 `design/art/`，App 只放適合裝置使用的衍生輸出，不把設定圖或整張表情 sheet 當執行期素材。

## Verification

計畫本身的最小檢查：連結存在、四單元及猜測庫共 35 個 key 與 asset-cues 相符、現有 UI 尺寸與測試覆蓋核對。本輪不改 App，無須為計畫重跑 Swift/UI 測試。

實作後最低檢查：

```bash
pipeline/.venv/bin/python pipeline/validate_content.py
pipeline/.venv/bin/python pipeline/validate_content.py --fixtures
cd app
xcodegen generate
xcodebuild -project KidsAI.xcodeproj -scheme KidsAI -destination 'generic/platform=iOS Simulator' build
```

App 單元測試另用 `KidsAI-Verify` 的實際 simulator destination，略過 UI tests；不可用 `generic` destination 宣稱跑過測試。新增素材測試要列舉單元、故事、回顧、貼紙、sandbox slot／choice 和猜測庫的 key，並在編譯後的 App bundle 驗證實際圖片可解碼。**角色、地圖等未出現在內容 JSON 的執行期圖片也要由 P2／P3 列入非內容資源清單，接受相同的 bundle 解碼測試**；實際資源名稱由各實作 Plan 確認，不新增內容 schema。設定圖與表情 sheet 是製作參考，不是執行期清單的一部分。分批期間，已遷移 key 缺圖必須失敗；35 張及非內容執行期圖完成後，不得再有未遷移許可。

依 [verify-kidsai skill](../../.claude/skills/verify-kidsai/SKILL.md)，每個 UI PR 重新 build／install／doctor，為受影響的 feature／entry 錄 `record --flow` 與最終截圖，逐張審查後 `evidence publish` 到證據 repo。不能沿用舊 commit 的證據。

| 改動 | 既有可用流程（需按實際 PR 選取） | 另外要補的範圍 |
|---|---|---|
| 角色 | `map-to-unit1`、`say-together`、`sandbox-open`、`story-branch`／`story-ending` | 儀式角色大圖、AI 小徽章及其他單元角色位置；現有流程不能代表全尺寸覆蓋 |
| 地圖 | `map-to-unit1`、`sticker`；`app-launch` 依 skill 的啟動錄影方式 | 初始／鎖定／完成狀態，SE、AX2、iPad 相容模式 |
| 單元 1 | `choice-answer`、`choice-reveal`、`sandbox-open`、`story-branch`、`story-ending`、`review-answer`、`sticker` | 箱子選圖、沙盒其餘主題、故事三張提示圖逐一到達；按現有測試實際觸及範圍補流程，不把流程名稱當全覆蓋證據 |
| 單元 2 | `drag-tap-to-place`、`sandbox-pick-and-react`、`sandbox-compare` | 第 1 關兩角色及貼紙等未覆蓋處；三張貓在實際小框中保留大小差異 |
| 單元 3 | `sandbox-graded`、`drag-group` | 蘋果選項、夜晚／紅車主題及貼紙等未覆蓋處 |
| 單元 4 | `drag-order` | 三個世界、角色與貼紙等未覆蓋處 |

缺少證據的進入點依 E1 先補適當的真實操作流程；新增測試與 harness 對應是另案的小 PR，不以啟動參數跳到最終畫面取代觸發。語音、手指拖曳、VoiceOver、減少動態效果依現有 Feature Map 由大人在實機補驗；模擬器影片沒有聲音。正式美術收尾再跑既有 17 條加上本階段所有新增流程，並補最低支援 iOS 的實際執行。

兒童試玩與工程證據分開：試玩**不錄音、不拍照、不錄影（含螢幕）**，repo 只收彙總。工程公開證據只用專用模擬器，不得出現兒童資料。

## Risks / rollback

- **圖好看但教錯：** 用每張的教學問題驗收，先完成單元 1 切片再擴批。若線索不合格，重做該張；不靠改正確答案迎合錯圖。
- **小尺寸失去線索：** 在 28／44／48／52／56pt 及使用中的大尺寸檢查。優先簡化圖與構圖；若需要放大圖框或改版面，重新提出設計變更與驗證。
- **比較圖相對大小消失：** 三張貓共用尺度與留白；檢查 `widthScale` 遷移。蘋果只改眼鏡，小車排序共用角色與場景。
- **地圖的視覺位置與可點範圍不同：** 原生按鈕與畫面圖形要對齊；保留 identifier 與無障礙順序，不能把互動做成整張圖的固定像素座標。
- **風格漂移／來源不清：** 用已核准角色作參考、逐組比較，來源與衍生檔關係完整記錄；商用條款未確認前不標記正式核准。
- **素材體積與品質：** 原檔與 App 衍生檔分開，量測加入前後的 Release build 大小；任何縮小／壓縮後都在 App 重看教學線索，不預設一個未經測試的體積上限。
- **回退：** 每 PR 一件事，原圖與上一版核准素材保留。遇到缺圖、教學線索退化或版面阻斷，回退該 UI PR 的資源與渲染變更，回到既有暫代版本重新驗證；不動內容契約、離線猜測或記憶體進度。

## 分工與執行入口

Michael：選風格、確認角色與素材、商用條款、安排試玩、決定修正與批量製作。Codex／Grok：依核准規格生圖；Grok 同步設計與 Notion。Claude Code：唯一程式寫手，提交每項 L2 實作 Plan 與 UI PR。Codex／Grok：審程式、教學線索與公開證據；觸發設計審時依流程加 Opus。

下一個執行入口是 **D0 的風格及表情規格定案**。定案後，Claude 用 `/agent-plan` 提出 P1 的具體接入方案，Michael 核准後才用 `/agent-action` 執行。地圖與其他 UI 決策跟各自 PR 核准，不把此路線圖當作一次授權所有改動。

## 本計畫審查

2026-10-03 已完成一次獨立 Codex 唯讀工程審及修訂後複審，未發現剩餘阻斷問題。採納的五項修訂：

1. D1 的來源圖／等尺寸預覽與 P2 的實際 App 疊字驗收分開。
2. 新增 E1 的流程與 harness PR 前置；UI PR 所需流程先完成，最後回歸包含本階段新增流程。
3. 角色與地圖等非內容執行期資源，同樣列入編譯後 App bundle 的解碼測試。
4. D4 明列修正 Plan、實作、工程回驗與必要再試玩的回路，再由 Michael 同意擴批。
5. P2 一次提供 `img_card_ai`，P4 沿用並只新增其餘 13 張，避免兩版角色來源。

另核對 35 個內容 key、14／8／6／7 分批數量、現有小圖尺寸、17 個流程的實際範圍與相對檔案連結。這是**規劃審查**，本輪沒有改 App、製作定稿或重跑 Swift／UI 測試。計畫可供 Michael 評估；風格、表情規格、素材及各項實作核准仍待完成。

實際參與：Codex 起草與來源核對；另一位 Codex agent 做獨立唯讀工程審及複審。本輪未要求 Claude 寫程式，也未由 Grok 修改設計或 Notion。

## 執行進度（2026-10-03）

- **E1 單元 1新增六條：完成。** Claude 已新增六條真實點擊流程及 CLI 對應；Codex 審查、套用提案並在新 build 執行，xcresult 確認 6 通過、0 失敗、0 跳過，驗證工具 103 個測試通過。Feature Map 與 design-map 已同步；六次錄製與本機視覺／隱私審查均完成，證據未發布。詳見[單元 1 美術證據覆蓋](unit1-art-evidence-coverage.md)；沙盒結語等未覆蓋入口仍待補。
- **P1：基礎程式與工程驗證完成，UI PR 準備中。** Claude 在 `art/p1-art-catalog`（基於 `0e1b793`）完成 Asset Catalog 接入、中央載入、35 個 key 的清單對照與 bundle 解碼檢查；Codex 工程審查、預設 Debug／Release 模擬器建置、78 個 App 單元測試及內容驗證均通過。Feature Map 與 design-map 已同步；提交後新 build 的畫面證據與 CI 結果以 PR 描述為準，尚未合併。35 張正式內容圖仍全部待製作／核准，工程 fixture 不代表美術定稿。詳見[P1 現況](p1-art-catalog-status.md)。
- **D0／D1–D6：待相應前置。** 尚無風格或表情規格定案；角色與地圖、14 張單元 1 定稿、兒童實機試玩、其餘 21 張及視覺收尾都未宣稱完成。

執行分工：Claude 寫程式；Codex 審查與操作驗證。Michael 已指示 commit 並 push `main`，本次提交範圍限 E1 測試、工具整合與相關文件；沒有改 App 畫面或內容。P1 的 UI 改動保留在獨立分支，完成後依 AGENTS.md 走 PR。
