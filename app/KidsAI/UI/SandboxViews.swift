import SwiftUI

/// 沙盒：猜猜帽對每張卡說出猜測；孩子對猜測做反應。每張卡都玩一次（D36、D37）。
/// 有對錯的沙盒（單元 3）每張卡各自計次；反應鈕一出現就留到換卡，上鎖時外觀不變（只擋點擊）。
struct SandboxView: View {
    let store: UnitStore
    let focus: HeadingFocus
    /// 反應鈕已經出現過的卡（重念、回前景時不再消失）。
    @State private var reactionsShown: Set<String> = []
    @Environment(\.contentWidth) private var contentWidth
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 「看圖檢查」時畫面捲到這裡（主題圖的頂端）。
    static let artID = "sandboxArt"

    var body: some View {
        if let sandbox = store.engine.sandboxBeat, case .sandbox(let s) = store.phase, let slot = store.engine.sandboxSlot(s) {
            // 窄螢幕（iPhone SE）縮小間距，看圖、猜測、反應鈕盡量在同一屏
            VStack(spacing: contentWidth < 360 ? 12 : 20) {
                if s.closing {
                    GuessHat(size: 120)
                    NarratorLine(store: store, item: sandbox.closingLine).accessibilityFocused(focus)
                } else if Self.isComparing(s, slot, store.engine) {
                    comparison(s, slot, sandbox)
                } else {
                    Text(slot.label.zhHant).font(.title.bold())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityFocused(focus)
                    slotArt(slot, s, sandbox).id(Self.artID)
                    if !s.played.isEmpty { playedRow(s, slot) }
                    choices(s, slot, sandbox)
                    ForEach(s.guesses, id: \.id) { GuessView(store: store, guess: $0) }
                    if !s.guesses.isEmpty {
                        NarratorLine(store: store, item: sandbox.reactionPrompt)
                        if reactionsVisible(s, sandbox) { reactions(s, sandbox) }
                    }
                    NarratorLine(store: store, item: feedback(s, sandbox))
                }
            }
            .onChange(of: reactionsReady(s, sandbox), initial: true) { _, ready in
                if ready { reactionsShown.insert(cardKey(s)) }
            }
        }
    }

    /// 多卡主題兩張都玩完：進入並排比較（D37）。
    static func isComparing(_ s: SandboxState, _ slot: SandboxSlot, _ engine: UnitEngine) -> Bool {
        slot.choices.count > 1 && engine.sandboxCardDone(s) && engine.unplayedChoices(s).isEmpty
    }

    // MARK: - 主題圖、卡、猜測

