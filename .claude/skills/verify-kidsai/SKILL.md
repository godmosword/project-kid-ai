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
| text-size（字級是系統預設） | exit 3 | `$C sim text-size --size default`（大字級的證據錄完要改回來；每日維護收尾時 wrapper 會自動改回） |
| only-kidsai（除 Apple 內建外只裝 KidsAI） | exit 3 | `$C sim erase --yes`，再 build、install |
| installed | exit 3 | `$C build && $C install` |
| debug-build（有啟動參數） | exit 3 | `$C build && $C install` |
| fresh-build（安裝的 App 等於目前原始碼） | **exit 7** | `$C build && $C install` |
| screen（截圖 1170×2532） | exit 3 | 刪掉模擬器後 `sim ensure` 重建 |

**舊 build 錄的影片不算證據**：fresh-build 比對原始碼指紋（HEAD＋`app/`、`content/` 的未提交改動與未追蹤檔）和已安裝的程式碼（主執行檔＋`KidsAI.debug.dylib`；Xcode 的 Debug build 把程式放在 dylib，主執行檔只是小殼）。

## Drive

兩種操作方式：

**1. 真實點擊（XCUITest，首選）。** 流程測試在 `app/KidsAIUITests/Flows.swift`，每支一個類別，靠 `accessibilityIdentifier` 找元素（表列在 `references/features/README.md`）。

```bash
$C build --for-testing && $C install && $C doctor      # doctor 的 ui-tests 要是「和目前原始碼一致」
$C drive --flow sandbox-pick-and-react                 # 只跑、不截圖：回報通過或失敗（連跑 3 次抓不穩定）
```

可用的流程：`map-to-unit1`、`say-together`、`sandbox-pick-and-react`、`drag-tap-to-place`、`story-branch`、`sticker`、`choice-answer`、`sandbox-graded`、`hold-to-exit`、`background-resume`、`sandbox-compare`、`drag-group`、`choice-reveal`、`sandbox-open`、`story-ending`、`review-answer`、`drag-order`（各自證明什麼見 `references/features/README.md` 的 Full sweep）。每支流程只用啟動參數準備前置狀態，要證明的動作一定是真的點擊；等待一律等「元素可點」（30 秒上限），不用固定秒數。

**2. 只打開 App 或準備前置狀態。** `$C launch`（從主畫面打開）、`$C launch --unit/--beat/--unlock-all/--events`。**不得**用 `--events` 或 `--beat` 冒充點擊的證明：它們跳過了孩子實際的操作。

- 語音：模擬器可能沒有 zh-TW 語音，這時字會一次全部顯示（CRITICAL-9 的路徑）；影片沒有聲音。截圖與影片**證明不了語音**，只能證明畫面。
- 旁白時間不固定：等畫面出現最終狀態，不要只睡固定秒數就宣稱完成。
- **Xcode 27 的限制（2026-09 實測）**：
  - UI 測試執行期間**不能用 `simctl` 錄影**，否則 `xcodebuild` 會一直卡在收尾（"waiting for test log to finish recording"）。所以真實點擊的證據用「測試裡的截圖接成縮時影片」（見 Evidence）。
  - 即使不錄影，`xcodebuild` 偶爾也會在測試結束後卡住（常見於重開模擬器、重新 build 後的第一次）。CLI 以測試自己寫的 `done`／`failed` 判斷通過；旗標出現 30 秒後還沒結束，就停掉 `xcodebuild` 並重開專用模擬器（輸出 `"xcodebuild_hung": true`）。卡住後不重開，之後每次都會卡。
- Mac 閒置睡著時模擬器會停住，測試會慢到逾時：CLI 用 `caffeinate -i` 包住 UI 測試；手動跑 `xcodebuild test` 時也要這樣做。
- 一般跑 App 的單元測試時略過 UI 測試：`xcodebuild … test -skip-testing:KidsAIUITests`。
- xcresult 不寫進專案：`drive`、`record --flow`、`snapshot` 的 `-resultBundlePath` 指到 `/tmp/kidsai-xcresult/<時間>-<標籤>.xcresult`。跑完只在 `.verify/summaries/` 留一份小 JSON（`passed`、`commit`、`time`），不留整個 xcresult。失敗時可 `open` 那個暫存 bundle 看步驟。

## Evidence

