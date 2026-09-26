import Foundation

/// 沙盒的規則：只回傳新狀態與要念的話，由 `UnitEngine` 寫回。
/// 單卡主題自動選好；多卡主題每張都玩（D37）；有對錯的沙盒每張卡各自計次（D40）。
extension UnitEngine {
    var sandboxBeat: SandboxBeat? {
        if case .sandbox(let s) = beat.kind { return s }
        return nil
    }

    var sandboxDefinition: SandboxDefinition? {
        sandboxBeat.flatMap { content.sandbox($0.sandboxRef) }
    }

    func sandboxSlot(_ s: SandboxState) -> SandboxSlot? {
        guard let definition = sandboxDefinition, definition.slots.indices.contains(s.slotIndex) else { return nil }
        return definition.slots[s.slotIndex]
    }

    /// 這個主題還沒玩過的卡（不含正在玩的這張）。
    func unplayedChoices(_ s: SandboxState) -> [Option] {
        guard let slot = sandboxSlot(s) else { return [] }
        return slot.choices.filter { choice in choice.id != s.choiceID && !s.played.contains { $0.choiceID == choice.id } }
    }

    /// 進入一個主題（或同一主題的下一張卡）：只剩一張就直接選好、不念「選一張卡」；
    /// 第一次有多張可選時念 prompt，並依序念出卡名。
    func sandboxEnter(_ state: SandboxState) -> (SandboxState, [SpeechLine]) {
        guard let sandbox = sandboxBeat else { return (state, []) }
        let remaining = unplayedChoices(state)
        guard remaining.count == 1, let only = remaining.first else {
            let prompt = state.played.isEmpty ? say([sandbox.prompt]) : []
            return (state, prompt + labelLines(remaining.map { ($0.id, $0.label) }))
        }
        return sandboxPick(state, only.id) ?? (state, [])
    }

    func sandboxPick(_ state: SandboxState, _ choiceID: String) -> (SandboxState, [SpeechLine])? {
        guard state.choiceID == nil, let sandbox = sandboxBeat, let definition = sandboxDefinition,
              let slot = sandboxSlot(state), unplayedChoices(state).contains(where: { $0.id == choiceID }) else { return nil }
        var s = state
        let request = SandboxRequest(sandboxID: definition.id, slotID: slot.id, structuredChoice: choiceID)
        s.choiceID = choiceID
        // 缺猜測庫等同查不到：走揭曉句，不卡住（CRITICAL-8）
        s.guesses = content.banks[definition.id].map { SandboxLookup.guesses(for: request, definition: definition, bank: $0) } ?? []
        guard !s.guesses.isEmpty else { return (s, say([sandbox.feedback.reveal].compactMap { $0 })) }
        return (s, guessLines(s.guesses) + reactionPromptLines(sandbox))
    }

    func sandboxReact(_ state: SandboxState, _ id: String) -> (SandboxState, [SpeechLine])? {
        guard let sandbox = sandboxBeat, !state.guesses.isEmpty, sandbox.reactions.contains(where: { $0.id == id }) else { return nil }
        var s = state
        switch sandbox.scoring {
        case .open:
            guard s.reaction == nil else { return nil }
            s.reaction = id
            // 多卡主題：兩張都玩完才念一次揭曉句（D37）
            return (s, unplayedChoices(s).isEmpty ? say([sandbox.feedback.reveal].compactMap { $0 }) : [])
        case .graded(let right, let wrong):
            guard s.graded == nil, !s.disabled.contains(id) else { return nil }
            let correct = s.guesses[0].truth == "right" ? right : wrong
            if id == correct {
                s.reaction = id
                s.graded = .success
                return (s, say([sandbox.feedback.success].compactMap { $0 }))
            }
            if id != right && id != wrong {
                // 「我不確定」：第一次不算答錯、不變淡；同一張卡第二次直接揭曉（D40）
                s.unsureTaps += 1
                return s.unsureTaps >= 2 ? reveal(s, id, correct, sandbox) : (s, say([sandbox.feedback.notYet].compactMap { $0 }))
            }
            s.attempts += 1
            if s.attempts >= sandbox.attempts.max { return reveal(s, id, correct, sandbox) }
            s.disabled.insert(id)
            return (s, say([sandbox.feedback.notYet].compactMap { $0 }))
        }
    }

    private func reveal(_ state: SandboxState, _ id: String, _ correct: String, _ sandbox: SandboxBeat) -> (SandboxState, [SpeechLine]) {
        var s = state
        s.reaction = id
        s.graded = .revealed(correct: correct)
        return (s, say([sandbox.feedback.reveal].compactMap { $0 }))
    }

    /// 這張卡做完了沒（反應完、答對或揭曉、或查不到猜測）。
    func sandboxCardDone(_ s: SandboxState) -> Bool {
        guard s.choiceID != nil else { return false }
        if s.guesses.isEmpty { return true }
        if case .graded = sandboxBeat?.scoring { return s.graded != nil }
        return s.reaction != nil
    }

    func sandboxCanProceed(_ s: SandboxState) -> Bool {
        s.closing || sandboxCardDone(s)
    }

    /// 下一步：同主題的下一張卡 → 下一個主題 → 結語。
    func sandboxNext(_ s: SandboxState) -> (SandboxState, [SpeechLine])? {
        guard let sandbox = sandboxBeat, let definition = sandboxDefinition, let choiceID = s.choiceID else { return nil }
        let played = s.played + [PlayedCard(choiceID: choiceID, guesses: s.guesses, reaction: s.reaction)]
        let sameSlot = SandboxState(slotIndex: s.slotIndex, played: played)
        if !unplayedChoices(sameSlot).isEmpty { return sandboxEnter(sameSlot) }
        if s.slotIndex + 1 < definition.slots.count { return sandboxEnter(SandboxState(slotIndex: s.slotIndex + 1)) }
        var closing = s
        closing.closing = true
        return (closing, say([sandbox.closingLine]))
    }

    func sandboxReplay(_ s: SandboxState) -> [SpeechLine] {
        guard let sandbox = sandboxBeat else { return [] }
        if s.closing { return say([sandbox.closingLine]) }
        if s.choiceID == nil {
            let remaining = unplayedChoices(s)
            return (s.played.isEmpty ? say([sandbox.prompt]) : []) + labelLines(remaining.map { ($0.id, $0.label) })
        }
        if s.guesses.isEmpty { return say([sandbox.feedback.reveal].compactMap { $0 }) }
        switch s.graded {
        case .success?: return say([sandbox.feedback.success].compactMap { $0 })
        case .revealed?: return say([sandbox.feedback.reveal].compactMap { $0 })
        case nil: break
        }
        if s.reaction != nil, unplayedChoices(s).isEmpty { return say([sandbox.feedback.reveal].compactMap { $0 }) }
        return guessLines(s.guesses) + reactionPromptLines(sandbox)
    }

    /// 反應題，接著依序念出每個反應（孩子不用識字也知道每顆是什麼）。
    private func reactionPromptLines(_ sandbox: SandboxBeat) -> [SpeechLine] {
        say([sandbox.reactionPrompt]) + labelLines(sandbox.reactions.map { ($0.id, $0.label) })
    }

    func guessLines(_ guesses: [Guess]) -> [SpeechLine] {
        guesses.flatMap { guess -> [SpeechLine] in
            guard guess.text.audience == .child else { return [] }
            var lines = [SpeechLine(text: guess.text.zhHant, role: .aiPersona, pauseAfter: 0.3)]
            if guess.uncertainty == .unsure { lines.append(SpeechLine(text: EngineText.unsure, role: .aiPersona)) }
            return lines
        }
    }
}
