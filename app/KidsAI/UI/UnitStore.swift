import Foundation
import Observation

/// 畫面狀態：持有引擎、負責念出引擎給的句子。進度只在記憶體（D30）。
/// 要念的字一律由引擎狀態畫在畫面上（CRITICAL-9），這裡只管念、鎖與提示。
@MainActor
@Observable
final class UnitStore {
    /// 作答後鎖到哪裡：整段回饋，或只鎖第一句（「再聽一次」後面的聲音不鎖）。
    private enum Lock { case none, firstLine, all }

    private(set) var engine: UnitEngine
    /// 正在念、或最後念過的一句。
    private(set) var caption: SpeechLine?
    private(set) var isNarrating = false
    /// 作答後鎖住輸入，直到回饋念完（防連點）。
    private(set) var inputLocked = false
    /// 按了「下一步」之後短暫冷卻，連點不會跳過下一個畫面。
    private(set) var coolingDown = false
    /// 一起說：目標句念到第幾個字（UTF-16 位置），逐字亮起用。
    private(set) var readAlongProgress: Int?
    let startedAt = ContinuousClock.now
    /// 截圖驗證用：從第幾關開始（只在 Debug 的啟動參數設定）。
    var startBeat: Int?

    private let speaker: any LineSpeaker
    private let hintDelay: Duration
    private let nextCooldown: Duration
    private var playToken = 0
    private var cooldownToken = 0
    private var hintTask: Task<Void, Never>?
    /// 每一題的提示只念一次；已經念過（畫面上也會留著）的題目。
    private var hintedQuestions: Set<String> = []
    /// 已經播過的聲音卡（播過就把聲音裡的話寫在卡上）。
    private var heardSounds: Set<String> = []
    private var batch: [SpeechLine] = []
    private var batchIndex = 0
    /// 進背景時被打斷、回來要補念的句子。
    private var interrupted: [SpeechLine] = []

    init(content: UnitContent, speaker: any LineSpeaker,
         hintDelay: Duration = .seconds(8), nextCooldown: Duration = .milliseconds(800)) {
        engine = UnitEngine(content: content)
        self.speaker = speaker
        self.hintDelay = hintDelay
        self.nextCooldown = nextCooldown
    }

    var phase: Phase { engine.phase }
    var canShowNext: Bool { engine.canProceed && !isNarrating && !inputLocked && !coolingDown }
    var speakingHighlight: String? { isNarrating ? caption?.highlight : nil }

    func isSpeaking(_ text: String) -> Bool { isNarrating && caption?.text == text }
    var hintShown: Bool { questionKey.map(hintedQuestions.contains) ?? false }
    func hasHeard(_ optionID: String) -> Bool { questionKey.map { heardSounds.contains("\($0)|\(optionID)") } ?? false }

    /// 換畫面的識別：換了就把 VoiceOver 焦點移到題目。
    var screenKey: String {
        switch phase {
        case .question(let q): "\(engine.beatIndex)-q\(q.index)"
        case .sandbox(let s): "\(engine.beatIndex)-s\(s.slotIndex)\(s.closing ? "c" : "")"
        case .story(let id): "\(engine.beatIndex)-\(id)"
        default: "\(engine.beatIndex)"
        }
    }

    private var questionKey: String? {
        guard case .question(let q) = phase else { return nil }
        return "\(engine.beatIndex)-\(q.index)"
    }

    func start() {
        if let startBeat {
            play(engine.jump(to: startBeat))
        } else {
            play(engine.start())
        }
    }

    func send(_ event: EngineEvent) {
        if event == .next {
            guard canShowNext else { return }
        } else {
            guard !inputLocked else { return }
        }
        let before = (engine.beatIndex, engine.phase)
        let lines = engine.send(event)
        // 無效的點擊（已停用的卡、重複的反應）不打斷旁白
        guard !lines.isEmpty || before != (engine.beatIndex, engine.phase) else { return }
        hintTask?.cancel()
        switch event {
        case .next:
            startCooldown()
            play(lines)
        case .select:
            if case .question(let q) = phase, q.outcome == nil {
                play(lines, lock: .firstLine)
            } else {
                play(lines, lock: .all)
            }
        case .sayTogether:
            play(lines, lock: .all, userInitiated: true)
        case .pickCard, .react, .chooseStory:
            play(lines, lock: .all)
        }
    }

