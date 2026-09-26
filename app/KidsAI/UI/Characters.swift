import SwiftUI

/// 點點（旁白，不是 AI）：珊瑚色圓形、胸前愛心。暫代圖，美術定稿後替換。
struct DianDian: View {
    var size: CGFloat = 56

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
        .accessibilityLabel("點點")
    }
}

/// 猜猜帽（AI）：藍色尖帽，帽上固定有「AI」牌。輪廓和點點完全不同。
struct GuessHat: View {
    var size: CGFloat = 56

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
        .accessibilityLabel("猜猜帽，AI")
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
