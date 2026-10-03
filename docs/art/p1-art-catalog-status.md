# P1 圖片載入與完整性檢查：現況

日期：2026-10-03。分支 `art/p1-art-catalog`，基準 `0e1b793`（已含 E1 新增的六條流程）。對應 [下一階段開發計畫](next-stage-plan.md) 的 **P1**（Asset Catalog 接入與素材完整性檢查）。

**這一輪只有工程接入，沒有任何美術素材。** 風格 A／B／C、表情規格、角色與地圖定稿、35 張內容圖、App 圖示全部仍待製作與 Michael 核准；畫面上看到的仍是原本的 `PlaceholderArt` 暫代圖，外觀、尺寸、字級、間距、動畫與 `widthScale` 都沒有改。

## 已實作

| 項目 | 檔案 | 說明 |
|---|---|---|
| 空的 App Asset Catalog | `app/KidsAI/Assets.xcassets/` | 只有 `Contents.json`，沒有任何 imageset。由 `sources: - KidsAI` 自動打包進 App target（`xcodegen generate` 後在 KidsAI 的 Resources build phase）。 |
| 中央清單與唯一載入點 | `app/KidsAI/Art/ArtResources.swift` | `Content.migrated`（已核准、已遷移）／`Content.pending`（待製作）／`runtime`（角色、地圖等非內容圖，P2／P3 填）；`image(named:in:)` 是唯一讀圖入口。 |
| 清單對照 | 同上 `ArtRegistryAudit` | `migrated ＋ pending` 必須剛好等於內容 JSON 用到的 `image` key；指名「內容用到但沒列」與「列了但內容沒用到」。 |
| bundle 解碼檢查 | 同上 `ArtCatalogAudit` | 對編譯後的 bundle 解圖，指名解不出來的 key；bundle 與清單都可注入。 |
| AI 卡保留給角色渲染 | `ArtResources.roleRenderedContentKeys`、`UI/PlaceholderArt.swift` | `img_card_ai` 永遠走共用角色渲染（`GuessHat` 畫帽上的「AI」牌與無障礙標籤「猜猜帽，AI」），不走 `ArtView` 的通用讀圖；即使 P2 把它列進 `migrated`（為了受 bundle 解碼檢查）也一樣。 |
| 測試 | `app/KidsAITests/AssetCatalogTests.swift`、`ContentImageKeys.swift` | 見下節。`PlaceholderArtTests` 的 key 走法改成共用 `ContentImageKeys`，原有的四條測試都保留。 |
| 修正 build | `app/project.yml` | 見「App 圖示」。 |

### 測試覆蓋

- 清單＝內容：`migrated ＋ pending` 等於 4 個單元與猜測庫的 35 個 key；重疊、漏列、拼錯、過期都會被指名。各單元 14／8／6／7 的分批數量也有測。
- 對照本身有效：用真實內容 key 做一組「少一個、多一個拼錯」的注入，驗對照真的會失敗並指名，不是把常數抄一遍。
- 實際 App bundle：預設清單（目前 `migrated`、`runtime` 都空）在宿主 App 的 bundle 解得出來；標成 `pending` 的 key 若已經在 App 裡解得出來也會失敗（清單與實際資源不一致）。
- 解圖路徑真的在解圖：注入測試 bundle 與測試素材，走同一個 `UIImage` 具名載入；缺圖與拼錯的 key 被指名，解得出來的不被指名。
- 測試素材不會上架：同一個 key 從 App bundle 必須解不出來。
- AI 卡：角色渲染的 key 列進 `migrated` 也不走通用讀圖；一般 key 遷移後才走，對照組一併驗。

## 工程用測試素材（不是美術素材）

`app/KidsAITests/TestAssets.xcassets/test_fixture_checker_8x8.imageset/test_fixture_checker_8x8.png`

