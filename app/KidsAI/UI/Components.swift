import SwiftUI

/// 主要按鈕：深綠底白字，放在畫面下方拇指碰得到的地方。`secondary` 是白底綠框（例如「再說一次」）。
struct PrimaryButton: View {
    let title: String
    var systemImage: String?
    var secondary = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label {
                Text(title)
            } icon: {
                if let systemImage { Image(systemName: systemImage) }
            }
            .font(.title2.bold())
            .foregroundStyle(secondary ? Theme.action : .white)
            .frame(maxWidth: .infinity, minHeight: Theme.touch)
            .background(secondary ? Theme.surface : Theme.action, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius).stroke(Theme.action, lineWidth: secondary ? 3 : 0))
        }
        .buttonStyle(.plain)
    }
}

/// 選項卡的狀態：一般、停用（選錯後變淡）、正確答案（✓）、孩子選的（沒有對錯時）。
enum OptionState: Equatable {
    case normal
    case disabled
    case correct
    case chosen
}

/// 卡片外框：一律有看得見的邊框；正確答案加粗；正在播聲音時換底色並加聲波圖示（不和答案混淆）。
struct CardChrome: ViewModifier {
    var state: OptionState = .normal
    var isHighlighted = false

    func body(content: Content) -> some View {
        content
            .background(isHighlighted ? Theme.speaking : Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
                .stroke(state == .correct ? Theme.ink : Theme.cardStroke, lineWidth: state == .correct ? 4 : 2))
            .overlay(alignment: .topTrailing) {
                if isHighlighted {
                    Image(systemName: "speaker.wave.2.fill").font(.headline).foregroundStyle(Theme.ink).padding(8)
                        .accessibilityHidden(true)
                }
            }
            .opacity(state == .disabled ? 0.35 : 1)
    }
}

/// 卡上的標記：✓ 只給正確答案；沒有對錯時標「你選的」。
struct OptionMark: View {
    let state: OptionState

    var body: some View {
        switch state {
        case .correct:
            Image(systemName: "checkmark.circle.fill").font(.title2).foregroundStyle(Theme.ink)
                .accessibilityLabel("答案")
        case .chosen:
            Text("你選的").font(.headline).foregroundStyle(Theme.ink)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Theme.neutralRetry, in: Capsule())
        default:
            EmptyView()
        }
    }
}

/// 一張選項卡：圖＋文字＋標記。最大字級時整列直排、撐滿寬度。
struct OptionCard: View {
    let option: Option
    var state: OptionState = .normal
    var isHighlighted = false
    /// 一列排三張的小卡（沙盒反應）：最小 88，不是 140。
    var compact = false
    let onSelect: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 8) {
                if option.image != nil { ArtView(key: option.image, size: 56) }
                Text(option.label.zhHant)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                OptionMark(state: state)
            }
            .padding(12)
            .frame(minWidth: compact ? 88 : Theme.optionCard, maxWidth: typeSize.isAccessibilitySize || compact ? .infinity : nil,
                   minHeight: compact ? 88 : Theme.optionCard)
            .modifier(CardChrome(state: state, isHighlighted: isHighlighted))
        }
        .buttonStyle(.plain)
        .disabled(state == .disabled)
        .accessibilityLabel(option.a11yLabel.map { "\(option.label.zhHant)，\($0)" } ?? option.label.zhHant)
        .accessibilityAddTraits(state == .correct || state == .chosen ? .isSelected : [])
    }
}

/// 有聲音的選項（第 1 關）：一整列，圖、字、重聽鈕在同一個框裡。
/// 聲音播過之後，把聲音裡的話寫在卡上（CRITICAL-9：沒有語音也看得到）。
struct SoundOptionRow: View {
    let option: Option
    let state: OptionState
    let heard: Bool
    let isHighlighted: Bool
    let onSelect: () -> Void
    let onPlay: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                HStack(spacing: 12) {
                    if option.image != nil { ArtView(key: option.image, size: 48) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(option.label.zhHant).font(.title2.bold()).foregroundStyle(Theme.ink)
                        if heard, let script = option.soundScript {
                            Text("「\(script)」").font(.title3).foregroundStyle(Theme.ink)
                        }
                    }
                    Spacer(minLength: 0)
                    OptionMark(state: state)
                }
                .frame(maxWidth: .infinity, minHeight: Theme.touch, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(state == .disabled)
            .accessibilityLabel(option.a11yLabel.map { "\(option.label.zhHant)，\($0)" } ?? option.label.zhHant)
            .accessibilityAddTraits(state == .correct || state == .chosen ? .isSelected : [])
            IconButton(systemImage: "play.circle.fill", label: "再聽一次\(option.label.zhHant)", action: onPlay)
                .disabled(state == .disabled)
        }
        .padding(12)
        .modifier(CardChrome(state: state, isHighlighted: isHighlighted))
    }
}

/// 一排選項：iPhone 直向放不下時自動改成直排；最大字級時一律整列直排。
struct OptionGrid<Card: View>: View {
    let options: [Option]
    let card: (Option) -> Card
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(spacing: 12) { ForEach(options, id: \.id, content: card) }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { ForEach(options, id: \.id, content: card) }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Theme.optionCard), spacing: 12)], spacing: 12) {
                    ForEach(options, id: \.id, content: card)
                }
            }
        }
    }
}

/// 60pt 的小圖示按鈕（🔊、重聽等）。
struct IconButton: View {
    let systemImage: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(Theme.ink)
                .frame(width: Theme.touch, height: Theme.touch)
                .background(Theme.surface, in: Circle())
                .overlay(Circle().stroke(Theme.cardStroke, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
