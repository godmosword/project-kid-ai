import Foundation

/// 單元的狀態機：純值，輸入事件 → 新狀態＋要念的話。不碰畫面與語音，可完整單元測試。
/// 狀態只在這個檔案改；沙盒與拖曳的規則在 `UnitEngine+Sandbox.swift`、`UnitEngine+Drag.swift`，只回傳新狀態。
struct UnitEngine: Sendable {
    let content: UnitContent
    private(set) var beatIndex = 0
    private(set) var phase: Phase = .lines
    /// 本單元每個 beat 最後的選擇（選項或反應 id），給「依選擇的跟讀」用。
    /// 只在記憶體、只存 id；開始、跳關、重玩時清掉（D30）。
    private(set) var choices: [String: String] = [:]

    init(content: UnitContent) {
        self.content = content
    }

    var beat: Beat { content.unit.beats[beatIndex] }

    /// 本版還不能玩的功能。空陣列代表這個單元可以玩。
    static func unsupported(_ content: UnitContent) -> [String] {
        content.unit.beats.compactMap { unsupportedFeature($0, in: content) }
    }

    private static func unsupportedFeature(_ beat: Beat, in content: UnitContent) -> String? {
        switch beat.kind {
        case .sandbox(let sandbox):
            guard case .graded = sandbox.scoring, let definition = content.sandbox(sandbox.sandboxRef),
                  let bank = content.banks[definition.id] else { return nil }
            let keys = bank.guesses.map { "\($0.slotID)|\($0.choiceID)" }
            return Set(keys).count == keys.count ? nil : "有對錯、同一張卡多筆猜測的沙盒"
        case .asr(let asr):
            guard case .byOption(let from, _) = asr.target,
                  let source = content.unit.beats.first(where: { $0.id == from }) else { return nil }
            if case .drag = source.kind { return "依拖曳結果決定的跟讀句" }
            return nil
        default:
            return nil
        }
    }

    // MARK: - 開始與前進

    mutating func start() -> [SpeechLine] {
        beatIndex = 0
        choices = [:]
        return enterBeat()
    }

    /// 現在能不能按「下一步」。
    var canProceed: Bool {
        switch phase {
        case .lines, .sticker: true
        case .question(let q): q.outcome != nil
        case .sayTogether(let done): done
        case .sandbox(let s): sandboxCanProceed(s)
        case .drag(let d): d.outcome != nil
        case .story(let id): storyNode(id).map { if case .choices = $0.exit { false } else { true } } ?? true
        case .finished: false
        }
    }

    mutating func send(_ event: EngineEvent) -> [SpeechLine] {
        switch (phase, event) {
        case (_, .next) where canProceed: return advance()
        case (.question(var q), .select(let id)): return answer(&q, id)
        case (.sayTogether, .sayTogether): return readAlong()
        case (.sandbox(let s), .pickCard(let id)):
            return apply(sandboxPick(s, id))
        case (.sandbox(let s), .react(let id)):
            guard let step = sandboxReact(s, id) else { return [] }
            choices[beat.id] = id
            return apply(step)
        case (.drag(let d), _):
            guard let (next, lines) = dragStep(d, event) else { return [] }
            phase = .drag(next)
            return lines
        case (.story(let id), .chooseStory(let choice)): return chooseStory(at: id, choice)
        default: return []
        }
    }

    private mutating func apply(_ step: (SandboxState, [SpeechLine])?) -> [SpeechLine] {
        guard let (state, lines) = step else { return [] }
        phase = .sandbox(state)
        return lines
    }

    private mutating func advance() -> [SpeechLine] {
        switch phase {
        case .question(let q) where q.index + 1 < questionCount:
            phase = .question(QuestionState(index: q.index + 1))
            return questionPrompt()
        case .sandbox(let s) where !s.closing:
            return apply(sandboxNext(s))
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
            phase = .sandbox(SandboxState())
            return apply(sandboxEnter(SandboxState()))
        case .drag:
            phase = .drag(DragState())
            return dragPrompt()
        case .story(let ref):
            return enterNode(content.story(ref)?.start ?? "")
        case .sticker(_, let lines):
            phase = .sticker
            return say(lines)
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

    /// 題目＋（有聲音的選項）依序播放聲音。🔊 重念也用這個。
    func questionPrompt() -> [SpeechLine] {
        guard let question else { return [] }
        return say([question.prompt]) + soundLines(question.options)
    }

    /// 有聲音的卡依序播放，並標出念到哪一張。
    func soundLines(_ options: [Option]) -> [SpeechLine] {
        options.compactMap { option in
            option.soundScript.map { SpeechLine(text: $0, role: .sound(key: option.sound ?? ""), pauseAfter: 0.6, highlight: option.id) }
        }
    }

    private mutating func answer(_ q: inout QuestionState, _ id: String) -> [SpeechLine] {
        guard let question, q.outcome == nil, !q.disabled.contains(id), question.options.contains(where: { $0.id == id }) else { return [] }
        defer { phase = .question(q) }
        choices[beat.id] = id
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

    /// 這一關要一起說的句子：固定句，或依前面的選擇決定（D38）。
    var readAlongLine: TextItem? {
        guard case .asr(let asr) = beat.kind else { return nil }
        switch asr.target {
        case .line(let line):
            return line
        case .byOption(let from, let lines):
            // 沒有紀錄（例如跳關）時，用來源選項順序的第一句，不靠 Dictionary 的順序
            let order = content.unit.beats.first { $0.id == from }.map(Self.optionIDs) ?? []
            if let chosen = choices[from], let line = lines[chosen] { return line }
            return order.lazy.compactMap { lines[$0] }.first
        }
    }

    /// 一個 beat 可被記住的選項 id（選擇題的選項、沙盒的反應），依內容順序。
    static func optionIDs(of beat: Beat) -> [String] {
        switch beat.kind {
        case .choice(let c): c.options.map(\.id)
        case .sandbox(let s): s.reactions.map(\.id)
        case .drag(let d): d.items.map(\.id)
        default: []
        }
    }

    /// 只念目標句；開念前停 0.5 秒讓孩子準備。做完後可以再按一次。
    private mutating func readAlong() -> [SpeechLine] {
        guard let line = readAlongLine else { return [] }
        phase = .sayTogether(done: true)
        return [SpeechLine(text: line.zhHant, role: .readAlong, pauseAfter: 0.6, pauseBefore: 0.5)]
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
        case .sandbox(let s): return sandboxReplay(s)
        case .drag: return dragPrompt()
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

    /// 觀察員選單：直接跳到第幾個 beat。記住的選擇一併清掉。
    mutating func jump(to index: Int) -> [SpeechLine] {
        guard content.unit.beats.indices.contains(index) else { return [] }
        beatIndex = index
        choices = [:]
        return enterBeat()
    }

    var attemptsUsed: Int {
        switch phase {
        case .question(let q): q.attempts
        case .sandbox(let s): s.attempts
        case .drag(let d): d.attempts
        default: 0
        }
    }

    // MARK: - 小工具

    /// 只念給孩子的文字；家長文字一律不念。
    func say(_ items: [TextItem], role: VoiceRole = .narrator) -> [SpeechLine] {
        items.filter { $0.audience == .child }.map { SpeechLine(text: $0.zhHant, role: role) }
    }

    /// 依序念出每個標籤並標出念到哪一個（選項、反應、目標）。
    func labelLines(_ labels: [(id: String, text: TextItem)]) -> [SpeechLine] {
        labels.filter { $0.text.audience == .child }.map { SpeechLine(text: $0.text.zhHant, role: .narrator, pauseAfter: 0.3, highlight: $0.id) }
    }
}
