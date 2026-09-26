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
        /// 單元 2：坐著的小黃貓（願望與說清楚的猜測）、站著的大白貓（說不清楚的猜測）。
        case sittingCat
        case standingCat
        /// 四隻腳分開、數得出來的小狗（單元 3 要孩子數腳）。
        case countableDog
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
        "img_u2_wish_cat": .sittingCat, "img_u2_guess_cat_clear": .sittingCat,
        "img_u2_guess_cat_vague": .standingCat,
        "img_sticker_say_clear": .emoji("💬"),
        // 單元 3
        "img_u3_apple_plain": .emoji("🍎"), "img_u3_apple_glasses": .emoji("🍎👓"),
        "img_u3_card_dog": .countableDog,
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
                Text(text).font(.system(size: size)).lineLimit(1).minimumScaleFactor(0.3)
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
            case .sittingCat?:
                SittingCat(size: size * 1.1)
            case .standingCat?:
                StandingCat(size: size * 1.5)
            case .countableDog?:
                CountableDog(size: size * 1.4)
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

/// 小狗：側面，四隻腳分開畫，數得出來（身體、頭、耳朵、眼睛、尾巴都是簡單形狀）。
private struct CountableDog: View {
    let size: CGFloat
    private let fur = Color(hex: 0x8B5E3C)
    private let ear = Color(hex: 0x5E3B22)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Capsule().fill(fur)
                .frame(width: size * 0.2, height: size * 0.06)
                .rotationEffect(.degrees(-35))
                .offset(x: size * 0.02, y: size * 0.3)
            ForEach(0..<4, id: \.self) { leg in
                RoundedRectangle(cornerRadius: size * 0.03).fill(fur)
                    .frame(width: size * 0.07, height: size * 0.26)
                    .offset(x: size * (0.2 + Double(leg) * 0.155), y: size * 0.56)
            }
            Capsule().fill(fur)
                .frame(width: size * 0.62, height: size * 0.28)
                .offset(x: size * 0.16, y: size * 0.34)
            Circle().fill(fur)
                .frame(width: size * 0.3, height: size * 0.3)
                .offset(x: size * 0.62, y: size * 0.16)
            Ellipse().fill(ear)
                .frame(width: size * 0.1, height: size * 0.18)
                .offset(x: size * 0.64, y: size * 0.12)
            Circle().fill(Theme.ink)
                .frame(width: size * 0.05, height: size * 0.05)
                .offset(x: size * 0.8, y: size * 0.25)
        }
        .frame(width: size, height: size * 0.85, alignment: .topLeading)
    }
}

/// 坐著的小黃貓：正面、身體是豎著的圓、尾巴繞在腳邊（和站著的貓一眼就分得出來）。
private struct SittingCat: View {
    let size: CGFloat
    private let fur = Color(hex: 0xF5B82E)

    var body: some View {
        ZStack(alignment: .topLeading) {
            Ellipse().fill(fur)
                .frame(width: size * 0.5, height: size * 0.56)
                .offset(x: size * 0.25, y: size * 0.4)
            Capsule().fill(fur)
                .frame(width: size * 0.36, height: size * 0.08)
                .offset(x: size * 0.52, y: size * 0.86)
            ForEach([0.29, 0.55], id: \.self) { x in
                Triangle().fill(fur)
                    .frame(width: size * 0.14, height: size * 0.16)
                    .offset(x: size * x, y: size * 0.04)
            }
            Circle().fill(fur)
                .frame(width: size * 0.42, height: size * 0.42)
                .offset(x: size * 0.29, y: size * 0.12)
            ForEach([0.39, 0.54], id: \.self) { x in
                Circle().fill(Theme.ink).frame(width: size * 0.05, height: size * 0.05)
                    .offset(x: size * x, y: size * 0.27)
            }
        }
        .frame(width: size, height: size, alignment: .topLeading)
    }
}

/// 站著的大白貓：側面、四隻腳站著、白色加深色外框（在白底上也看得清楚）。
private struct StandingCat: View {
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            part(Capsule(), width: 0.08, height: 0.3, x: 0.06, y: 0.2, angle: -20)
            ForEach([0.22, 0.34, 0.56, 0.68], id: \.self) { x in
                part(RoundedRectangle(cornerRadius: size * 0.03), width: 0.07, height: 0.24, x: x, y: 0.5)
            }
            part(Capsule(), width: 0.62, height: 0.26, x: 0.16, y: 0.3)
            ForEach([0.66, 0.8], id: \.self) { x in
                Triangle().fill(.white).overlay(Triangle().stroke(Theme.ink, lineWidth: 2))
                    .frame(width: size * 0.1, height: size * 0.12)
                    .offset(x: size * x, y: size * 0.08)
            }
            part(Circle(), width: 0.28, height: 0.28, x: 0.64, y: 0.14)
            Circle().fill(Theme.ink).frame(width: size * 0.04, height: size * 0.04)
                .offset(x: size * 0.82, y: size * 0.24)
        }
        .frame(width: size, height: size * 0.8, alignment: .topLeading)
    }

    private func part(_ shape: some Shape, width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat, angle: Double = 0) -> some View {
        shape.fill(.white)
            .overlay(shape.stroke(Theme.ink, lineWidth: 2))
            .frame(width: size * width, height: size * height)
            .rotationEffect(.degrees(angle))
            .offset(x: size * x, y: size * y)
    }
}
