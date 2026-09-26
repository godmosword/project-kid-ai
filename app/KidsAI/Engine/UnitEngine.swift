import Foundation

/// 單元的狀態機：純值，輸入事件 → 新狀態＋要念的話。不碰畫面與語音，可完整單元測試。
struct UnitEngine: Sendable {
    let content: UnitContent
    private(set) var beatIndex = 0
    private(set) var phase: Phase = .lines

    init(content: UnitContent) {
        self.content = content
    }

    var beat: Beat { content.unit.beats[beatIndex] }

    /// 本版還不能玩的功能（D29'）。空陣列代表這個單元可以玩。
    static func unsupported(_ content: UnitContent) -> [String] {
        content.unit.beats.compactMap(unsupportedFeature)
    }

    private static func unsupportedFeature(_ beat: Beat) -> String? {
        switch beat.kind {
        case .drag:
            return "拖曳"
        case .sandbox(let sandbox) where sandbox.scoring != .open:
            return "有對錯的沙盒"
        case .asr(let asr):
            if case .byOption = asr.target { return "依選擇決定的跟讀句" }
            return nil
        default:
            return nil
        }
    }

    // MARK: - 開始與前進

    mutating func start() -> [SpeechLine] {
        beatIndex = 0
        return enterBeat()
    }

    /// 現在能不能按「下一步」。
    var canProceed: Bool {
        switch phase {
        case .lines, .sticker: true
        case .question(let q): q.outcome != nil
        case .sayTogether(let done): done
        case .sandbox(let s): s.closing || s.reaction != nil || (s.choiceID != nil && s.guesses.isEmpty)
        case .story(let id): storyNode(id).map { if case .choices = $0.exit { false } else { true } } ?? true
        case .finished: false
        }
    }

    mutating func send(_ event: EngineEvent) -> [SpeechLine] {
        switch (phase, event) {
        case (_, .next) where canProceed: advance()
        case (.question(var q), .select(let id)): answer(&q, id)
        case (.sayTogether, .sayTogether): readAlong()
        case (.sandbox(var s), .pickCard(let id)): pick(&s, id)
        case (.sandbox(var s), .react(let id)): react(&s, id)
        case (.story(let id), .chooseStory(let choice)): chooseStory(at: id, choice)
        default: []
        }
    }

    private mutating func advance() -> [SpeechLine] {
        switch phase {
        case .question(let q) where q.index + 1 < questionCount:
            phase = .question(QuestionState(index: q.index + 1))
            return questionPrompt()
        case .sandbox(let s) where !s.closing:
            return nextSlot(after: s)
        case .story(let id):
            if let node = storyNode(id), case .next(let next) = node.exit { return enterNode(next) }
        case .sticker:
            phase = .finished
            return []
        default:
            break
        }
        guard beatIndex + 1 < content.unit.beats.count else {
            phase = .finished
            return []
        }
        beatIndex += 1
        return enterBeat()
    }

    private mutating func enterBeat() -> [SpeechLine] {
        switch beat.kind {
        case .intro(let lines), .ritual(let lines):
            phase = .lines
            return say(lines)
        case .choice, .review:
            phase = .question(QuestionState())
            return questionPrompt()
        case .asr(let asr):
            phase = .sayTogether(done: false)
            return say([asr.prompt] + asr.sayTogether.lines)
        case .sandbox:
            return enterSlot(SandboxState())
        case .story(let ref):
            return enterNode(content.story(ref)?.start ?? "")
        case .sticker(_, let lines):
            phase = .sticker
            return say(lines)
        case .drag:
            phase = .lines
            return []
        }
    }

    // MARK: - 選擇題與回顧

    /// 目前這題（選擇題本身，或回顧的第幾題）。
    struct Question {
        let prompt: TextItem
        let options: [Option]
        let correct: [String]?
        let feedback: Feedback
        let maxAttempts: Int
        let hint: TextItem?
        let stage: Stage?
    }

