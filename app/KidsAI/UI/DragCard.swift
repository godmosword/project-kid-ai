import SwiftUI

/// 一張可以拖的卡：圖卡（配對、排序的卡片區）、長條（分組；最大字級時左圖右字）、排序格裡的一列。
struct DragCard: View {
    enum Style: Equatable {
        case tile(width: CGFloat)
        /// 卡片區的長條有重聽鈕；放進組裡的不放（半寬放不下，點卡本身就會播）。
        case strip(showsPlay: Bool)
        case row
    }

    /// VoiceOver 的自訂動作（放到〇〇、放回卡片區）。
    struct Action: Identifiable {
        let name: String
        let perform: () -> Void
        var id: String { name }
    }

    let item: Option
    let style: Style
    let isSelected: Bool
    let isFixed: Bool
    let isReturned: Bool
    let heard: Bool
    let isSpeaking: Bool
    let actions: [Action]
    let onTap: () -> Void
    let onPlay: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onTap) { content.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .accessibilityLabel(item.a11yLabel.map { "\(item.label.zhHant)，\($0)" } ?? item.label.zhHant)
                .accessibilityValue(heard ? item.soundScript ?? "" : "")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityActions { ForEach(actions) { Button($0.name, action: $0.perform) } }
            if case .strip(true) = style, item.soundScript != nil {
                IconButton(systemImage: "play.circle.fill", label: "再聽一次\(item.label.zhHant)", action: onPlay)
            }
        }
        .padding(.horizontal, isStrip ? 10 : 8)
        .padding(.vertical, isStrip ? 4 : 8)
        .background(background, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(borderColor, lineWidth: borderWidth))
        .overlay(alignment: .topTrailing) {
            if isSpeaking {
                Image(systemName: "speaker.wave.2.fill").font(.headline).foregroundStyle(Theme.ink).padding(6)
                    .accessibilityHidden(true)
            }
        }
        // 選起來的卡浮起來（不只靠框的顏色）
        .shadow(color: isSelected ? Theme.ink.opacity(0.3) : .clear, radius: 8, y: 4)
        .scaleEffect(isSelected && !reduceMotion ? 1.05 : 1)
        .offset(y: isSelected && !reduceMotion ? -3 : 0)
    }

    private var isStrip: Bool {
        if case .strip = style { return true }
        return false
    }

    @ViewBuilder private var content: some View {
        switch style {
        case .tile(let width):
            VStack(spacing: 4) {
                if item.image != nil { ArtView(key: item.image, size: width * 0.55) }
                Text(item.label.zhHant).font(width < 120 ? .headline : .title3.bold()).foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center).minimumScaleFactor(0.8)
            }
            .frame(width: width - 16, height: width - 16)
        case .row:
            HStack(spacing: 10) {
                if item.image != nil { ArtView(key: item.image, size: 44) }
                Text(item.label.zhHant).font(.title3.bold()).foregroundStyle(Theme.ink)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        case .strip:
            HStack(spacing: 10) {
                if item.image != nil { ArtView(key: item.image, size: 56) }
                // 放得下就一行（卡名＋句子），放不下再分兩行
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { stripText }
                    VStack(alignment: .leading, spacing: 2) { stripText }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        }
    }

    @ViewBuilder private var stripText: some View {
        Text(item.label.zhHant).font(.title3.bold()).foregroundStyle(Theme.ink)
        if heard, let script = item.soundScript {
            Text("「\(script)」").font(.body).foregroundStyle(Theme.ink)
        }
    }

    private var background: Color {
        if isSpeaking { return Theme.speaking }
        if isReturned { return Theme.neutralRetry }
        return Theme.surface
    }

    private var borderColor: Color {
        if isSelected { return Theme.action }
        return isFixed ? Theme.ink : Theme.cardStroke
    }

    private var borderWidth: CGFloat { isSelected || isFixed ? 4 : 2 }
}

/// 目標的外框：空的用虛線；拖曳中會落在這裡時加粗（不只靠顏色）。
/// 點外框的空白處＝點這個目標；點裡面的卡由卡自己處理。
struct TargetChrome: ViewModifier {
    let isHovered: Bool
    let isEmpty: Bool
    let isSpeaking: Bool
    let onTap: () -> Void

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(isSpeaking ? Theme.speaking : Theme.surface.opacity(0.6))
                    .onTapGesture(perform: onTap)
            }
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(isHovered ? Theme.action : Theme.cardStroke,
                        style: StrokeStyle(lineWidth: isHovered ? 4 : 2, dash: isEmpty || isHovered ? [10, 6] : []))
                .allowsHitTesting(false))
    }
}

/// 分組的圖示用明確的對照表（art-spec §4）；查不到就只顯示字。
/// 「留下」用細的 ✓，和代表答案的圓形 ✓ 分開。
enum DragArt {
    static let groupIcons: [String: String] = ["keep": "checkmark", "fix": "pencil"]
}

/// 只給 VoiceOver 的字（不顯示、不念給一般使用者）。
enum DragA11y {
    static let empty = "還沒有卡片"
    static let backToTray = "放回卡片區"
    static let occupied = "這個位子已經有卡片"
    static func slot(_ position: Int) -> String { "第 \(position) 格" }
    static func placeOn(_ target: String) -> String { "放到\(target)" }
    static func placed(_ item: String, _ target: String) -> String { "\(item)，放到\(target)" }
}

enum DragArea {
    static let name = "dragArea"
    static let tray = "_tray"
}

struct DragFrameKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    func reportFrame(_ id: String) -> some View {
        background(GeometryReader { g in
            Color.clear.preference(key: DragFrameKey.self, value: [id: g.frame(in: .named(DragArea.name))])
        })
    }
}
