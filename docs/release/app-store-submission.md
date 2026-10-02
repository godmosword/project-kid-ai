# App Store 送審資料（首版）

更新：2026-10-02。照首版實際行為整理（[首版範圍](../first-release-scope.md)、Notion「合規／資料流 Checklist v1.2」）。App 改了會用到資料的功能，這份和[隱私權政策](privacy-policy.md)、`app/KidsAI/PrivacyInfo.xcprivacy` 都要一起改。

## 還沒準備好的

| 項目 | 狀態 | 誰 |
|---|---|---|
| 聯絡信箱（政策與 App Store 的支援聯絡） | 佔位符，送審前填 | Michael |
| 隱私權政策網址、支援網址 | 未定（GitHub Pages 或其他） | Michael |
| 律師看隱私權政策與未成年人個資（Checklist T1） | 待做 | Michael |
| 讀 Review Guidelines 1.3、5.1.4（Checklist R1） | 下面已逐條對照，送審前再看一次最新版 | Michael |
| 開發者名稱、App 名稱是否沿用 KidsAI | 待定 | Michael |
| 定稿美術、商店截圖、App 圖示 | 等美術 | Michael／Grok |
| 實機試玩、TestFlight | 等 iPhone 配對 | Michael |

## App Store Connect 要填的

- **主要類別：** 教育。
- **Kids Category：** 是，年齡帶 **6–8**（Checklist Q6=A）。勾選後很難撤回。商店描述寫「5 歲的孩子在大人陪伴下也適合」。
- **App 隱私（營養標籤）：** **不收集資料（Data Not Collected）**。理由：
  - App 不連網，也不傳任何東西出裝置。
  - 進度只在記憶體（D30）。
  - 沒有帳號，也沒有第三方 SDK。
- **年齡分級問卷：** 每一題都選「無」（沒有暴力、恐怖、成人主題、賭博、不受限的網頁瀏覽、使用者產生內容、聊天或購買）。
- **出口合規（加密）：** 只用系統提供的功能，沒有自己的加密。`ITSAppUsesNonExemptEncryption = NO` 寫在 `app/project.yml`，上傳時就不會再問。
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

> KidsAI is a children's app (Kids Category, ages 6–8) that teaches that "AI guesses, can be wrong, and can be taught." No account or login is needed. Open the app, tap the first island ("認識島"), and follow the on-screen narration; tapping the large green button moves to the next step. To leave a unit, press and hold the X in the top-left corner for 1.5 seconds (a short tap only shows a reminder). Completing an island unlocks the next one. The app makes no network requests, collects no data, and contains no ads, analytics, external links, or purchases. Progress is kept in memory only and resets when the app is closed.

## 正式版（Release build）的確認

- 只給測試用的啟動參數（`-openUnit`、`-beat`、`-events`、`-unlockAll`）和觀察員選單都包在 `#if DEBUG` 裡。2026-10-02 建 Release build 檢查過，執行檔裡沒有這些字串。
- `Info.plist` 沒有任何 `*UsageDescription`（不用麥克風、相機等）。
- Privacy Manifest：`app/KidsAI/PrivacyInfo.xcprivacy` 申報不追蹤、不收集資料、沒有用到需要說明理由的 API。