    var question: Question? {
        guard case .question(let q) = phase else { return nil }
        switch beat.kind {
        case .choice(let c):
            let correct: [String]? = if case .graded(let ids) = c.scoring { ids } else { nil }
            return Question(prompt: c.prompt, options: c.options, correct: correct, feedback: c.feedback,
                            maxAttempts: c.attempts.max, hint: c.hint, stage: c.stage)
        case .review(let questions):
            let r = questions[q.index]
            return Question(prompt: r.prompt, options: r.options, correct: r.correct, feedback: r.feedback,
                            maxAttempts: r.attempts.max, hint: nil, stage: nil)
        default:
            return nil
        }
    }

    private var questionCount: Int {
        if case .review(let questions) = beat.kind { return questions.count }
        return 1
    }

    /// 題目＋（有聲音的選項）依序播放三段聲音。🔊 重念也用這個。
    func questionPrompt() -> [SpeechLine] {
        guard let question else { return [] }
        let sounds = question.options.compactMap { option in
            option.soundScript.map { SpeechLine(text: $0, role: .sound(key: option.sound ?? ""), pauseAfter: 0.6, highlight: option.id) }
        }
        return say([question.prompt]) + sounds
    }

    private mutating func answer(_ q: inout QuestionState, _ id: String) -> [SpeechLine] {
        guard let question, q.outcome == nil, !q.disabled.contains(id), question.options.contains(where: { $0.id == id }) else { return [] }
        defer { phase = .question(q) }
        guard let correct = question.correct else {
            q.outcome = .revealed(selected: id, correct: [])
            return say([question.feedback.reveal].compactMap { $0 })
        }
        if correct.contains(id) {
            q.outcome = .success(selected: id)
            return say([question.feedback.success].compactMap { $0 })
        }
        q.attempts += 1
        if q.attempts >= question.maxAttempts {
            q.outcome = .revealed(selected: id, correct: correct)
            return say([question.feedback.reveal].compactMap { $0 })
        }
        q.disabled.insert(id)
        let replay = questionPrompt().filter { $0.highlight != nil }
        return say([question.feedback.notYet].compactMap { $0 }) + replay
    }

    // MARK: - 一起說

    /// 只念目標句；開念前停 0.5 秒讓孩子準備。做完後可以再按一次。
    private mutating func readAlong() -> [SpeechLine] {
        guard case .asr(let asr) = beat.kind, case .line(let line) = asr.target else { return [] }
        phase = .sayTogether(done: true)
        return [SpeechLine(text: line.zhHant, role: .readAlong, pauseAfter: 0.6, pauseBefore: 0.5)]
    }

    // MARK: - 沙盒

    var sandboxBeat: SandboxBeat? {
        if case .sandbox(let s) = beat.kind { return s }
        return nil
    }

    var sandboxDefinition: SandboxDefinition? {
        sandboxBeat.flatMap { content.sandbox($0.sandboxRef) }
    }

    private mutating func enterSlot(_ state: SandboxState) -> [SpeechLine] {
        var s = state
        phase = .sandbox(s)
        guard let sandbox = sandboxBeat, let definition = sandboxDefinition, s.slotIndex < definition.slots.count else { return [] }
        let slot = definition.slots[s.slotIndex]
        // 主題只有一張卡時直接選好，也不念「選一張卡」（孩子沒有卡可選）
        guard slot.choices.count == 1, let only = slot.choices.first else { return say([sandbox.prompt]) }
        return pick(&s, only.id)
    }

    private mutating func pick(_ s: inout SandboxState, _ choiceID: String) -> [SpeechLine] {
        guard s.choiceID == nil, let sandbox = sandboxBeat, let definition = sandboxDefinition else { return [] }
        let slot = definition.slots[s.slotIndex]
        guard slot.choices.contains(where: { $0.id == choiceID }) else { return [] }
        let request = SandboxRequest(sandboxID: definition.id, slotID: slot.id, structuredChoice: choiceID)
        s.choiceID = choiceID
        // 缺猜測庫等同查不到：走揭曉句，不卡住
        s.guesses = content.banks[definition.id].map { SandboxLookup.guesses(for: request, definition: definition, bank: $0) } ?? []
        phase = .sandbox(s)
        // 查不到合格的猜測：念揭曉句繼續，不卡住
        guard !s.guesses.isEmpty else { return say([sandbox.feedback.reveal].compactMap { $0 }) }
        return guessLines(s.guesses) + say([sandbox.reactionPrompt])
    }