| 項目 | 值 |
|---|---|
| 用途 | 只為了證明「編譯後的 Asset Catalog 真的解得出圖」。沒有正式素材時，這是唯一能證明檢查有效的方式。 |
| 內容 | 8×8 像素、RGBA、黑白格子的純色塊，不是任何角色、場景或題目圖 |
| 大小／雜湊 | 83 bytes；`sha256 92e959dc9e8fe6164c452b7974d875718c3eb56abcd4c8c24f85ea16d205ec14` |
| 來源 | Claude Code 用 Python 標準函式庫（`zlib`／`struct`）直接寫出 PNG。沒有用生成式工具、沒有參考圖、沒有第三方素材。 |
| 打包範圍 | 只在 `KidsAITests` target（`xcodegen generate` 後只出現在測試 bundle 的 Resources build phase）。App target 不含它，並且有測試斷言它在 App bundle 解不出來。 |
| 核准狀態 | **不是美術素材，不列入 [provenance.md](provenance.md)，也沒有、也不需要美術核准。** `provenance.md` 目前仍是空表＝尚無任何已核准的圖。 |

## App 圖示（暫不製作）

- **失敗原因：** XcodeGen 對 iOS application target 的內建預設帶 `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`（`SettingPresets/Product_Platform/application_iOS.yml`）。以前 `app/` 沒有任何 `.xcassets`，`actool` 不會跑，這個設定是空轉；P1 一加入 `KidsAI/Assets.xcassets`，`actool` 開始編譯資源，找不到 `AppIcon` 就讓 Debug／Release build 直接失敗。
- **這一輪的處理：** 在 `app/project.yml` 的 `KidsAI` target 設 `ASSETCATALOG_COMPILER_APPICON_NAME: ""`，意思是「這個 target 現在不指定 App 圖示」。沒有新增 `AppIcon.appiconset`，沒有放任何圖示圖檔，也沒有任何圖示被核准。
- **D6／P8 怎麼接回去：** 圖示排在 [計畫](next-stage-plan.md) 的 D6（四單元視覺收尾）與 P8（圖示及商店素材）。屆時由 Michael 核准圖示稿後，在 `app/KidsAI/Assets.xcassets/` 加入 `AppIcon.appiconset`（1024px，Kids Category 的規定見 [送審清單](../release/app-store-submission.md)），把 `project.yml` 這行改回 `AppIcon`，並把來源記進 `provenance.md`。在那之前，模擬器與測試機上的圖示是系統預設的白底，不是缺陷。
- 先前為了定位問題，在命令列用 `ASSETCATALOG_COMPILER_APPICON_NAME=''` 覆寫過一次 build；那只是診斷，**不代表預設 build 已修好**。本次已從 `project.yml` 重新產生專案，預設 Debug 與 Release 模擬器 build 均通過。

## 尚未驗證／仍待辦

- **程式提交前的工程驗證由 Codex 完成：** XcodeGen、預設 Debug build-for-testing、generic Debug build、generic Release 模擬器 build 均通過，沒有用命令列覆寫 AppIcon 設定。iPhone 17e／iOS 27.0 的 78 個 App 單元測試通過（含新增 9 個測試，0 失敗、0 跳過）；內容與正反例驗證通過。本機摘要為 `.verify/p1-verification-summary.json`，原始 log／xcresult 不進 git。這些結果證明工程接入與檢查機制，不代表正式美術或實機已驗收。PR 的 CI 結果與提交後新 build 的 UI 證據另列在 PR 描述。
- **35 個內容 key 全部 `pending`**，`migrated` 與 `runtime` 都是空的。測試現在證明的是「清單與內容一致、檢查機制有效」，不是「已經有正式圖」。
- **風格、表情規格未定案**（計畫的 D0）：A／B／C 未選、`art-spec.md` 與 `generation-prompts.md` 的表情清單仍衝突。角色（D1）、地圖（D2）定稿、單元 1 的 14 張（D3）都還沒開始。
- **沒有任何素材核准、沒有商用條款確認、沒有來源紀錄**；`provenance.md` 空表維持原狀。
- 測試證明不了教學線索（圖是否讓孩子看得出題目）、小尺寸辨識、實機外觀與孩子試玩；這些依計畫在 D1–D4 另外驗收。
- `PlaceholderArt.widthScale` 還沒動。遷移把「相對大小」畫進共用畫布的 key（單元 2 三張貓、單元 3 兩顆蘋果）時，要同批把倍率改成 1，否則會再乘一次；這留給 P4／P5。

## Feature Map 與設計對照

