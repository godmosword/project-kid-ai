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

struct SandboxState: Equatable, Sendable {
    var slotIndex: Int = 0
    var choiceID: String?
    var guesses: [Guess] = []
    var reaction: String?
    var closing = false
}

enum Phase: Equatable, Sendable {
    case lines                 // 開場、儀式
    case question(QuestionState)
    case sayTogether(done: Bool)
    case sandbox(SandboxState)
    case story(nodeID: String)
    case sticker
    case finished
}

enum EngineText {
    /// schema 規定 unsure 要「顯示並念出我不確定」；這是引擎唯一寫死的文案。
    static let unsure = "我不確定"
}
