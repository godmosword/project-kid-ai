import SwiftUI

typealias HeadingFocus = AccessibilityFocusState<Bool>.Binding

/// 點點說的一句（回饋、提示、指示、結語）：一律畫在點點的框裡，字和聲音同時出現（CRITICAL-9）。
struct NarratorLine: View {
    let store: UnitStore
    let item: TextItem?

    var body: some View {
        if let item, item.audience == .child {
            SpeechBubble(text: item.zhHant, isAI: false, isSpeaking: store.isSpeaking(item.zhHant))
        }
    }
}

/// 選擇題與回顧：點選項即作答；有聲音的卡是一整列，另有重聽鈕，和選取分開。
struct QuestionView: View {
    let store: UnitStore
    let focus: HeadingFocus

    var body: some View {
        if let question = store.engine.question, case .question(let q) = store.phase {
            VStack(spacing: 20) {
                Text(question.prompt.zhHant)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused(focus)
                if let stage = question.stage {
                    ArtView(key: stage.image, size: 90, label: stage.a11yLabel)
                }
                if question.options.contains(where: { $0.soundScript != nil }) {
                    VStack(spacing: 12) {
                        ForEach(question.options, id: \.id) { option in
                            SoundOptionRow(option: option, state: state(of: option, q), heard: store.hasHeard(option.id),
                                           isHighlighted: store.speakingHighlight == option.id,
                                           onSelect: { store.send(.select(option.id)) },
                                           onPlay: { store.playSound(of: option) })
                        }
                    }
                } else {
                    OptionGrid(options: question.options) { option in
                        OptionCard(option: option, state: state(of: option, q),
                                   isHighlighted: store.speakingHighlight == option.id) {
                            store.send(.select(option.id))
                        }
                    }
                }
                NarratorLine(store: store, item: feedback(q, question))
            }
        }
    }

    /// 畫面上的回饋：答對、揭曉、再試一次，或（8 秒沒動作後）提示。
    private func feedback(_ q: QuestionState, _ question: UnitEngine.Question) -> TextItem? {
        switch q.outcome {
        case .success?: question.feedback.success
        case .revealed?: question.feedback.reveal
        case nil: q.attempts > 0 ? question.feedback.notYet : (store.hintShown ? question.hint : nil)
        }
    }

    private func state(of option: Option, _ q: QuestionState) -> OptionState {
        let dimmed: OptionState = q.disabled.contains(option.id) ? .disabled : .normal
        switch q.outcome {
        case .success(let selected)?:
            return selected == option.id ? .correct : dimmed
        case .revealed(let selected, let correct)?:
            if correct.contains(option.id) { return .correct }
            return selected == option.id ? .chosen : dimmed
        case nil:
            return dimmed
        }
    }
}

/// 跟讀（本版一律一起說）：下方按「一起說」，停 0.5 秒後慢慢念目標句，念到的字會亮起來。
struct SayTogetherView: View {
    let store: UnitStore
    let focus: HeadingFocus

    var body: some View {
        if case .asr(let asr) = store.engine.beat.kind, case .line(let line) = asr.target {
            let active = store.isNarrating && store.caption?.role == .readAlong
            VStack(spacing: 24) {
                Text(asr.prompt.zhHant).font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused(focus)
                ForEach(asr.sayTogether.lines, id: \.id) { NarratorLine(store: store, item: $0) }
                Text(Self.readAlong(line.zhHant, spoken: active ? store.readAlongProgress : nil))
                    .font(.largeTitle.weight(.heavy))
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .stroke(active ? Theme.action : Theme.cardStroke, lineWidth: active ? 5 : 2))
                    .accessibilityLabel(line.zhHant)
            }
        }
    }

    /// 已念到的字用綠色，還沒念到的用墨色。`spoken` 是 UTF-16 位置（語音引擎回報的範圍）。
    static func readAlong(_ text: String, spoken: Int?) -> AttributedString {
        let ns = text as NSString
        let cut = min(max(spoken ?? 0, 0), ns.length)
        var done = AttributedString(ns.substring(to: cut))
        done.foregroundColor = Theme.action
        var rest = AttributedString(ns.substring(from: cut))
        rest.foregroundColor = Theme.ink
        return done + rest
    }
}

/// 沙盒：猜猜帽對每張卡說出猜測；孩子對猜測做反應。三張卡都玩一次（D36）。
struct SandboxView: View {
    let store: UnitStore
    let focus: HeadingFocus

