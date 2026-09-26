import Testing
@testable import KidsAI

/// 用合法操作玩一關：`correct` 為 true 時都答對，否則盡量答錯（測揭曉後仍能前進）。
/// 每一步都回傳念了哪些句子，才驗證得到「真的走過揭曉」。
enum Solver {
    @discardableResult
    static func solve(_ e: inout UnitEngine, correct: Bool) -> [SpeechLine] {
        switch e.phase {
        case .question(let q):
            guard q.outcome == nil, let question = e.question else { return [] }
            let right = question.correct ?? question.options.map(\.id)
            let wrong = question.options.map(\.id).filter { !right.contains($0) && !q.disabled.contains($0) }
            return e.send(.select((correct ? right.first : wrong.first ?? right.first)!))
        case .sayTogether(false):
            return e.send(.sayTogether)
        case .sandbox(let s):
            return solveSandbox(&e, s, correct: correct)
        case .drag(let d) where d.outcome == nil:
            return solveDrag(&e, correct: correct)
        case .story(let id):
            guard let node = e.storyNode(id), case .choices(let choices) = node.exit else { return [] }
            return e.send(.chooseStory(choices[0].id))
        default:
            return []
        }
    }

    private static func solveSandbox(_ e: inout UnitEngine, _ s: SandboxState, correct: Bool) -> [SpeechLine] {
        guard let sandbox = e.sandboxBeat, !s.closing else { return [] }
        if s.choiceID == nil, let first = e.unplayedChoices(s).first { return e.send(.pickCard(first.id)) }
        guard !e.sandboxCardDone(s) else { return [] }
        switch sandbox.scoring {
        case .open:
            return e.send(.react(sandbox.reactions[0].id))
        case .graded(let right, let wrong):
            let answer = s.guesses[0].truth == "right" ? right : wrong
            let other = answer == right ? wrong : right
            if correct { return e.send(.react(answer)) }
            if !s.disabled.contains(other) { return e.send(.react(other)) }
            // 唯一的錯答已停用：連按「我不確定」兩次走到揭曉（D40）
            let unsure = sandbox.reactions.first { $0.id != right && $0.id != wrong }
            return e.send(.react(unsure?.id ?? answer))
        }
    }

    private static func solveDrag(_ e: inout UnitEngine, correct: Bool) -> [SpeechLine] {
        guard let drag = e.dragBeat else { return [] }
        let answer = e.canonicalPlacements(drag)
        let ids = drag.items.map(\.id)
        var spoken: [SpeechLine] = []
        for (index, item) in ids.enumerated() {
            guard case .drag(let d) = e.phase, d.placements[item] == nil else { continue }
            // 答錯：放到下一張卡的答案位置（錯開一格，不會互相交換）
            let preferred = correct ? answer[item]! : answer[ids[(index + 1) % ids.count]]!
            spoken += e.send(.dragPlace(item: item, target: preferred))
            guard case .drag(let after) = e.phase, after.placements[item] == nil else { continue }
            // 那格已被固定的卡佔住：改放任何一個空位
            let free = e.dragTargets.first { t in !t.holdsOne || !after.placements.values.contains(t.id) }
            if let free { spoken += e.send(.dragPlace(item: item, target: free.id)) }
        }
        return spoken + e.send(.dragCheck)
    }

    /// 從頭玩到結束，回傳念過的所有句子。
    static func playThrough(_ content: UnitContent, correct: Bool) -> (UnitEngine, [SpeechLine]) {
        var e = UnitEngine(content: content)
        var spoken = e.start()
        var steps = 0
        while e.phase != .finished, steps < 500 {
            steps += 1
            if !e.canProceed { spoken += solve(&e, correct: correct) }
            spoken += e.send(.next)
        }
        return (e, spoken)
    }
}

@Suite("四個單元都能玩完")
struct UnitsWalkthroughTests {
    @Test("本版 4 個單元都可以玩")
    func allUnitsPlayable() throws {
        for content in try RepoContent.all() {
            #expect(UnitEngine.unsupported(content).isEmpty, "\(content.unit.id)：\(UnitEngine.unsupported(content))")
        }
    }

    @Test("都答對：每個單元都能從頭走到尾，家長卡不念", arguments: ["unit_1_recognize", "unit_2_prompt", "unit_3_verify", "unit_4_create"])
    func correctPath(unitID: String) throws {
        let content = try RepoContent.unit(unitID)
        let (e, spoken) = Solver.playThrough(content, correct: true)
        #expect(e.phase == .finished)
        #expect(!spoken.contains { $0.text == content.unit.parentCard.zhHant })
    }

    @Test("一直答錯：揭曉後仍能前進，走到尾", arguments: ["unit_1_recognize", "unit_2_prompt", "unit_3_verify", "unit_4_create"])
    func wrongPath(unitID: String) throws {
        let content = try RepoContent.unit(unitID)
        let (e, spoken) = Solver.playThrough(content, correct: false)
        #expect(e.phase == .finished)
        // 真的走過揭曉：每個拖曳與有對錯的沙盒都念過揭曉句
        for beat in content.unit.beats {
            switch beat.kind {
            case .drag(let drag):
                #expect(spoken.contains { $0.text == drag.feedback.reveal?.zhHant }, "\(beat.id) 沒有揭曉")
            case .sandbox(let sandbox) where sandbox.scoring != .open:
                #expect(spoken.contains { $0.text == sandbox.feedback.reveal?.zhHant }, "\(beat.id) 沒有揭曉")
            default:
                break
            }
        }
    }
}
