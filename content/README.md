# content

`content/` 底下的 JSON 是課程內容的唯一真實版本（single source of truth）。App 與 `pipeline/` 都以這裡為準，不在別處另存一份。

- `schema/` — JSON Schema（`common`、`unit`、`sandbox`）
- `units/` — 各單元的課程 JSON 與沙盒猜測庫

各單元玩法對應哪種 beat 類型，見 [docs/content-schema-v1-mapping.md](../docs/content-schema-v1-mapping.md)。

## 驗證

```
python3 -m venv pipeline/.venv
pipeline/.venv/bin/pip install -r pipeline/requirements.txt
pipeline/.venv/bin/python pipeline/validate_content.py              # 驗證 content/ 下所有內容檔（schema/ 除外）
pipeline/.venv/bin/python pipeline/validate_content.py --fixtures   # 跑正反例
```

`--allow-unreviewed` 只供草稿階段暫時放行未核准的猜測，CI 與合併前的驗證不得使用。

改了 schema 或驗證規則，要跑 `pipeline/.venv/bin/python pipeline/fixtures/make_fixtures.py` 重新產生正反例，再跑 `--fixtures`。

## 文字規則

- 文字物件：`{ id, audience, text: {"zh-Hant": ...}, vo, vo_status }`。v1 只允許 `zh-Hant`（加語系時一併訂該語系的上限，minor 版號）。孩子看的文字必須有旁白音檔 key `vo`，還沒錄音時 `vo_status` 用 `tts_placeholder`。
- 有聲音的選項要寫出 `sound_script`（聲音裡說的話），方便審稿與 VoiceOver。
- 資產 key（圖片、聲音、旁白）只能是 `img_card_ai`、`vo/u1/title` 這種站內 key：小寫英數與底線，用 `/` 分層，不得有 `.`。
- 長度上限以 NFC 正規化後的 Unicode 字元數計（標點、空白都算）：

| 用途 | 上限 |
|---|---|
| 題幹 | 16 字 |
| 選項、貼紙名稱 | 6 字 |
| 旁白、故事、回饋（每句） | 20 字 |
| AI 猜測 | 24 字（沙盒可用 `max_guess_chars` 再收緊） |
| 家長文字 | 120 字 |

- 不得出現：錯了、不對、答錯、失敗、不正確、笨（繁簡都擋；比對前會先去掉零寬等看不見的字元）。
- 不得出現網址、網域、`javascript:`、`file:`、data URI、email、電話號碼；給人看的文字不得有半形 `:`、`@`（請用全形「：」）。

## AI 猜測的核准

每筆猜測由 Michael 看過文字後核准：把驗證訊息裡的核准碼（`guess_text` 的 SHA-256 前 12 碼）寫進該筆的 `approved_hash`。文字只要改一個字，核准碼就對不上，必須重新核准。

## 版號規則（`schema_version`）

- 新增**選填**欄位：minor（1.0.0 → 1.1.0）
- 修正說明、不影響資料：patch（1.0.0 → 1.0.1）
- 新增必填欄位、改名、刪除、收緊限制：major，而且所有既有內容要一起遷移

## 規則代號

| 代號 | 意思 |
|---|---|
| R-JSON | 不是合法 JSON |
| R-DUP-KEY | 同一物件裡有重複的鍵 |
| R-KIND | `kind` 不是 `unit` 或 `guess_bank` |
| R-CLOSED | 出現沒有定義的欄位（格式是封閉的） |
| R-REQUIRED | 缺少必填欄位（含缺 `zh-Hant`、有圖卻沒有 `a11y_label`） |
| R-LEN | 文字超過長度上限 |
| R-COUNT | 項目數量超出範圍（例如選項超過 3 個） |
| R-ENUM | 值不在允許的清單內 |
| R-PATTERN | id 或 key 的格式不對 |
| R-TYPE、R-RANGE、R-SHAPE | 型別、數值範圍、結構不符 |
| R-UNSAFE | 猜測的 `safe` 不是 `true` |
| R-ROLE | 旁白（點點）與 AI 角色（猜猜帽）的 id 相同 |
| R-NFC | 字串沒有做 NFC 正規化 |
| R-STRING-LEAK | 字串含網址、網域、data URI、email、電話，或文字裡有半形 `:`、`@` |
| R-BANNED-WORD | 含禁用詞 |
| R-DUP-ID | id 重複 |
| R-REF | 引用了不存在的 id、答案沒涵蓋所有項目，或年齡覆寫拿掉了正確答案 |
| R-FLOW | 單元節奏不符（intro → 3–5 小關 → story → review → sticker；沙盒前要有儀式） |
| R-DURATION | 各 beat 的 `est_seconds` 合計超過 `max_seconds` |
| R-STORY-CYCLE、R-STORY-UNREACHABLE、R-STORY-DEPTH | 故事繞回原處、有走不到的節點、分歧超過 3 層 |
| R-SANDBOX-COVERAGE | 沙盒有選項沒有猜測，或沙盒沒有猜測庫 |
| R-SANDBOX-CHOICE | 猜測對應到不存在的 slot／選項 |
| R-SANDBOX-TRUTH | 有對錯的沙盒，猜測缺 `truth`；或沒有對錯的沙盒，猜測卻有 `truth` |
| R-UNCERTAINTY | `uncertainty_mark` 不符沙盒要求 |
| R-GUESS-LEN | 猜測超過沙盒的 `max_guess_chars` |
| R-UNREVIEWED | 猜測沒有 `approved_hash`，或文字改過、核准碼對不上 |
| R-BANK-ORPHAN | 猜測庫找不到對應的單元或沙盒 |

同一處有更具體的錯誤時，驗證會略過因此連帶產生的 R-CLOSED；修掉具體錯誤後再跑一次即可。
