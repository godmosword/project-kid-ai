# 內容格式 v1：單元 1–4 機制對照表

來源：Notion「四單元關卡腳本大綱 v1」、「單元1 完整 JSON＋沙盒契約 v1」。格式定義見 [content/schema/](../content/schema/)。

本表確認大綱裡每一種玩法都能用 v1 的 beat 類型表達。之後新增玩法時，先補這張表，再改 schema。

## 單元流程

每個單元依序為：

1. `intro`
2. 3–5 個小關（`choice`／`drag`／`asr_repeat`／`sandbox`；`sandbox_ritual` 不計入）
3. `story`
4. `review`
5. `sticker`

家長卡是單元頂層的 `parent_card`，全檔只有一份；App 在貼紙之後、共玩模式下顯示。

故事放在 `stories` 陣列（v1 限定一個），由 `story` beat 以 `story_ref` 引用；計畫草稿寫的頂層 `story` 已改成這個結構。

沒有標準答案的關卡（`scoring: open`）選一次就揭曉。沙盒主題只有一張卡時，App 直接選好，孩子不必再點一次。

## 機制 → beat 類型

| 單元 | 大綱中的玩法 | beat 類型／mode | 關鍵欄位 |
|---|---|---|---|
| 1 | 聽一聽・誰在說話（三段聲音選一） | `choice`（`scoring: graded`） | `options[].sound`、`sound_script`、`correct_option_ids` |
| 1 | 猜箱子（先猜再揭曉） | `choice`（`scoring: open`） | `stage`（只露一角的箱子）、`feedback.reveal` |
| 1 | 跟讀金句 | `asr_repeat` | `target_line`、`accept`、三條退路 |
| 1 | 戴上猜猜帽 | `sandbox_ritual` | `lines`（不可跳過） |
| 1 | 沙盒・三種猜測 | `sandbox` | `sandbox_ref`、`reaction_prompt`、`reactions`（好像對／好像錯／不知道）、`closing_line` |
| 2 | 糊糊句子 vs 魔法句子 | `choice`（`graded`） | `correct_option_ids` |
| 2 | 拖曳組句 | `drag`（`mode: order`） | `correct_order` |
| 2 | 跟讀魔法句 | `asr_repeat` | `target_line` |
| 2 | 沙盒・同一件事兩種提示（孩子教 AI） | `sandbox` | slot 的兩個 `choices`（糊／清楚）；猜測可附 `image`（預審示意卡） |
| 3 | 真假照片對對看 | `choice`（`graded`） | `options[].image`、`a11y_label` |
| 3 | 聽句子・抓怪怪的 | `choice`（`graded`） | `options[].label` |
| 3 | 把錯誤丟進垃圾桶 | `drag`（`mode: group`） | `groups`（留下／垃圾桶）、`assignments` |
| 3 | 跟讀 | `asr_repeat` | `target_line` |
| 3 | 沙盒・AI 先猜你來查 | `sandbox`（`scoring: graded`） | 猜測的 `truth`（`right`／`wrong`）、`uncertainty_mark: sure` |
| 4 | 碎片是什麼 | `choice`（`graded`） | `correct_option_ids` |
| 4 | 拖曳排序（可多解） | `drag`（`mode: order`） | `correct_order`、`alt_orders` |
| 4 | 跟讀結局句（依所選結局） | `asr_repeat` | `target_lines_by_option`（引用前一個 beat 的選項） |
| 4 | 沙盒・三碎片 | `sandbox` | 同一 slot×choice 放 3 筆猜測；`max_guess_chars: 12` |

## 故事分歧

| 單元 | 分歧 | 表達方式 |
|---|---|---|
| 1 | 猜猜帽猜錯→再猜一次／自己找（各有一句不同的回應）；猜猜帽不確定→一起找／給提示（選圖） | `nodes[].choices[].next`，最後會合到結局節點（`end: true`）；猜猜帽說話的節點 `speaker: ai_persona` |
| 2 | 糊提示路線／清楚提示路線 | 同上 |
| 3 | 相信／檢查一下（相信路線仍導回檢查） | 同上，相信路線的 `next` 指向檢查節點 |
| 4 | 讓它全寫／我來選結局 | 同上 |

分歧選項沒有對錯，所以故事節點不帶 `feedback.not_yet`。驗證規則：不能繞回原處、不能有走不到的節點、每條路徑都以 `end: true` 結束，而且每條路徑最多經過 3 個分歧。

## 大綱有、但 v1 刻意不做的

| 項目 | 原因 |
|---|---|
| 事件 `emit` | 事件格式另案定案，v1 不允許出現 |
| live 沙盒、kill switch | 需要網路，白名單目前為無 |
| 單元 3「真模型真實錯誤入庫」（S4） | 屬於 pipeline 生成流程，另案 |
| 年齡差異內容 | 先定義 `age_overrides` 欄位，首發不填 |

