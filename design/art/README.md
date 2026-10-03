# 美術風格預覽

**2026-10-03 Michael 選定 A（扁平圓角）。** 角色表情照 [art-spec](../../docs/art/art-spec.md) 第 3 節；生圖工具的商用條款還沒確認，所以這些圖仍是 draft。B、C 只留作紀錄。

2026-10-03 依 [生圖規格](../../docs/art/generation-prompts.md)用內建 image_gen 產生三個方向，每個方向各有地圖、兩個角色和天氣圖卡，共 9 張 PNG。

- A：扁平圓角。
- B：繪本水彩。
- C：軟黏土 3D。

打開 [風格樣張](../style-tile/index.html) 第 6 節即可比較。完整 prompts、日期、尺寸和 SHA-256 記在 [generation-log.json](generation-log.json)。所有圖片都是 draft，尚未由 Michael 選定或核准，不打包進 App。

天氣圖卡是比較風格用的晴天樣本，不是正式單元 1 的 img_slot_weather；正式圖需要保留不完整的天氣線索。設定圖、表情、透明背景、教學線索驗收和商用授權確認仍待做；定稿後才登錄 docs/art/provenance.md。

## D1 角色設定稿（draft，2026-10-03）

依 [生圖 prompt](../../docs/art/generation-prompts.md) 第 2 步，以 `style-a/characters.png` 為參考圖生成；完整 prompt 與 SHA-256 記在 generation-log.json。

| 檔案 | 內容 |
|---|---|
| `d1/dian-turnaround.png` | 點點三視圖（正、側、背） |
| `d1/dian-expressions.png` | 點點表情 4 種：開心、好奇、指引、鼓勵 |
| `d1/hat-turnaround.png` | 猜猜帽三視圖（正、側、背），小牌子空白 |
| `d1/hat-expressions.png` | 猜猜帽表情 5 種：猜、不確定、開心、道謝、被抓到說錯 |

- 都是透明背景（alpha 輪廓乾淨；透明區殘留的顏色在 App 合成時看不到）。
- 縮成 App 大小（28pt、52pt、140pt）檢查過，兩個角色一眼分得出來。
- **2026-10-03 Michael 核准角色造型（D1）。** 商用條款還沒確認，所以還不記入 provenance；P2 接入 App 的 PR 在條款確認前不合併。

## D3 單元 1 內容圖（draft，2026-10-03）

依 [教學線索與驗收](../../docs/art/asset-cues.md) 寫 prompt，用 Codex 內建 image_gen 生成 13 張（`img_card_ai` 由 P2 的猜猜帽渲染，不另外生）；完整 prompt 與 SHA-256 記在 generation-log.json。

- 早餐、動物影子、貼紙各重生一次：早餐第一版只剩角落一小片、動物影子太像狐狸也沒模糊、貼紙的帽子不是猜猜帽。
- 圖卡多是透明背景；箱子（4:3 場景）、早餐（放大照片的一角）、動物影子（模糊）有底色。
- 13 張並排的總覽：[d3-overview.png](d3-overview.png)。
- 還是 draft：等 Michael 逐張核准（asset-cues 標 ✅ 的要特別看）與商用條款確認，才記入 provenance、接進 App（P4）。
