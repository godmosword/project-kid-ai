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

## 單元 2–4 取捨紀錄（依大綱新寫，Michael 核准 2026-09-25）

計畫與兩審（工程、設計）的決定：D11–D18。所有孩子文字與 14 筆 AI 猜測都由 Michael 逐句核准。

| 單元 | 與大綱不同之處 | 原因 |
|---|---|---|
| 全部 | 故事裡猜、犯錯、說話的是猜猜帽；點點只旁白；開場都有「我是點點，不是 AI 喔。」 | D11，避免孩子把點點當 AI |
| 2 | 金句改成「說清楚，AI 才猜得準。」 | D15，不把 AI 說成會理解，也接上單元 1「AI 會猜」 |
| 2 | 第 1 關選項改成「小熊說／小兔說」，句子放在聲音裡；兩句都有「請」 | 句子超過 6 字；讓兩句只差在具體程度 |
| 2 | 拖曳組句改成把「拿什麼」「放哪裡」的圖卡拖進空格（match） | D17，排詞序練的是文法 |
| 2 | 故事的模糊指令改成「拿那個來」 | 「種菜！」拿來玩具車不合理 |
| 2 | 「魔法句子」一律改說「說清楚」；紅積木加上「小」、杯子用星星圖案 | 不讓孩子以為有咒語；不只靠顏色辨識 |
| 3 | 5 關改 4 關，「抓怪怪句子」併進拖曳分組「留下／要改正」，不用垃圾桶 | D16，時間上限；避免和回顧題「生氣丟掉」衝突 |
| 3 | 錯誤猜測為人工撰寫：看圖就查得出來、不碰安全事實、對錯都有 | D12；步驟 8 改用真模型錯誤時照同樣條件並重新核准 |
| 3 | 不逐筆念出正確答案，改用通用查證揭曉句 | D14，維持 v1 格式；試玩後再評估 |
| 3 | 故事結尾孩子告訴猜猜帽，猜猜帽道謝；「相信」路線有自己的回應 | 回顧題考「告訴它」；抓錯是幫忙，不是罵 AI |
| 4 | 「碎片」改「點子」；AI 的 3 個點子就是 3 個結局方向；「再試一次」改「不放棄」 | D18，讓「我來決定」真的連到 AI 的點子 |
| 4 | 「讓它全寫」路線不懲罰：猜猜帽寫完問「這樣好嗎？你來決定。」 | 不把用 AI 講成壞事 |
| 4 | 排序圖改用「出門、下雨、撐傘」，接受兩種合理順序 | 大綱要求可多解 |

**已知限制**
- 單元 2 第 2 關：格式規定每張卡都要放進空格，無法放干擾卡，難度偏低。
- 單元 4 沙盒：每個世界的 3 個點子依序對應「救朋友／分享食物／不放棄」，格式沒有欄位標明對應，App 要照順序顯示。

## 素材清單（給路線圖步驟 7）

所有旁白目前都是 `tts_placeholder`，共 301 段（key 為 `vo/<單元>/…`，由文字 id 產生）。「需核准」欄打勾的圖會影響教學判斷，製作後要 Michael 看過。

| 單元 | key | 類型 | 用在 | 需核准 |
|---|---|---|---|---|
| 1 | `img_box_peek_cat_ear` | 圖片 | u1_gate2_box | ✅ |
| 1 | `img_box_reveal_banana` | 圖片 | u1_gate2_box |  |
| 1 | `img_box_reveal_car` | 圖片 | u1_gate2_box |  |
| 1 | `img_box_reveal_cat` | 圖片 | u1_gate2_box |  |
| 1 | `img_card_ai` | 圖片 | u1_gate1_listen |  |
| 1 | `img_card_family` | 圖片 | u1_gate1_listen |  |
| 1 | `img_card_toy` | 圖片 | u1_gate1_listen |  |
| 1 | `img_hint_bag` | 圖片 | u1_story_hint |  |
| 1 | `img_hint_bath` | 圖片 | u1_story_hint |  |
| 1 | `img_hint_bed` | 圖片 | u1_story_hint |  |
| 1 | `img_slot_animal` | 圖片 | u1_guess_01 |  |
| 1 | `img_slot_breakfast` | 圖片 | u1_guess_01 |  |
| 1 | `img_slot_weather` | 圖片 | u1_guess_01 |  |
| 1 | `img_sticker_can_guess` | 圖片 | u1_sticker |  |
| 1 | `sfx_voice_ai_short` | 聲音 | u1_gate1_listen |  |
| 1 | `sfx_voice_family_short` | 聲音 | u1_gate1_listen |  |
| 1 | `sfx_voice_toy_short` | 聲音 | u1_gate1_listen |  |
| 2 | `img_sticker_say_clear` | 圖片 | u2_sticker |  |
| 2 | `img_u2_bear` | 圖片 | u2_gate1_clear |  |
| 2 | `img_u2_cup_star` | 圖片 | u2_gate2_blanks |  |
| 2 | `img_u2_guess_cat_clear` | 圖片 | 猜測庫 | ✅ |
| 2 | `img_u2_guess_cat_vague` | 圖片 | 猜測庫 | ✅ |
| 2 | `img_u2_place_table` | 圖片 | u2_gate2_blanks |  |
| 2 | `img_u2_rabbit` | 圖片 | u2_gate1_clear |  |
| 2 | `img_u2_wish_cat` | 圖片 | u2_draw_01 | ✅ |
| 2 | `sfx_u2_bear_vague` | 聲音 | u2_gate1_clear |  |
| 2 | `sfx_u2_rabbit_clear` | 聲音 | u2_gate1_clear |  |
| 3 | `img_sticker_detective` | 圖片 | u3_sticker |  |
| 3 | `img_u3_apple_glasses` | 圖片 | u3_gate1_odd | ✅ |
| 3 | `img_u3_apple_plain` | 圖片 | u3_gate1_odd | ✅ |
| 3 | `img_u3_card_car` | 圖片 | u3_check_01 | ✅ |
| 3 | `img_u3_card_dog` | 圖片 | u3_check_01 | ✅ |
| 3 | `img_u3_card_night` | 圖片 | u3_check_01 | ✅ |
| 3 | `sfx_u3_fish` | 聲音 | u3_gate2_sort |  |
| 3 | `sfx_u3_ice` | 聲音 | u3_gate2_sort |  |
| 3 | `sfx_u3_moon` | 聲音 | u3_gate2_sort |  |
| 3 | `sfx_u3_sun` | 聲音 | u3_gate2_sort |  |
| 4 | `img_sticker_director` | 圖片 | u4_sticker |  |
| 4 | `img_u4_car_go_out` | 圖片 | u4_gate2_order |  |
| 4 | `img_u4_car_umbrella` | 圖片 | u4_gate2_order |  |
| 4 | `img_u4_rain` | 圖片 | u4_gate2_order |  |
| 4 | `img_u4_world_animals` | 圖片 | u4_ideas_01 |  |
| 4 | `img_u4_world_cars` | 圖片 | u4_ideas_01 |  |
| 4 | `img_u4_world_picnic` | 圖片 | u4_ideas_01 |  |