P1 改到 `UI/PlaceholderArt.swift` 的 `ArtView`，依 AGENTS.md 與 [AGENT-WORKFLOW](../AGENT-WORKFLOW.md) 走 UI PR，同步 Feature Map 與 `design-map.md`。本次已同步驗證範圍與仍需人工驗收的限制。

孩子與家長看得到的行為沒有改變：暫代圖的查表、外觀、`ArtView` 的框大小與 `PlaceholderArt.widthScale` 都不變；35 個 key 全部 `pending`、`migrated` 是空的，所以畫面上仍然是原本的暫代圖。AI 卡（`img_card_ai`）不論清單狀態都由共用角色渲染（`GuessHat`）畫出帽上的「AI」牌與無障礙標籤「猜猜帽，AI」。

功能檔「不寫實作細節」（`features/README.md` 的 Feature entry contract），所以同步的內容是**驗證範圍**的註記，不是新的使用者流程、也不是新的設計決定；四個 H2 的契約不變：

| 檔案 | 這次加的註記 |
|---|---|
| `references/features/README.md` | 一條 2026-10-03 的 Proof 註記：素材可從 Asset Catalog 讀，但 35 個內容圖 key 目前全是暫代圖、畫面不變；AI 卡由共用角色渲染；正式素材換上去後「可證明」仍只證明元素在畫面上，圖本身要逐張看證據與人工驗收 |
| `references/design-map.md` | 一條 2026-10-03 的註記：P1 沒有改畫面，各屏差異不變；正式素材（P2／P3／P4）放上去時用新 build 的證據重新對照每一屏的圖，再把新的差異列進對應小節 |
| `references/features/sandbox.md` | 一條 Gotcha：三張貓換成正式素材後，流程抓不到「大小關係消失」，要在證據裡人工確認站著的大白貓看起來比坐著的小黃貓大 |
| `references/features/drag.md` | 一條 Gotcha：卡片上的圖沒有自己的無障礙標籤，流程只斷言卡與目標；排序的先後線索、分組卡的主題換圖後要人工驗收 |
| `references/features/review-and-sticker.md` | 一條 Gotcha：貼紙圖有無障礙標籤但 `sticker` 流程沒有斷言它，只在錄影與截圖裡看得到 |

`features/choice-question.md` 與 `features/story.md` 已有等效敘述（選項圖是裝飾性元素、換圖要人工驗收；提示圖要看影片裡被橘框標出的那一下），這次不重複加。`map.md`、`unit-flow.md`、`say-together.md`、`system-states.md`、`observer-menu.md` 不顯示內容 `image`，不動。

Claude 的提案已由 Codex 檢查並套用（基準 `0e1b793`）；只改上表五份參考文件，沒有改 harness、SKILL.md 或流程清單。功能檔四個 H2 的契約與相對連結另做機械檢查。`.verify/` 在 `.gitignore` 裡，所以 patch 本身是交接用的本機檔案，不進 git；進 PR 的是套用後的 `references/` 變更。

這裡動到 `.claude/skills/verify-kidsai/references/` 不是每日維護：AGENTS.md 的每日維護限制（只能改 `SKILL.md` 與 `references/`、只開 draft PR、不得發布證據）說的是 launchd 的 `/maintain-verification-skill`；UI PR 要同步 Feature Map 與 `design-map.md` 是另一條規定，走一般工程 PR，由 Michael 合併。

受影響畫面的證據要照 [verify-kidsai skill](../../.claude/skills/verify-kidsai/SKILL.md) 用這個分支的 build 重錄（`UI/PlaceholderArt.swift` 有改，即使預期畫面相同）。會顯示內容圖的 feature 是 choice-question、sandbox、drag、story、review-and-sticker；本分支已基於 `0e1b793`，E1 的六條流程（`choice-box`、`sandbox-ritual`、`sandbox-breakfast`、`sandbox-animal`、`story-hint-bag`、`story-hint-bath`）可以直接用來錄單元 1 的素材進入點。沙盒結語（sandbox `closing`）與故事的 `find-together` 仍是 `needs-flow`，貼紙圖仍沒有被斷言：照實回報，不得用別的進入點代替。P2 真的放進角色與地圖資源時，再按計畫做 Feature Map 與設計對照的實質更新。