    var body: some View {
        if let sandbox = store.engine.sandboxBeat, let definition = store.engine.sandboxDefinition,
           case .sandbox(let s) = store.phase, s.slotIndex < definition.slots.count {
            let slot = definition.slots[s.slotIndex]
            VStack(spacing: 20) {
                if s.closing {
                    GuessHat(size: 120)
                    NarratorLine(store: store, item: sandbox.closingLine).accessibilityFocused(focus)
                } else {
                    Text(slot.label.zhHant).font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused(focus)
                    ArtView(key: slot.image, size: 110, label: slot.a11yLabel ?? slot.label.zhHant)
                    if s.choiceID == nil {
                        NarratorLine(store: store, item: sandbox.prompt)
                        OptionGrid(options: slot.choices) { option in
                            OptionCard(option: option) { store.send(.pickCard(option.id)) }
                        }
                    }
                    ForEach(s.guesses, id: \.id) { guess in
                        VStack(alignment: .leading, spacing: 8) {
                            SpeechBubble(text: guess.text.zhHant, isAI: true, isSpeaking: store.isSpeaking(guess.text.zhHant))
                            if guess.uncertainty == .unsure {
                                Label(EngineText.unsure, systemImage: "questionmark.bubble.fill")
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(Theme.ai, in: Capsule())
                                    .padding(.leading, 64)
                            }
                        }
                    }
                    if !s.guesses.isEmpty {
                        NarratorLine(store: store, item: sandbox.reactionPrompt)
                        // 猜測念完才出現反應鈕，孩子先聽完再反應
                        if !store.isNarrating || s.reaction != nil {
                            OptionGrid(options: sandbox.reactions) { option in
                                OptionCard(option: option, state: reactionState(option, s)) { store.send(.react(option.id)) }
                            }
                        }
                    }
                    if s.reaction != nil || (s.choiceID != nil && s.guesses.isEmpty) {
                        NarratorLine(store: store, item: sandbox.feedback.reveal)
                    }
                }
            }
        }
    }

    private func reactionState(_ option: Option, _ s: SandboxState) -> OptionState {
        if s.reaction == option.id { return .chosen }
        return s.reaction != nil || store.inputLocked ? .disabled : .normal
    }
}

/// 故事：同一節點的句子念完，才出現分歧選項或下一步。
struct StoryView: View {
    let store: UnitStore
    let focus: HeadingFocus

    var body: some View {
        if case .story(let id) = store.phase, let node = store.engine.storyNode(id) {
            VStack(spacing: 16) {
                ForEach(Array(node.lines.enumerated()), id: \.element.id) { index, line in
                    SpeechBubble(text: line.zhHant, isAI: node.speaker == .aiPersona, isSpeaking: store.isSpeaking(line.zhHant))
                        .accessibilityFocused(focus, index == 0)
                }
                if case .choices(let choices) = node.exit, !store.isNarrating {
                    ForEach(choices, id: \.id) { choice in
                        Button { store.send(.chooseStory(choice.id)) } label: {
                            HStack(spacing: 12) {
                                if choice.image != nil { ArtView(key: choice.image, size: 44) }
                                Text(choice.label.zhHant).font(.title2.bold()).foregroundStyle(Theme.ink)
                            }
                            .padding(.horizontal, 12)
                            .frame(maxWidth: .infinity, minHeight: Theme.touch)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.buttonRadius))
                            .overlay(RoundedRectangle(cornerRadius: Theme.buttonRadius).stroke(Theme.cardStroke, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(choice.a11yLabel.map { "\(choice.label.zhHant)，\($0)" } ?? choice.label.zhHant)
                    }
                }
            }
        }
    }
}

/// 開場與儀式：一般旁白；儀式另外顯示猜猜帽。
struct LinesView: View {
    let store: UnitStore
    let focus: HeadingFocus

    var body: some View {
        VStack(spacing: 16) {
            if case .ritual(let lines) = store.engine.beat.kind {
                GuessHat(size: 140)
                bubbles(lines)
            } else if case .intro(let lines) = store.engine.beat.kind {
                DianDian(size: 120)
                bubbles(lines)
            }
        }
    }

    private func bubbles(_ lines: [TextItem]) -> some View {
        ForEach(Array(lines.enumerated()), id: \.element.id) { index, line in
            NarratorLine(store: store, item: line).accessibilityFocused(focus, index == 0)
        }
    }
}

/// 貼紙頁：貼紙不綁表現；家長卡在下方，標「給大人」，不念、不擋路、不進孩子的朗讀順序（D32'）。
struct StickerView: View {
    let store: UnitStore
    let focus: HeadingFocus

    var body: some View {
        if case .sticker(let sticker, let lines) = store.engine.beat.kind {
            VStack(spacing: 20) {
                ArtView(key: sticker.image, size: 110, label: sticker.a11yLabel)
                    .frame(width: 180, height: 180)
                    .background(Theme.surface, in: Circle())
                    .overlay(Circle().stroke(Theme.cardStroke, lineWidth: 2))
                    .accessibilityFocused(focus)
                ForEach(lines, id: \.id) { NarratorLine(store: store, item: $0) }
                VStack(alignment: .leading, spacing: 6) {
                    Text("給大人").font(.headline)
                    Text(store.engine.content.unit.parentCard.zhHant).font(.body)
                }
                .foregroundStyle(.white)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.parent, in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            }
        }
    }
}

private extension View {
    /// 只有第一句接 VoiceOver 焦點。
    func accessibilityFocused(_ focus: HeadingFocus, _ isFirst: Bool) -> some View {
        modifier(FirstFocus(focus: focus, isFirst: isFirst))
    }
}

private struct FirstFocus: ViewModifier {
    let focus: HeadingFocus
    let isFirst: Bool

    func body(content: Content) -> some View {
        if isFirst { content.accessibilityFocused(focus) } else { content }
    }
}
