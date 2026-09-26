---
name: verify-kidsai
description: "在 Michael 的 Mac 上用專用 iOS 模擬器（KidsAI-Verify）啟動 KidsAI App、做健康檢查、操作、錄下截圖與影片證據，並發布到公開證據 repo godmosword/project-kid-ai-evidence。改到孩子或家長看得到的畫面或流程時，用它產生 PR 的證據；也用它回歸檢查整個 App。"
disable-model-invocation: true
---

# Verify KidsAI

KidsAI 是給 5–8 歲孩子的 SwiftUI iOS App（單元 1–4，地圖 → 單元 → 貼紙）。這個 skill 用 `control-kidsai` 在**專用模擬器**上操作它並留下證據。證據會公開，**永遠不得有兒童資料**。

`control-kidsai --help` 列出所有命令、旗標和範例；每個命令輸出 JSON，失敗時附 `fix`（修法）與固定的結束碼：0 成功｜2 用法錯｜3 環境不對｜4 拒絕危險操作｜5 外部命令失敗｜6 證據不合格｜7 舊 build。

```bash
C=.claude/skills/verify-kidsai/control-kidsai   # 在 repo 根目錄執行
```

## Launch

- 只用專用模擬器 `KidsAI-Verify`（每日維護用 `--sim KidsAI-Maintain`）。任何其他模擬器都會被拒絕（exit 4），不會碰到 Michael 自己的模擬器。
- 第一次：`$C sim ensure`（建立 iPhone 17e／最新 iOS runtime，不支援時退 iPhone 16e；都是 390×844 pt）。
- 每次：
  ```bash
  $C sim boot && $C sim statusbar          # 開機；status bar 固定 9:41、Wi-Fi、滿電、不顯示電信業者
  $C build && $C install                   # xcodegen＋xcodebuild（Debug），寫 .verify/build.json
  $C launch                                # 從主畫面打開 App（會先關掉舊的）
  ```
- 啟動參數（**只在 Debug build**，只能用來準備前置狀態，不能當證明本身）：`$C launch --unit <0-3> --beat <n>`（直接進某單元的某關）、`--unlock-all`（地圖四個島都可進）、`--events "<操作>"`（開場後套用一串操作，例如 `place:cup_star:blank_where;check`）。單元與關卡編號見 `references/features/README.md`。
- 準備好的判斷：`$C doctor` 回傳 `"ok": true`。App 本身沒有就緒訊號；要等畫面上看得到的最終狀態（見各功能檔），不要用固定秒數當證明。
- 結束：見 Cleanup。

## Doctor

`$C doctor` 是唯讀檢查，回答「這台模擬器上的 App 值得操作嗎？」。第一次操作前、任何怪事之後、每個失敗的操作之後都要跑。逐項回報：

| 檢查 | 失敗時 | 修法 |
|---|---|---|
| xcode | exit 3 | `xcode-select --install` |
| simulator 存在 | exit 3 | `$C sim ensure` |
| booted | exit 3 | `$C sim boot` |
| statusbar 已覆寫 | exit 3 | `$C sim statusbar` |
| only-kidsai（除 Apple 內建外只裝 KidsAI） | exit 3 | `$C sim erase --yes`，再 build、install |
| installed | exit 3 | `$C build && $C install` |
| debug-build（有啟動參數） | exit 3 | `$C build && $C install` |
| fresh-build（安裝的 App 等於目前原始碼） | **exit 7** | `$C build && $C install` |
| screen（截圖 1170×2532） | exit 3 | 刪掉模擬器後 `sim ensure` 重建 |

**舊 build 錄的影片不算證據**：fresh-build 比對原始碼指紋（HEAD＋`app/`、`content/` 的未提交改動與未追蹤檔）和已安裝的程式碼（主執行檔＋`KidsAI.debug.dylib`；Xcode 的 Debug build 把程式放在 dylib，主執行檔只是小殼）。

## Drive

V1 沒有點擊自動化（V2 才加 XCUITest＋accessibilityIdentifier）。現在能做的只有：

- **打開 App**：`$C launch`（真實使用者路徑：從主畫面打開）。
- **準備前置狀態**：`$C launch --unit/--beat/--unlock-all/--events`。
- **看結果**：`$C screenshot`、`$C record start/stop`。
- 需要點擊才能證明的步驟，在功能檔標 `needs-V2-driver`。**不得**用 `--events` 或 `--beat` 冒充點擊的證明：它們跳過了孩子實際的操作。
- 語音：模擬器可能沒有 zh-TW 語音，這時字會一次全部顯示（CRITICAL-9 的路徑）；錄影沒有聲音。截圖與錄影**證明不了語音**，只能證明畫面。
- 旁白時間不固定：等畫面出現最終狀態再截圖，不要只睡固定秒數就宣稱完成。

## Evidence