每次證明是一個 run，放在 repo 根目錄的 `.verify/<run-id>/`（gitignore；cleanup 不會刪）。run-id＝`YYYYMMDD-HHMMSS-<7 碼 sha>`（台北時間）。

**真實點擊的證據（首選）：**

```bash
RUN=$($C run new --feature sandbox --entry multi-card | python3 -c 'import sys,json;print(json.load(sys.stdin)["run"])')
$C record --flow sandbox-pick-and-react --run $RUN     # 前置畫面 → 真實點擊 → 最終狀態
$C snapshot --run $RUN --name sandbox-tree --unit 1 --beat 5   # 需要時：無障礙元素樹（JSON）
```

`record --flow` 不錄影：測試約每 0.5 秒截一張圖，CLI 以 4 fps 接成 ≤20 秒的**縮時影片**（MP4＋GIF），點擊前兩格用橘色框標出被點的元素，最後一格另存成 `<flow>-end.png`。流程沒通過就不留任何證據（exit 6）。

**只打開 App 的證據（V1 的做法，例如 `map/app-launch`）：**

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
- 讀 `references/features/` 裡相關的功能檔，每個受影響的進入點都要走到；走不到的要寫明進入點和原因（`needs-flow`：還沒有流程測試；`verified-unreachable`：自動化到不了，寫明缺的前提），不得用別的路徑代替後宣稱已驗證。
- 改到的畫面要對照 `references/design-map.md` 的設計稿，列出新的差異。
- 每個證據都寫明 feature id 和進入點（`run new --feature --entry`）。
- 回歸掃描：依 `references/features/README.md` 由上而下走。

**發布到證據 repo（PR 用）：**

1. 開 draft PR 取得編號 `N`。
2. **畫面內容審查（一定要做）**：`$C evidence frames --run $RUN` 把影片每 2 秒抽一格；**逐張看過**所有截圖、GIF 和抽出的格，確認畫面只有 KidsAI，或專用模擬器的主畫面（只有 Apple 內建 App 圖示，加上本專案的 KidsAI 與 UI 測試 runner 圖示——2026-09-28 定；從主畫面打開 App、進背景再回來都是孩子的真實路徑），加上覆寫後的 status bar；沒有通知、系統對話框、其他 App 的內容或任何個人資料（Michael 2026-09-26 定案）。有 `snapshot` 的元素樹 JSON 時，**整份讀過**，確認裡面只有 App 的內容文字與 identifier，沒有任何個人資料（CLI 只擋得住本機路徑、使用者名稱與裝置 ID）。看完才 `$C evidence review --run $RUN --ok`。沒有這一步，publish 會拒絕（exit 6）。
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

## Maintain（每日）

每天 03:17 由 launchd 自動跑一次 `/maintain-verification-skill`（Michael 2026-09-28 核准的 V4）：

- 在專用 clone `~/kidsai-maintain/project-kid-ai` 和專用模擬器 `KidsAI-Maintain` 上跑，不碰平常工作的 checkout 與 `KidsAI-Verify`。
- 結果只有三種：
  - **clean**：只寫 log。
  - **changed**：wrapper 套用 agent 的提案並開一個 **draft** PR，只改 `SKILL.md` 與 `references/`；已有未合併的 maintain PR 時不開新的。
  - **blocked**：寫 log，並跳 macOS 通知；連續 3 天另外標出。
- **agent 只提案，不改檔、不 commit**：Claude Code 在無頭模式下不准改 `.claude/` 底下的檔案（allow 規則與 `acceptEdits` 都放不過，2026-09-29 實測）。
  - agent 把改好的完整檔案寫到 `.verify/maintain-proposed/<相對於本目錄的路徑>`（例如 `.verify/maintain-proposed/references/features/unit-flow.md`），run notes 寫到 `.verify/maintain-notes.md`。權限見 `maintain/maintain-settings.json`：只能寫 `.verify/`、git 只能 `status`、不能跑 python。
  - 只能提案 `SKILL.md` 與 `references/**/*.md`；harness（`control-kidsai`、`lib/`、`maintain/`、`tests/`）的問題寫進 run notes，另走 `/agent-plan`。不然 agent 可以改掉防護。
  - `control-kidsai` 只能用列出的子命令。從專用 clone 執行時，不看環境變數，一律拒絕 `evidence publish`（含 dry-run）、`maintain`（wrapper 的 `run` 除外）和 `KidsAI-Maintain` 以外的模擬器；agent 的環境（`KIDSAI_MAINTAIN_AGENT=1`）連 `maintain run` 也拒絕。也不能 push、不能用 `gh`。