    /// 主題圖放在中性框裡（和猜猜帽畫的圖分開）；要「看圖檢查」時放大，答錯後加粗框。
    private func slotArt(_ slot: SandboxSlot, _ s: SandboxState, _ sandbox: SandboxBeat) -> some View {
        let graded = sandbox.scoring != .open
        let lookAgain = graded && s.graded == nil && s.attempts + s.unsureTaps > 0
        let size: CGFloat = graded ? (contentWidth < 360 ? 116 : 160) : 110
        return ArtView(key: slot.image, size: size, label: slot.a11yLabel ?? slot.label.zhHant)
            .padding(12)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(lookAgain ? Theme.ink : Theme.cardStroke, lineWidth: lookAgain ? 5 : 2))
    }

    /// 還沒選卡：多卡主題第一次念 prompt 並列出卡；選好後，孩子選的句子卡留在猜猜帽回答的上方。
    @ViewBuilder private func choices(_ s: SandboxState, _ slot: SandboxSlot, _ sandbox: SandboxBeat) -> some View {
        if s.choiceID == nil {
            if s.played.isEmpty { NarratorLine(store: store, item: sandbox.prompt) }
            OptionGrid(options: store.engine.unplayedChoices(s)) { option in
                OptionCard(option: option, isHighlighted: store.speakingHighlight == option.id) { store.send(.pickCard(option.id)) }
            }
        } else if slot.choices.count > 1, let chosen = slot.choices.first(where: { $0.id == s.choiceID }) {
            ChosenSentence(label: chosen.label.zhHant)
        }
    }

    /// 同一主題先玩過的卡：句子＋猜猜帽畫的圖，和這一張同尺寸。
    private func playedRow(_ s: SandboxState, _ slot: SandboxSlot) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(s.played, id: \.choiceID) { card in
                VStack(spacing: 6) {
                    if let choice = slot.choices.first(where: { $0.id == card.choiceID }) {
                        Text(choice.label.zhHant).font(.headline).foregroundStyle(Theme.ink)
                    }
                    ForEach(card.guesses, id: \.id) { guess in
                        if guess.image != nil { AIDrawing(guess: guess, size: 90) }
                        if guess.uncertainty == .unsure { UnsureTag(small: true) }
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - 並排比較（D37）

    /// 「我想要的」和猜猜帽畫的兩張，同尺寸排成一列；這時才念揭曉句。
    private func comparison(_ s: SandboxState, _ slot: SandboxSlot, _ sandbox: SandboxBeat) -> some View {
        let cards = s.played + [PlayedCard(choiceID: s.choiceID ?? "", guesses: s.guesses, reaction: s.reaction)]
        let cell = max(88, ((contentWidth - 16) / 3).rounded(.down))
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return VStack(spacing: 20) {
            Text(slot.label.zhHant).font(.title.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused(focus)
            layout {
                VStack(spacing: 6) {
                    ArtView(key: slot.image, size: cell * 0.6, label: slot.a11yLabel ?? slot.label.zhHant)
                        .frame(width: cell - 8, height: cell - 8)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
                        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.cardStroke, lineWidth: 2))
                    Text(slot.label.zhHant).font(.headline).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                }
                ForEach(cards, id: \.choiceID) { card in
                    VStack(spacing: 6) {
                        ForEach(card.guesses.filter { $0.image != nil }, id: \.id) { AIDrawing(guess: $0, size: cell * 0.6 - 20) }
                        if let choice = slot.choices.first(where: { $0.id == card.choiceID }) {
                            Text(choice.label.zhHant).font(.headline).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
                        }
                        if card.guesses.contains(where: { $0.uncertainty == .unsure }) { UnsureTag(small: true) }
                    }
                }
            }
            NarratorLine(store: store, item: sandbox.feedback.reveal)
        }
    }

    // MARK: - 反應

    /// 反應鈕排成一列、等寬（小螢幕也不用捲）；最大字級時直排。
    @ViewBuilder private func reactions(_ s: SandboxState, _ sandbox: SandboxBeat) -> some View {
        let card = { (option: Option) in
            OptionCard(option: option, state: reactionState(option, s, sandbox),
                       isHighlighted: store.speakingHighlight == option.id, compact: true) {
                store.send(.react(option.id))
            }
        }
        if typeSize.isAccessibilitySize {
            VStack(spacing: 12) { ForEach(sandbox.reactions, id: \.id) { card($0) } }
        } else {
            HStack(spacing: 12) { ForEach(sandbox.reactions, id: \.id) { card($0).frame(maxWidth: .infinity) } }
        }
    }

    /// 反應鈕在念到反應題時出現（標籤依序念出並標亮），之後一直留到換卡。
    private func reactionsVisible(_ s: SandboxState, _ sandbox: SandboxBeat) -> Bool {
        reactionsShown.contains(cardKey(s)) || reactionsReady(s, sandbox)
    }

    private func reactionsReady(_ s: SandboxState, _ sandbox: SandboxBeat) -> Bool {
        guard !s.guesses.isEmpty else { return false }
        if !store.isNarrating || s.reaction != nil || s.attempts + s.unsureTaps > 0 { return true }
        let reactionIDs = Set(sandbox.reactions.map(\.id))
        return store.caption?.text == sandbox.reactionPrompt.zhHant || store.caption?.highlight.map(reactionIDs.contains) == true
    }

    private func cardKey(_ s: SandboxState) -> String { "\(s.slotIndex)-\(s.played.count)-\(s.choiceID ?? "")" }

    private func reactionState(_ option: Option, _ s: SandboxState, _ sandbox: SandboxBeat) -> OptionState {
        switch s.graded {
        case .success?: return s.reaction == option.id ? .correct : .normal
        case .revealed(let correct)?:
            if option.id == correct { return .correct }
            return s.reaction == option.id ? .chosen : (s.disabled.contains(option.id) ? .disabled : .normal)
        case nil:
            if sandbox.scoring != .open { return s.disabled.contains(option.id) ? .disabled : .normal }
            if s.reaction == option.id { return .chosen }
            return s.reaction != nil ? .disabled : .normal
        }
    }

    /// 畫面上的回饋：答對、再看看、揭曉；多卡主題的揭曉在並排比較裡。
    private func feedback(_ s: SandboxState, _ sandbox: SandboxBeat) -> TextItem? {
        guard s.choiceID != nil else { return nil }
        if s.guesses.isEmpty { return sandbox.feedback.reveal }
        switch s.graded {
        case .success?: return sandbox.feedback.success
        case .revealed?: return sandbox.feedback.reveal
        case nil:
            if sandbox.scoring != .open { return s.attempts + s.unsureTaps > 0 ? sandbox.feedback.notYet : nil }
            return s.reaction != nil && store.engine.unplayedChoices(s).isEmpty ? sandbox.feedback.reveal : nil
        }
    }
}

/// 孩子選的句子卡：只是標示，不是按鈕（VoiceOver 不會念成按鈕）。
private struct ChosenSentence: View {
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(label).font(.title2.bold()).foregroundStyle(Theme.ink).multilineTextAlignment(.center)
            OptionMark(state: .chosen)
        }
        .padding(12)
        .frame(minWidth: Theme.optionCard)
        .modifier(CardChrome(state: .chosen))
        .accessibilityElement(children: .combine)
    }
}

