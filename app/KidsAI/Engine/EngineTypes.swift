import Foundation

/// 誰在說（決定語速、音高與顯示在哪個角色的框裡）。
enum VoiceRole: Equatable, Sendable {
    case narrator          // 點點
    case aiPersona         // 猜猜帽
    case readAlong         // 一起說：較慢的目標句
    case sound(key: String) // 第 1 關的聲音（暫以語音念 sound_script）
}

/// 一句要念的話。`highlight` 是念這句時要標出的選項 id；`pauseBefore` 讓孩子準備（一起說）。
struct SpeechLine: Equatable, Sendable {
    let text: String
    let role: VoiceRole
    var pauseAfter: Double = 0.4
    var highlight: String? = nil
    var pauseBefore: Double = 0
}

enum EngineEvent: Equatable, Sendable {
    case next
    case select(String)
    case sayTogether
    case pickCard(String)
    case react(String)
    case chooseStory(String)
    // 拖曳（點和拖用同一組事件）
    case dragSelect(String)
    case dragPlace(item: String, target: String)
    case dragReturn(String)
    case dragTapTarget(String)
    case dragCheck
    /// 選起的卡太久沒動作：自動放下選取（不移動任何卡）。
    case dragDeselect
}

enum AnswerOutcome: Equatable, Sendable {
    case success(selected: String)
    case revealed(selected: String, correct: [String])
}

struct QuestionState: Equatable, Sendable {
    var index: Int = 0
    var attempts: Int = 0
    var disabled: Set<String> = []
    var outcome: AnswerOutcome?
}

/// 一個主題裡已經玩過的卡（單元 2 的「兩張卡都玩」，D37）。
struct PlayedCard: Equatable, Sendable {
    let choiceID: String
    let guesses: [Guess]
    let reaction: String?
}

enum GradedOutcome: Equatable, Sendable {
    case success
    case revealed(correct: String)
}

struct SandboxState: Equatable, Sendable {
    var slotIndex: Int = 0
    var choiceID: String?
    var guesses: [Guess] = []
    var reaction: String?
    var closing = false
    /// 同一主題先前玩過的卡；換主題清空。
    var played: [PlayedCard] = []
    /// 有對錯的沙盒：每張卡各自計次，換卡歸零。
    var attempts = 0
    var disabled: Set<String> = []
    /// 按「我不確定」的次數：第一次不算答錯，第二次直接揭曉（D40）。
    var unsureTaps = 0
    var graded: GradedOutcome?
}

/// 拖曳的目標：配對的空格、分組的組、排序的第幾格。
struct DragTarget: Equatable, Sendable {
    let id: String
    let label: TextItem?
    let image: String?
    /// 排序的第幾格（從 1 開始）；配對與分組是 nil。
    let position: Int?
    /// 一格只放一張（配對、排序）；分組可以放很多張。
    let holdsOne: Bool
}

enum DragOutcome: Equatable, Sendable {
    case success
    case revealed
}

struct DragState: Equatable, Sendable {
    /// 卡片 id → 目標 id；沒有的在卡片區。
    var placements: [String: String] = [:]
    var selected: String?
    /// 檢查後放對、固定住的卡：可以點來聽，不能移動。
    var fixed: Set<String> = []
    /// 上次檢查被退回卡片區的卡（短暫標示「再試一次」）。
    var returned: Set<String> = []
    var attempts = 0
    var outcome: DragOutcome?
}

enum Phase: Equatable, Sendable {
    case lines                 // 開場、儀式
    case question(QuestionState)
    case sayTogether(done: Bool)
    case sandbox(SandboxState)
    case drag(DragState)
    case story(nodeID: String)
    case sticker
    case finished
}

enum EngineText {
    /// schema 規定 unsure 要「顯示並念出我不確定」；這是引擎唯一寫死的文案。
    static let unsure = "我不確定"
}
