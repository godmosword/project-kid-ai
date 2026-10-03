# 驗證基準線（模擬器）

更新：2026-10-03。對應 App 與內容的 commit `af48ad0`，Xcode 27.0，模擬器 iPhone 17e／iOS 27.0。

這份只記錄**模擬器上跑過、而且有 xcresult 或工具輸出可以對照的結果**，不是送審授權，也不代表可以發布。實機、試玩、法務與商店資料都還沒做（見下面「待補的輸入」）。範圍以[首版範圍](../first-release-scope.md)為準，送審資料的缺口以[送審清單](app-store-submission.md)為準。

## 已完成的檢查

| 項目 | 結果 | 說明 |
|---|---|---|
| 建置 | 通過 | Debug build-for-testing 與 Release 模擬器建置都成功 |
| App 單元測試 | 69／69 通過 | xcresulttool 確認 0 失敗、0 跳過 |
| verify-kidsai 工具測試 | 103 項通過 | |
| 內容與驗證器 | 通過 | 8 個內容檔全部通過，validator fixtures 全部通過 |
| UI 流程 | 17／17 通過 | 前 5 條用 `control-kidsai drive` 逐條跑，由 CLI 的 done／failed handshake 與流程本身的斷言證明；其餘 12 條併成一批 XCUITest，沿用現有的流程斷言，由 xcresult 確認（xcresulttool 顯示 Passed、12 passed／0 failed／0 skipped）。流程清單見[驗證地圖](../../.claude/skills/verify-kidsai/references/features/README.md) |
| 動態字級（輔助使用 2） | 2 條通過 | feature id `system-states`、進入點 `dynamic-type`；真實點擊的 `choice-answer` 與 `drag-tap-to-place` 都通過；run `20261003-101740-af48ad0`；跑完字級已改回 default |
| Release build 設定 | 11 項全部通過 | 沒有 Debug 啟動參數或觀察員選單的字串、沒有任何隱私權限 key、iPhone 直向、8 個內建 JSON 都在、宣告最低 iOS 17.0 |
| Privacy Manifest 申報內容 | 與預期一致 | `PrivacyInfo.xcprivacy` 申報「不追蹤」、「不收集資料」，而且需要說明理由的 API 那一欄是空的。這是**申報內容**的檢查，不等於執行期真的沒有用到這類 API |
| 需要說明理由的 API 符號 | 抽查沒有命中 | 用 `nm` 抽查部分直接引用的符號，沒有相符的；這是子集抽查，不是全面掃描 |
| 美術風格預覽 | 9 張 draft，已逐張看過 | 三種風格各 3 張，已記 SHA-256；沒有打包進 App。Codex 已經逐張檢視過全部 9 張；風格定案、正式角色一致性、教學線索驗收與商用授權確認都還要等 Michael，**不代表定稿美術已核准** |
| AX2 證據的視覺檢查 | 通過 | Codex 逐張看過：抽出的 7 格、2 張最終截圖、2 個 GIF 都只有 KidsAI 畫面和覆寫過的 status bar。`control-kidsai evidence review --ok` 成功，`images_checked=11`。證據留在本機，沒有發布到 PR |

## 限制

- 全部在模擬器上執行，沒有任何實機結果。
- 有幾條單獨跑的 UI run 遇到已知的 Xcode 27 收尾卡住：CLI 的處理方式是把卡住的 xcodebuild 停掉，並重開專用模擬器，**不是**重跑同一條流程。那幾條的通過是由 CLI 的 done／failed handshake 和流程斷言證明的，不是由 xcresult 證明。
- 截圖與錄影沒有聲音，所以旁白、語速／音高、「一起說」的實際發聲都沒有被證明。
- `nm` 抽查只是機械比對部分直接引用的符號，**不是**法務審查，也不是完整的隱私稽核。
- 美術只看過風格草稿，定稿美術還沒有產出，也還沒有核准。
- 孩子的[試玩報告](../playtests/unit1-report.md)這次沒有動（目前仍是空白模板），也沒有引用其中任何內容。

## 待補的輸入

全部待辦，沒有一項在這次驗證裡完成：

- 孩子的實機試玩。
- 尚需實機確認的項目：手指拖曳、語音、VoiceOver、減少動態效果。
- iOS 17 runtime 實際執行（目前只宣告最低 17.0，只在 iOS 27.0 跑過）。
- 小螢幕（最小到 iPhone SE）與 iPad 相容模式的實機確認。
- 定稿美術（風格定案、正式角色一致性、教學線索驗收），以及商用授權條款確認。預覽與限制見[美術風格預覽](../../design/art/README.md)。
- 開發者名稱、聯絡信箱、隱私權政策與支援網址、律師看隱私權政策與未成年人個資。
- 簽署的實機 archive、TestFlight、App Store 送審。

大人的開發機目前已經配對，但 Developer Mode 是關閉的、tunnel 不可用。這只會卡住**本機用 Xcode 裝到實機上執行與測試**；依 Apple 的[說明](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)，Developer Mode 不影響正常的 TestFlight 安裝。簽署的 archive、TestFlight 與商店資料是因為上面各自的條件還沒滿足而待辦，不是因為 Developer Mode。