    private func guessLines(_ guesses: [Guess]) -> [SpeechLine] {
        guesses.flatMap { guess -> [SpeechLine] in
            var lines = [SpeechLine(text: guess.text.zhHant, role: .aiPersona, pauseAfter: 0.3)]
            if guess.uncertainty == .unsure { lines.append(SpeechLine(text: EngineText.unsure, role: .aiPersona)) }
            return lines
        }
    }

    private mutating func react(_ s: inout SandboxState, _ id: String) -> [SpeechLine] {
        guard let sandbox = sandboxBeat, s.reaction == nil, !s.guesses.isEmpty, sandbox.scoring == .open,
              sandbox.reactions.contains(where: { $0.id == id }) else { return [] }
        s.reaction = id
        phase = .sandbox(s)
        return say([sandbox.feedback.reveal].compactMap { $0 })
    }

    private mutating func nextSlot(after s: SandboxState) -> [SpeechLine] {
        guard let sandbox = sandboxBeat, let definition = sandboxDefinition else { return [] }
        if s.slotIndex + 1 < definition.slots.count {
            return enterSlot(SandboxState(slotIndex: s.slotIndex + 1))
        }
        var closing = s
        closing.closing = true
        phase = .sandbox(closing)
        return say([sandbox.closingLine])
    }

    // MARK: - 故事

    func storyNode(_ id: String) -> StoryNode? {
        guard case .story(let ref) = beat.kind else { return nil }
        return content.story(ref)?.node(id)
    }

    private mutating func enterNode(_ id: String) -> [SpeechLine] {
        guard let node = storyNode(id) else {
            phase = .lines
            return []
        }
        phase = .story(nodeID: id)
        return say(node.lines, role: node.speaker == .aiPersona ? .aiPersona : .narrator)
    }

    private mutating func chooseStory(at nodeID: String, _ choiceID: String) -> [SpeechLine] {
        guard let node = storyNode(nodeID), case .choices(let choices) = node.exit,
              let choice = choices.first(where: { $0.id == choiceID }) else { return [] }
        return enterNode(choice.next)
    }

    // MARK: - 重念、跳關（🔊 與觀察員選單用）

    /// 🔊 重念：目前畫面的題目或句子。
    func replayLines() -> [SpeechLine] {
        switch phase {
        case .question: return questionPrompt()
        case .sayTogether:
            guard case .asr(let asr) = beat.kind else { return [] }
            return say([asr.prompt] + asr.sayTogether.lines)
        case .sandbox(let s):
            guard let sandbox = sandboxBeat else { return [] }
            if s.closing { return say([sandbox.closingLine]) }
            if s.reaction != nil || (s.choiceID != nil && s.guesses.isEmpty) { return say([sandbox.feedback.reveal].compactMap { $0 }) }
            if s.choiceID == nil { return say([sandbox.prompt]) }
            return guessLines(s.guesses) + say([sandbox.reactionPrompt])
        case .story(let id):
            guard let node = storyNode(id) else { return [] }
            return say(node.lines, role: node.speaker == .aiPersona ? .aiPersona : .narrator)
        case .lines:
            if case .intro(let lines) = beat.kind { return say(lines) }
            if case .ritual(let lines) = beat.kind { return say(lines) }
            return []
        case .sticker:
            if case .sticker(_, let lines) = beat.kind { return say(lines) }
            return []
        case .finished:
            return []
        }
    }

    /// 觀察員選單：直接跳到第幾個 beat。
    mutating func jump(to index: Int) -> [SpeechLine] {
        guard content.unit.beats.indices.contains(index) else { return [] }
        beatIndex = index
        return enterBeat()
    }

    var attemptsUsed: Int {
        if case .question(let q) = phase { return q.attempts }
        return 0
    }

    // MARK: - 小工具

    /// 只念給孩子的文字；家長文字一律不念。
    func say(_ items: [TextItem], role: VoiceRole = .narrator) -> [SpeechLine] {
        items.filter { $0.audience == .child }.map { SpeechLine(text: $0.zhHant, role: role) }
    }
}
