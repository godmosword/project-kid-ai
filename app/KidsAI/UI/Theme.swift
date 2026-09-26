import SwiftUI

/// 對應 design/tokens/kidsai.tokens.json（改值時兩邊一起改）。
enum Theme {
    static let bg = Color(hex: 0xFFF8EC)
    static let surface = Color.white
    static let ink = Color(hex: 0x2B2B3A)
    static let inkSecondary = Color(hex: 0x5C5C7A)
    static let action = Color(hex: 0x1A7A4B)
    static let neutralRetry = Color(hex: 0xE9E4DA)
    static let cardStroke = Color(hex: 0x8C8475)
    static let speaking = Color(hex: 0xFFE9A8)
    static let diandian = Color(hex: 0xF2877A)
    static let ai = Color(hex: 0x1E6FC2)
    static let parent = Color(hex: 0x3D4A5C)

    static let islands: [Color] = [Color(hex: 0xF5B82E), Color(hex: 0x3BAA6E), Color(hex: 0xF08A3C), Color(hex: 0xA98BF0)]
    static let islandIcons = ["questionmark.circle.fill", "bubble.left.fill", "magnifyingglass", "film.fill"]
    static let islandNames = ["認識島", "提問島", "檢查島", "創作島"]

    /// 兒童可點物件最小 60pt、選項卡最小 140pt。
    static let touch: CGFloat = 60
    static let optionCard: CGFloat = 140
    static let cardRadius: CGFloat = 20
    static let buttonRadius: CGFloat = 28
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