## 單元 1 轉換紀錄（Notion 完整 JSON content_version 1.1 → v1）

來源：Notion「單元1 完整 JSON＋沙盒契約 v1」頁的「完整 JSON 原文」。轉換後經三審，下列修改都已由 Michael 核准（2026-09-25）。

**角色：** 原稿故事裡猜錯、說「我不確定」、說「我只是會猜的幫手」的是點點，和「點點不是 AI」（S7）衝突。v1 改由猜猜帽（AI）在故事裡猜與說話，點點只旁白，開場加一句「我是點點，不是 AI 喔。」

**改寫的文字**

| 位置 | 原文 | v1 |
|---|---|---|
| 標題 | 單元1｜認識：AI 是會猜的幫手 | 認識島：AI 是會猜的幫手 |
| 第 1 關題目 | 聽一聽，誰常常在猜？ | 聽一聽，誰說「我猜」？（只有 AI 那段聲音說「我猜」） |
| 第 1 關選項 | 媽媽 | 家人 |
| 猜箱子題目 | 箱子只露出一小角，你猜裡面是什麼？ | 你猜箱子裡是什麼？（露一角的說明移到場景圖替代文字） |
| 猜箱子揭曉 | 你也會猜。AI 也會猜——有時猜對、有時猜錯。 | 你和 AI 都會猜，有時對有時錯。 |
| 跟讀提示 | （失敗後）沒關係，再試一次。 | 跟我一起說：AI 會猜。 |
| 拒絕麥克風、裝置不支援 | 沒關係，按一下綠色按鈕，我們一起說。 | 按一下嘴巴按鈕，我們一起說。 |
| 辨識失敗 2 次 | 沒關係，按一下綠色按鈕，我們一起說。 | 沒關係，按一下，聽我念一次。 |
| 儀式 | 戴上猜猜帽，我們請 AI 來猜一猜！ | 猜猜帽是 AI，請它猜一猜！ |
| 沙盒題目、主題 | 選一個主題，請 AI 猜一猜／天氣符號、早餐圖、動物剪影 | 選一張卡，請猜猜帽猜！／天氣、早餐、動物影子 |
| 沙盒揭曉 | 不管猜得怎樣，記住：AI 會猜。 | AI 會猜，有時猜對，有時猜錯。 |
| 回顧 1 選項 | 什麼都知道的神仙 | 什麼都知道 |
| 家長卡 | 問孩子：今天 AI 猜對了幾次？猜錯有沒有關係？ | 問孩子：今天猜猜帽猜了什麼？你覺得它猜得對嗎？ |
| 故事 | 點點猜：在沙發下！……咦，沒有。／點點說：我不確定。 | 由猜猜帽說：我猜在沙發下！咦，沒有。／我不確定。 |

**新寫的文字**（原稿沒有）：開場自我介紹、所有 `feedback.reveal`、三段聲音的台詞（`sound_script`）、圖片與聲音的替代文字、故事分歧 A 的兩句不同回應、提示圖節點說明。

**沒有轉入 v1 的內容**

| 原稿內容 | 原因 |
|---|---|
| 「大聲說貼紙」彩蛋（跟讀成功才給） | 貼紙不綁表現；拒絕麥克風的孩子會拿不到 |
| 第二句跟讀「會猜、也會錯。」 | v1 一個跟讀 beat 只有一句；「會錯」改在猜箱子與沙盒的揭曉句教 |
| 各 beat 的 `emit`、`metrics_hooks`、`validation_telemetry` | 事件格式另案（D6） |
| `parent_gate`、`compliance_locked`、`age_profile` | 屬於 App 設定或合規文件；`age_profile` 之後用 `age_overrides` 表達 |
| 與畫面文字不同的 `tts` 文字 | 旁白念畫面文字（`vo`），不另存一份 |
| 拒麥預告提示、故事分歧後的回饋句、沙盒等待文案 | v1 沒有對應欄位；需要時再加選填欄位 |
| 猜箱子的隨機變體（貓／車／香蕉輪流藏） | 先固定為貓咪 |
| 故事開頭的假分歧、貼紙頁的「回地圖／下一島」 | 改成單純往下；導覽由 App 處理 |

**行為差異：** 有答案的關卡最多試 2 次後揭曉並繼續（原稿可無限重試）；沒有答案的關卡選一次就揭曉。沙盒每個主題一張卡，`structured_choice` 是該卡的 id（原稿為 null）。

**AI 猜測：** 3 筆猜測已由 Michael 核准（2026-09-25），核准碼寫在 `unit_1_recognize.guesses.json` 的 `approved_hash`。