- **wrapper 的硬性防護**（`lib/kidsai_maintain.py`，不依賴模型守規矩）：
  - agent 不准動 git：有任何 commit、index 或工作樹改動（`.verify/` 除外）就是越界。
  - 提案只准 `SKILL.md` 與 `references/**/*.md`、不准 symlink、要是 UTF-8 純文字（≤200 KB）；通過才由 wrapper 套用，並用 repo 設好的 git 身分 commit。
  - wrapper 的 commit 再檢查一次範圍與二進位；新增內容與 commit 訊息、作者，不得有本機路徑、使用者名稱、裝置 ID 或金鑰樣式。
  - run notes 必須和提案一致（說 clean 卻有提案、說 changed 卻沒有或內容沒變，都算 blocked）。
  - 分支 push 了但開 PR 失敗，也算 blocked（要手動處理）。
  - 任一項不合就 blocked，並丟掉這次的分支。
- **不發布證據**：證據只留在專用 clone 的 `.verify/`。
- **log**：`~/Library/Logs/kidsai-maintain/<date>.log`（保留 30 天），Claude Code 的輸出在 `<date>-<時間>.claude.log`（每次一個檔）。

```bash
$C maintain install --dry-run    # 印出 plist 內容與路徑，不寫任何檔
$C maintain install              # 裝 LaunchAgent（記下 claude、gh、git、python3 的絕對路徑）
$C maintain status               # 是否已安裝、最近 5 次結果、連續 blocked 天數
$C maintain uninstall            # 移除 LaunchAgent 與 bootstrap；專用 clone、log 保留
```

- 手動跑一次：`launchctl kickstart gui/$(id -u)/com.godmosword.kidsai.maintain-verify`。
- 驗收時先用 `maintain install --ref <分支> --no-push`，只留本機分支與 log。
- Node 升級後 `claude` 的路徑會變，每日維護會 blocked 並提示重跑 `maintain install`。

## Helpers

- `control-kidsai`（本目錄，可執行，Python 3 標準函式庫；程式在 `lib/kidsai_core.py`、`kidsai_evidence.py`、`kidsai_flows.py`）：`$C --help`。子命令：`doctor`、`sim ensure|boot|shutdown|erase|statusbar|text-size`、`build [--for-testing]`、`install`、`launch`、`terminate`、`run new`、`screenshot`、`record start|stop`、`record --flow`、`drive --flow`、`snapshot`、`cleanup`、`evidence frames|review|md|publish`、`maintain install|uninstall|status|run`（`lib/kidsai_maintain.py`）。破壞性命令有 `--dry-run`；`sim erase` 一定要 `--yes`。
- 流程測試：`app/KidsAIUITests/`（`FlowSupport.swift` 的 `Flow`／`Frames`／`Handshake`、`Flows.swift` 的流程與 `SnapshotTree`）。新增流程：在 `Flows.swift` 加類別，再加進 `lib/kidsai_flows.py` 的 `FLOWS`。
- 測試：`python3 -m unittest discover .claude/skills/verify-kidsai/tests`（不需要 Xcode、模擬器或網路；`test_maintain.py` 會用本機暫存的 git repo）。
- 需要：Xcode、XcodeGen、ffmpeg／ffprobe（`brew install ffmpeg`，產生 GIF 與驗證錄影）、已登入的 `gh`（發布證據）。
- 功能地圖：[`references/features/`](references/features/)（每個功能一個檔，四個 H2：`Sub-features`、`How to get to it (user POV)`、`Driving it with control-kidsai`、`Gotchas`）。這裡刻意用 `references/features/`，不是 generator 預設的 `features/`，和 pstack 範例 repo 一致。
- 設計對照：[`references/design-map.md`](references/design-map.md)（功能 → Notion mid-fi 屏號與版本 → 目前的差異；參考圖在 repo 的 `design/midfi/`）。
- 維護：用 `/maintain-verification-skill`（來源 pstack `cursor/plugins@ecc249f`，放在 `~/.claude/skills/`）保持地圖和 App 一致。只能改這個目錄；最多開一個 PR；不得自己合併。
