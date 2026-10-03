import SwiftUI

/// 角色圖（P2）：D1 核准的正面設定稿，放在 Asset Catalog。讀不到就退回自繪暫代圖。
enum CharacterArt {
    static let dianDian = "char_diandian"
    static let guessHat = "char_guesshat"

    /// 猜猜帽小牌子（米白色圓牌）在圖上的位置，以整張圖的比例表示；量自 `char_guesshat.png`。
    static let badgeCenter = CGPoint(x: 0.478, y: 0.395)
    static let badgeSize = CGSize(width: 0.156, height: 0.118)
    /// 角色框小於這個大小就不疊「AI」字（28pt 的小帽子字會小到看不清，那裡本來就不給 VoiceOver）。
    static let badgeTextMinSize: CGFloat = 40

    /// 圖以 scaledToFit 放進 box×box 的框時，實際畫出來的區域（置中）。
    static func fittedRect(imageSize: CGSize, box: CGFloat) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return CGRect(x: 0, y: 0, width: box, height: box) }
        let scale = min(box / imageSize.width, box / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(x: (box - size.width) / 2, y: (box - size.height) / 2, width: size.width, height: size.height)
    }

    /// 小牌子在框裡的位置；框太小時回傳 nil（不疊字）。
    static func badgeRect(imageSize: CGSize, box: CGFloat) -> CGRect? {
        guard box >= badgeTextMinSize else { return nil }
        let fitted = fittedRect(imageSize: imageSize, box: box)
        let width = fitted.width * badgeSize.width
        let height = fitted.height * badgeSize.height
        return CGRect(x: fitted.minX + fitted.width * badgeCenter.x - width / 2,
                      y: fitted.minY + fitted.height * badgeCenter.y - height / 2,
                      width: width, height: height)
    }
}

/// 點點（旁白，不是 AI）：珊瑚色圓機器人、胸前愛心燈。
struct DianDian: View {
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let image = ArtResources.image(named: CharacterArt.dianDian) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                DrawnDianDian(size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel("點點")
    }
}

/// 點點的自繪暫代圖（Asset Catalog 讀不到角色圖時才用）。
private struct DrawnDianDian: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle().fill(Theme.diandian)
            HStack(spacing: size * 0.22) {
                Circle().fill(Theme.ink).frame(width: size * 0.12)
                Circle().fill(Theme.ink).frame(width: size * 0.12)
            }
            .offset(y: -size * 0.08)
            Image(systemName: "heart.fill")
                .font(.system(size: size * 0.2))
                .foregroundStyle(.white)
                .offset(y: size * 0.24)
        }
        .frame(width: size, height: size)
    }
}

/// 猜猜帽（AI）：藍色魔術帽，帽上的小牌子由 App 疊「AI」字（圖裡不放字）。輪廓和點點完全不同。
struct GuessHat: View {
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let image = ArtResources.image(named: CharacterArt.guessHat) {
                Image(uiImage: image).resizable().scaledToFit()
                    .frame(width: size, height: size)
                    .overlay(alignment: .topLeading) {
                        if let badge = CharacterArt.badgeRect(imageSize: image.size, box: size) {
                            Text("AI")
                                .font(.system(size: badge.height * 0.62, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.ai)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .frame(width: badge.width, height: badge.height)
                                .offset(x: badge.minX, y: badge.minY)
                        }
                    }
            } else {
                DrawnGuessHat(size: size)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(.isImage)
        .accessibilityLabel("猜猜帽，AI")
    }
}

/// 猜猜帽的自繪暫代圖（Asset Catalog 讀不到角色圖時才用）。
private struct DrawnGuessHat: View {
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            HatShape().fill(Theme.ai)
            Capsule().fill(Theme.ai.opacity(0.75)).frame(width: size, height: size * 0.16)
            Text("AI")
                .font(.system(size: size * 0.2, weight: .heavy))
                .foregroundStyle(Theme.ai)
                .padding(.horizontal, size * 0.08)
                .background(.white, in: RoundedRectangle(cornerRadius: 4))
                .offset(y: -size * 0.2)
        }
        .frame(width: size, height: size)
    }
}

private struct HatShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.minX + rect.width * 0.2, y: rect.maxY - rect.height * 0.08))
            p.addLine(to: CGPoint(x: rect.midX - rect.width * 0.12, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.midX + rect.width * 0.12, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.2, y: rect.maxY - rect.height * 0.08))
            p.closeSubpath()
        }
    }
}

/// 一句話顯示在說話者的框裡：旁白與回饋＝點點；猜測與 ai_persona 的故事句＝猜猜帽。
struct SpeechBubble: View {
    let text: String
    let isAI: Bool
    var isSpeaking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Group {
                if isAI { GuessHat(size: 52) } else { DianDian(size: 52) }
            }
            .scaleEffect(isSpeaking && !reduceMotion ? 1.08 : 1)
            Text(text)
                .font(.title2.weight(.semibold))
                .foregroundStyle(Theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .stroke(isAI ? Theme.ai : Theme.diandian, lineWidth: isSpeaking ? 4 : 1.5))
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: isSpeaking)
        .accessibilityElement(children: .combine)
    }
}