/// 猜猜帽旁的「我不確定」標籤（schema 規定 unsure 要顯示）。
private struct UnsureTag: View {
    var small = false

    var body: some View {
        Label(EngineText.unsure, systemImage: "questionmark.bubble.fill")
            .font(small ? .subheadline.bold() : .title3.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, small ? 8 : 12).padding(.vertical, small ? 4 : 6)
            .background(Theme.ai, in: Capsule())
    }
}

/// 猜猜帽說的一個猜測：說話框、「我不確定」標籤、猜猜帽畫的圖。
private struct GuessView: View {
    let store: UnitStore
    let guess: Guess

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SpeechBubble(text: guess.text.zhHant, isAI: true, isSpeaking: store.isSpeaking(guess.text.zhHant))
            if guess.uncertainty == .unsure { UnsureTag().padding(.leading, 64) }
            if guess.image != nil { AIDrawing(guess: guess, size: 90).padding(.leading, 64) }
        }
    }
}

/// 猜猜帽畫的圖：AI 藍框＋角落的小猜猜帽，和「我想要的」中性框分得出來。
private struct AIDrawing: View {
    let guess: Guess
    let size: CGFloat

    var body: some View {
        ArtView(key: guess.image, size: size, label: guess.a11yLabel.map(SandboxA11y.drawnByAI))
            .padding(10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.ai, lineWidth: 3))
            .overlay(alignment: .topTrailing) { GuessHat(size: 28).offset(x: 8, y: -10).accessibilityHidden(true) }
    }
}

/// 只給 VoiceOver 的字（D43）。
enum SandboxA11y {
    static func drawnByAI(_ description: String) -> String { "猜猜帽畫的：\(description)" }
}
