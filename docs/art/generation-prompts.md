# 生圖 prompt（Codex／Grok）

規格見 [art-spec.md](art-spec.md)。英文 prompt 通常比較穩定，所以 prompt 用英文，說明用中文。每次生圖都把「風格區塊＋限制區塊＋題目」一起貼上，並把結果記到 [provenance.md](provenance.md)。

## 第 1 步：風格方向（3 選 1）

每個方向都生同一組 3 張測試圖（地圖、兩個角色、一張圖卡），放在一起給 Michael 比較。

### 風格區塊

**方向 A｜扁平圓角（像兒童教育 App）**
```
Style: flat vector illustration for a children's learning app, soft rounded shapes, thick friendly outlines, bright but gentle colors, simple shading, clean shapes, playful and calm, no gradients noise.
```

**方向 B｜繪本水彩**
```
Style: children's picture-book illustration, soft watercolor and colored-pencil texture, warm cream paper background, gentle hand-drawn lines, cozy and calm mood.
```

**方向 C｜軟黏土 3D**
```
Style: soft clay 3D render for young children, rounded chunky forms, matte pastel materials, soft studio lighting, cute and friendly, gentle shadows.
```

### 限制區塊（每次都要附上）

```
Constraints: for ages 5-8, friendly and not scary, no text or letters anywhere in the image, no real people, no children, no brand logos, no existing cartoon characters, no religious symbols, no flags, no weapons, no injuries. Color palette: cream #FFF8EC background, yellow #F5B82E, green #3BAA6E, orange #F08A3C, purple #A98BF0, coral #F2877A, blue #1E6FC2.
```

### 測試圖題目

1. **地圖**
```
A vertical treasure-map style island world seen from above, four small round islands connected by a winding path: a yellow island with a question-mark shaped hill and a box, a green island with a small bridge, an orange island with a little detective house, a purple island with a small stage with curtains. Clouds, gentle sea, lots of empty space at the bottom for buttons. Portrait 3:4.
```
2. **兩個角色**
```
Two characters side by side on a plain background: (1) "DianDian", a small round friendly robot buddy in coral color with a heart-shaped light on its chest, big kind eyes, short arms; (2) "Guess Hat", a talking magician's top hat in blue with a pointed tip, a friendly face on the hat band, and a small badge on the hat. The two must look clearly different in shape and color. Full body, front view.
```
3. **一張圖卡**
```
A single square card illustration of a sunny weather symbol: a smiling sun with a few small clouds, centered, plenty of margin, plain light background. Square 1:1.
```

選定一個方向後，之後所有圖都只用那個風格區塊。

## 第 2 步：角色設定圖

選好風格後，把選中的角色圖當參考圖一起上傳，逐張生：

```
Character turnaround sheet of [角色描述，照上面第 2 題], front view, side view, back view, same character, consistent proportions, transparent background.
```

```
Expression sheet of [角色描述], six expressions: happy, curious, pointing to guide, encouraging, thinking with eyes looking up and a small question mark above the hat tip (Guess Hat only), shy smile when caught being wrong (Guess Hat only). Transparent background, same style.
```

注意：猜猜帽上的小牌子，最後由 App 疊上「AI」字樣；生圖時只要一塊空白的小牌子。

## 第 3 步以後：素材圖

- 題目依[素材清單](../content-schema-v1-mapping.md#素材清單給路線圖步驟-7)逐張寫，句型：「[風格區塊] + [限制區塊] + 這張圖要畫什麼 + 比例」。
- 要表達教學重點的圖，把重點寫進題目，例如：
  - `img_u3_card_dog`：`A friendly puppy standing sideways so all four legs are clearly visible and easy to count. Square 1:1.`
  - `img_box_peek_cat_ear`：`A closed cardboard box with only one pointed furry ear peeking out of a small gap at the top, the rest hidden. 4:3.`
  - `img_u3_apple_glasses`：`A shiny apple wearing small round glasses, playful and obviously odd, same framing as the plain apple card. Square 1:1.`
- 同一組比較用的圖（例如 `img_u3_apple_plain` 和 `img_u3_apple_glasses`），要用同樣的構圖和光線，只差題目要比較的那一點。
