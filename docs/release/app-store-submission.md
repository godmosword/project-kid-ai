# App Store 送審資料（首版）

更新：2026-10-02。照首版實際行為整理（[首版範圍](../first-release-scope.md)、Notion「合規／資料流 Checklist v1.2」）。App 改了會用到資料的功能，這份和[隱私權政策](privacy-policy.md)、`app/KidsAI/PrivacyInfo.xcprivacy` 都要一起改。

## 還沒準備好的

| 項目 | 狀態 | 誰 |
|---|---|---|
| 聯絡信箱（政策與 App Store 的支援聯絡） | 佔位符，送審前填 | Michael |
| 隱私權政策網址、支援網址 | 未定（GitHub Pages 或其他） | Michael |
| 律師看隱私權政策與未成年人個資（Checklist T1） | 待做 | Michael |
| 讀 Review Guidelines 1.3、5.1.4（Checklist R1） | 下面已逐條對照，送審前再看一次最新版 | Michael |
| 開發者名稱（政策裡的「我們」）、App 名稱是否沿用 KidsAI | 待定 | Michael |
| Kids Category 年齡帶再確認：勾 6–8，但描述寫 5 歲可共玩（Checklist Q6=A）。Grok 審提醒：Apple 可能要求跨年齡帶時勾最小的一檔。送審前和律師一起確認 | 待確認 | Michael |
| iPad 相容模式的橫向（審查員常用 iPad 測） | 實機確認一次 | Michael |
| 定稿美術、商店截圖、App 圖示 | 等美術 | Michael／Grok |
| 實機試玩、TestFlight | 等 iPhone 配對 | Michael |

## App Store Connect 要填的

- **主要類別：** 教育。
- **Kids Category：** 是，年齡帶 **6–8**（Checklist Q6=A）。勾選後很難撤回。商店描述寫「5 歲的孩子在大人陪伴下也適合」。
- **App 隱私（營養標籤）：** **不收集資料（Data Not Collected）**。理由：
  - App 不連網，也不傳任何東西出裝置。
  - 進度只在記憶體（D30）。
  - 沒有帳號，也沒有第三方 SDK。
- **年齡分級問卷：** 內容類題目都選「無／否」（沒有暴力、恐怖、成人主題、賭博、不受限的網頁瀏覽、使用者產生內容或聊天）。「為兒童製作（Made for Kids）」選「是」、年齡帶 6–8。問卷會改版，送審前照最新版逐題確認。
- **出口合規（加密）：** 只用系統的 CryptoKit 算 SHA-256（檢查內建內容的核准碼），沒有自己實作加密，也沒有網路傳輸，屬於豁免。`app/project.yml` 已設定 `ITSAppUsesNonExemptEncryption = NO`。如果 App Store Connect 另外問「是否使用加密」，回答「是」，再選豁免。
- **價格與內購：** 沒有 App 內購買。

## Kids Category 規定對照

| 規定 | KidsAI |
|---|---|
| 1.3、5.1.4：不得有第三方分析或廣告 | 沒有任何第三方套件（AGENTS.md 硬規則） |
| 1.3：連到 App 外或購買前要有家長閘 | 沒有外部連結，也沒有購買，所以不需要家長閘 |
| 5.1.4：不得傳出可識別個人的資料 | 不連網、不收集資料 |
| 5.1.1：要有隱私權政策 | [草稿](privacy-policy.md)，網址待定 |
| 2.3：描述與截圖要和 App 一致 | 等定稿美術再做截圖 |

## 給 App Review 的說明（英文，貼到 Review Notes）

> KidsAI is a children's app (Kids Category, ages 6–8) that teaches that "AI guesses, can be wrong, and can be taught." The app is in Traditional Chinese with Mandarin narration; please turn the sound on. No account or login is needed. "認識島" (the first island) is the only island unlocked at start; tap it and follow the narration. Each step asks the child to tap an answer, place cards, or react to a guess; when a step is done, a green "下一步" (Next) button appears at the bottom. To leave a unit, press and hold the X in the top-left corner for 1.5 seconds (a short tap only shows a reminder). Completing an island unlocks the next one. The "給大人" (For grown-ups) card on each unit's last page is static co-play tips only, with no links, settings, or purchases, so no parental gate is needed. iPhone only, portrait only; on iPad it runs in iPhone compatibility mode. The app makes no network requests, collects no data, and contains no ads, analytics, external links, or purchases. Progress is kept in memory only and resets when the app is quit (swiped away in the app switcher) or closed by iOS.

## 正式版（Release build）的確認

- 只給測試用的啟動參數（`-openUnit`、`-beat`、`-events`、`-unlockAll`）和觀察員選單都包在 `#if DEBUG` 裡。2026-10-02 建 Release build（`xcodebuild -configuration Release`）用 `grep -a` 掃執行檔，沒有這些字串。送審前用要上傳的那個 build 再掃一次。
- `Info.plist` 沒有任何 `*UsageDescription`（不用麥克風、相機等）。
- Privacy Manifest：`app/KidsAI/PrivacyInfo.xcprivacy` 申報不追蹤、不收集資料、沒有用到需要說明理由的 API。
  - 查證方式：`nm -u` 看 Release 執行檔引用的符號，沒有 Apple 清單上的 API（`systemUptime`、`mach_absolute_time`、`UserDefaults`、檔案時間戳、磁碟空間、鍵盤清單）。
  - App 用到的 `ContinuousClock`（Swift 標準庫）、`FileManager.contentsOfDirectory`（只讀 App 內建的課程檔，不取屬性）、`AVAudioSession` 都不在清單上。
  - 之後如果加了清單上的 API（例如用 `UserDefaults` 存進度），要在 manifest 補上理由。
