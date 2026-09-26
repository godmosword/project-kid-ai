import SwiftUI

/// 素材的暫代圖：依內容的素材 key 查表，不從 key 猜、不顯示 key。
/// 需要教學判斷的圖刻意保留模糊（例如沙盒卡不和猜測一模一樣）。美術定稿後改讀 Asset Catalog。
enum PlaceholderArt {
    enum Art: Equatable {
        case emoji(String)
        case symbol(String, color: Color, scale: CGFloat = 1)
        case silhouette(String)
        /// 糊掉的剪影：看得出「有東西」，看不出是哪一種（沙盒動物卡）。
        case blurredSilhouette(String)
        /// 只露出一角（沙盒早餐卡）。
        case corner(String)
        case guessHat
        case boxWithEar
    }

    static let table: [String: Art] = [
        // 單元 1
        "img_card_family": .emoji("👪"), "img_card_toy": .emoji("🧸"), "img_card_ai": .guessHat,
        "img_box_peek_cat_ear": .boxWithEar,
        "img_box_reveal_cat": .emoji("🐱"), "img_box_reveal_car": .emoji("🚗"), "img_box_reveal_banana": .emoji("🍌"),
        "img_slot_weather": .emoji("⛅"), "img_slot_breakfast": .corner("🍽️"), "img_slot_animal": .blurredSilhouette("hare.fill"),
        "img_hint_bed": .emoji("🛏️"), "img_hint_bag": .emoji("🎒"), "img_hint_bath": .emoji("🛁"),
        "img_sticker_can_guess": .emoji("⭐"),
        // 單元 2
        "img_u2_bear": .emoji("🐻"), "img_u2_rabbit": .emoji("🐰"), "img_u2_cup_star": .emoji("☕️"),
        "img_u2_place_table": .symbol("table.furniture", color: Color(hex: 0x8B5E3C)),
        "img_u2_wish_cat": .symbol("cat.fill", color: Color(hex: 0xF5B82E), scale: 0.7),
        "img_u2_guess_cat_clear": .symbol("cat.fill", color: Color(hex: 0xF5B82E), scale: 0.7),
        "img_u2_guess_cat_vague": .symbol("cat.fill", color: Color(hex: 0xDADADA), scale: 1.1),
        "img_sticker_say_clear": .emoji("💬"),
        // 單元 3
        "img_u3_apple_plain": .emoji("🍎"), "img_u3_apple_glasses": .emoji("🍎👓"),
        "img_u3_card_dog": .symbol("dog.fill", color: Color(hex: 0x8B5E3C), scale: 1.2),
        "img_u3_card_night": .emoji("🌙"), "img_u3_card_car": .emoji("🚗"), "img_sticker_detective": .emoji("🔍"),
        // 單元 4
        "img_u4_car_go_out": .emoji("🚗🏠"), "img_u4_rain": .emoji("🌧️"), "img_u4_car_umbrella": .emoji("🚗☂️"),
        "img_u4_world_cars": .emoji("🚗"), "img_u4_world_animals": .emoji("🐾"), "img_u4_world_picnic": .emoji("🚀"),
        "img_sticker_director": .emoji("🎬"),
    ]

    static func has(_ key: String) -> Bool { table[key] != nil }
}

/// 顯示一個素材；找不到就是中性色塊（測試會擋下缺少的 key）。
/// 有 `label` 時是一個無障礙元素；沒有就交給外層（例如選項卡）的標籤。
struct ArtView: View {
    let key: String?
    var size: CGFloat = 72
    var label: String?

    var body: some View {
        if let label {
            art.accessibilityElement().accessibilityLabel(label).accessibilityAddTraits(.isImage)
        } else {
            art.accessibilityHidden(true)
        }
    }

    private var art: some View {
        Group {
            switch key.flatMap({ PlaceholderArt.table[$0] }) {
            case .emoji(let text)?:
                Text(text).font(.system(size: size))
            case .symbol(let name, let color, let scale)?:
                Image(systemName: name).font(.system(size: size * scale)).foregroundStyle(color)
            case .silhouette(let name)?:
                Image(systemName: name).font(.system(size: size)).foregroundStyle(Theme.ink)
            case .blurredSilhouette(let name)?:
                Image(systemName: name).font(.system(size: size)).foregroundStyle(Theme.ink)
                    .blur(radius: size * 0.16)
                    .frame(width: size * 1.3, height: size * 1.3)
            case .corner(let text)?:
                Text(text).font(.system(size: size * 1.8))
                    .offset(x: size * 0.6, y: size * 0.6)
                    .frame(width: size, height: size)
                    .background(Theme.neutralRetry)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            case .guessHat?:
                GuessHat(size: size)
            case .boxWithEar?:
                BoxWithEar(size: size * 1.6)
            case nil:
                RoundedRectangle(cornerRadius: 12).fill(Theme.neutralRetry).frame(width: size, height: size)
            }
        }
    }
}

/// 猜箱子：箱子只露出兩只耳朵（不直接畫出貓）。
private struct BoxWithEar: View {
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .top) {
            HStack(spacing: size * 0.14) {
                ForEach(0..<2, id: \.self) { _ in
                    Triangle().fill(Color(hex: 0x8E8E8E)).frame(width: size * 0.2, height: size * 0.24)
                }
            }
            .offset(y: -size * 0.16)
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: 0xC8964B))
                .frame(width: size, height: size * 0.7)
                .overlay(Rectangle().fill(Color(hex: 0xA97A35)).frame(height: 6), alignment: .top)
        }
        .frame(width: size, height: size * 0.85, alignment: .bottom)
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}