    /// 🔊：重念目前的題目或句子。
    func replay() {
        guard !inputLocked else { return }
        play(engine.replayLines(), userInitiated: true)
    }

    /// 單獨重聽某張卡的聲音（和選取分開）。
    func playSound(of option: Option) {
        guard !inputLocked, let script = option.soundScript else { return }
        play([SpeechLine(text: script, role: .sound(key: option.sound ?? ""), highlight: option.id)], userInitiated: true)
    }

    func jump(to index: Int) {
        hintTask?.cancel()
        hintedQuestions = []
        heardSounds = []
        play(engine.jump(to: index))
    }

    /// 離開畫面或進背景：停止旁白、解除鎖定，記下被打斷的句子。
    func pause() {
        hintTask?.cancel()
        if isNarrating, batch.indices.contains(batchIndex) {
            interrupted = Array(batch[batchIndex...])
        }
        playToken += 1
        speaker.stop()
        isNarrating = false
        inputLocked = false
        readAlongProgress = nil
    }

    /// 回到前景：補念被打斷的句子；沒有被打斷就重念目前的畫面。
    func resume() {
        let rest = interrupted
        interrupted = []
        if rest.isEmpty { replay() } else { play(rest) }
    }

    private func play(_ lines: [SpeechLine], lock: Lock = .none, userInitiated: Bool = false) {
        playToken += 1
        let token = playToken
        interrupted = []
        batch = lines
        batchIndex = 0
        readAlongProgress = nil
        guard !lines.isEmpty else {
            speaker.stop()
            finishPlayback()
            return
        }
        isNarrating = true
        inputLocked = lock != .none
        let lockedLines = lock == .firstLine ? 1 : lines.count
        let key = questionKey
        Task {
            await speaker.speak(lines, userInitiated: userInitiated) { progress in
                self.track(progress, in: lines, token: token, lockedLines: lockedLines, questionKey: key)
            }
            // 過期的播放（已被新的取代）不得改動狀態
            guard token == playToken else { return }
            finishPlayback()
        }
    }

    private func track(_ progress: SpeechProgress, in lines: [SpeechLine], token: Int, lockedLines: Int, questionKey key: String?) {
        guard token == playToken else { return }
        switch progress {
        case .line(let index):
            batchIndex = index
            caption = lines[index]
            readAlongProgress = nil
            if index >= lockedLines { inputLocked = false }
            if case .sound = lines[index].role, let key, let id = lines[index].highlight {
                heardSounds.insert("\(key)|\(id)")
            }
        case .word(let range):
            if caption?.role == .readAlong { readAlongProgress = range.upperBound }
        }
    }

    private func finishPlayback() {
        isNarrating = false
        inputLocked = false
        readAlongProgress = nil
        batch = []
        scheduleHint()
    }

    private func startCooldown() {
        cooldownToken += 1
        let token = cooldownToken
        coolingDown = true
        Task { [weak self, nextCooldown] in
            try? await Task.sleep(for: nextCooldown)
            guard let self, token == cooldownToken else { return }
            coolingDown = false
        }
    }

    /// 孩子 8 秒沒動作才念提示；每題只念一次。
    private func scheduleHint() {
        hintTask?.cancel()
        guard case .question(let q) = phase, q.outcome == nil, let hint = engine.question?.hint,
              let key = questionKey, !hintedQuestions.contains(key) else { return }
        let token = playToken
        hintTask = Task { [weak self, hintDelay] in
            try? await Task.sleep(for: hintDelay)
            guard !Task.isCancelled, let self, token == playToken, !inputLocked else { return }
            hintedQuestions.insert(key)
            play(engine.say([hint]))
        }
    }
}