每次證明是一個 run，放在 repo 根目錄的 `.verify/<run-id>/`（gitignore；cleanup 不會刪）。run-id＝`YYYYMMDD-HHMMSS-<7 碼 sha>`（台北時間）。

```bash
RUN=$($C run new --feature map --entry app-launch | python3 -c 'import sys,json;print(json.load(sys.stdin)["run"])')
$C record start --run $RUN --name map-launch     # 先開錄：觸發動作要在影片裡
$C launch                                        # 觸發
# 等畫面出現最終狀態（功能檔寫的「看得到什麼」）
$C screenshot --run $RUN --name map-islands      # 最終狀態
$C record stop --run $RUN --name map-launch      # ≤20 秒、h264；另產 GIF
```

**Proof bar（證明標準）：**

- 走真實使用者路徑。啟動參數只能準備前置狀態。
- 同一段錄影裡要有**觸發動作**和**最終狀態**；截圖是最終狀態的清楚畫面。
- 先跑 doctor；舊 build（exit 7）錄的不算。
- 讀 `references/features/` 裡相關的功能檔，每個受影響的進入點都要走到；走不到的要寫明進入點和原因（例如 `needs-V2-driver`），不得用別的路徑代替後宣稱已驗證。
- 每個證據都寫明 feature id 和進入點（`run new --feature --entry`）。
- 回歸掃描：依 `references/features/README.md` 由上而下走。

**發布到證據 repo（PR 用）：**

1. 開 draft PR 取得編號 `N`。
2. **畫面內容審查（一定要做）**：`$C evidence frames --run $RUN` 把影片每 2 秒抽一格；**逐張看過**所有截圖、GIF 和抽出的格，確認畫面只有 KidsAI，或專用模擬器的主畫面（只有 Apple 內建 App 圖示；從主畫面打開 App 就是孩子的真實路徑），加上覆寫後的 status bar；沒有通知、系統對話框、其他 App 的內容或任何個人資料（Michael 2026-09-26 定案）。看完才 `$C evidence review --run $RUN --ok`。沒有這一步，publish 會拒絕（exit 6）。
3. `$C evidence publish --pr N --run $RUN --dry-run`（完全不寫入、不連網：只做本機檢查、列出會做的事）。
4. `$C evidence publish --pr N --run $RUN`：只接受 CLI 產生的檔（manifest 以外的檔、連結、子目錄都拒絕）、副檔名 png／gif／mp4／json、每檔 ≤10 MB、manifest 不含本機路徑／使用者名稱／裝置 ID、sha256 對得上、目標路徑已存在就不覆寫。推到 `pr-N/<run-id>/`，用 Mac 既有的 gh 登入；CLI 不讀取、不保存 token。
5. 把輸出的 `markdown` 放進 PR 描述的「證據」區：`gh pr edit N --body-file <檔>`。PNG／GIF 以 raw 連結內嵌（手機 App 看得到），MP4 與 manifest 是連結。
6. 證據有問題要刪：**停下來問 Michael**，他同意才刪。CLI 不提供刪除命令。

## Cleanup

```bash
$C cleanup --dry-run   # 列出會停掉什麼
$C cleanup             # 只停本次啟動的：錄影（核對 pid 身分）、App、以及本次開機的模擬器
```

- 依 `.verify/session-<sim>.json` 記錄的資源清理；**不依 process 名稱 kill**，不關別人開的模擬器。
- **不刪證據**：`.verify/<run-id>/` 永遠保留。清理後確認證據還在：`ls .verify/$RUN`。
- 每次操作失敗後也要 cleanup，避免殘留錄影程序。

## Helpers

- `control-kidsai`（本目錄，可執行，Python 3 標準函式庫）：`$C --help`。子命令：`doctor`、`sim ensure|boot|shutdown|erase|statusbar`、`build`、`install`、`launch`、`terminate`、`run new`、`screenshot`、`record start|stop`、`cleanup`、`evidence frames|review|md|publish`。破壞性命令有 `--dry-run`；`sim erase` 一定要 `--yes`。
- 測試：`python3 -m unittest discover .claude/skills/verify-kidsai/tests`（不需要 Xcode、模擬器或網路）。
- 需要：Xcode、XcodeGen、ffmpeg／ffprobe（`brew install ffmpeg`，產生 GIF 與驗證錄影）、已登入的 `gh`（發布證據）。
- 功能地圖：[`references/features/`](references/features/)（每個功能一個檔，四個 H2：`Sub-features`、`How to get to it (user POV)`、`Driving it with control-kidsai`、`Gotchas`）。這裡刻意用 `references/features/`，不是 generator 預設的 `features/`，和 pstack 範例 repo 一致。
- 維護：用 `/maintain-verification-skill`（來源 pstack `cursor/plugins@ecc249f`，放在 `~/.claude/skills/`）保持地圖和 App 一致。只能改這個目錄；最多開一個 PR；不得自己合併。
