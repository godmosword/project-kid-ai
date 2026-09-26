import Foundation
import Observation

/// 畫面狀態：持有引擎、負責念出引擎給的句子。進度只在記憶體（D30）。
/// 要念的字一律由引擎狀態畫在畫面上（CRITICAL-9），這裡只管念、鎖、提示與拖曳的檢查時機。
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
    /// 手指正拖著一張卡（這時停用捲動、不檢查）。
    private(set) var isDragging = false
    let startedAt = ContinuousClock.now
    /// 截圖驗證用：從第幾關開始（只在 Debug 的啟動參數設定）。
    var startBeat: Int?
    #if DEBUG
    /// 截圖驗證用：開場後直接套用的操作（`-events`）。
    var debugEvents: [EngineEvent] = []
    #endif

    private let speaker: any LineSpeaker
    private let hintDelay: Duration
    private let nextCooldown: Duration
    private let checkDelay: Duration
    private let deselectDelay: Duration
    private var playToken = 0
    /// 拖曳的代數：進背景、跳關時加一，讓進行中的拖曳作廢（CRITICAL-12）。
    private var dragGeneration = 0
    private var cooldownToken = 0
    private var hintTask: Task<Void, Never>?
    private var checkTask: Task<Void, Never>?
    /// 每一題的提示只念一次；已經念過（畫面上也會留著）的題目。
    private var hintedKeys: Set<String> = []
    /// 已經播過的聲音卡（播過就把聲音裡的話寫在卡上）。
    private var heardSounds: Set<String> = []
    private var batch: [SpeechLine] = []
    private var batchIndex = 0
    private var batchLock: Lock = .none
    /// 進背景時被打斷、回來要補念的句子與原本的鎖。
    private var interrupted: [SpeechLine] = []
    private var interruptedLock: Lock = .none

    init(content: UnitContent, speaker: any LineSpeaker, hintDelay: Duration = .seconds(8),
         nextCooldown: Duration = .milliseconds(800), checkDelay: Duration = .milliseconds(600),
         deselectDelay: Duration = .seconds(3)) {
        engine = UnitEngine(content: content)
        self.speaker = speaker
        self.hintDelay = hintDelay
        self.nextCooldown = nextCooldown
        self.checkDelay = checkDelay
        self.deselectDelay = deselectDelay
    }

    var phase: Phase { engine.phase }
    var canShowNext: Bool { engine.canProceed && !isNarrating && !inputLocked && !coolingDown }
    var speakingHighlight: String? { isNarrating ? caption?.highlight : nil }

    func isSpeaking(_ text: String) -> Bool { isNarrating && caption?.text == text }
    var hintShown: Bool { interactionKey.map(hintedKeys.contains) ?? false }
    func hasHeard(_ optionID: String) -> Bool { interactionKey.map { heardSounds.contains("\($0)|\(optionID)") } ?? false }

    /// 換畫面的識別：換了就把 VoiceOver 焦點移到題目。
    var screenKey: String {
        switch phase {
        case .question(let q): "\(engine.beatIndex)-q\(q.index)"
        case .sandbox(let s): "\(engine.beatIndex)-s\(s.slotIndex)-\(s.played.count)\(s.closing ? "c" : "")"
        case .story(let id): "\(engine.beatIndex)-\(id)"
        default: "\(engine.beatIndex)"
        }
    }

    /// 有提示、有聲音卡的畫面（選擇題的每一題、拖曳）。
    private var interactionKey: String? {
        switch phase {
        case .question(let q): "\(engine.beatIndex)-\(q.index)"
        case .drag: "\(engine.beatIndex)-drag"
        default: nil
        }
    }

    /// 還沒結算時 8 秒沒動作要念的提示。
    private var pendingHint: TextItem? {
        switch phase {
        case .question(let q) where q.outcome == nil: engine.question?.hint
        case .drag(let d) where d.outcome == nil: engine.dragBeat?.hint
        default: nil
        }
    }

    func start() {
        if let startBeat {
            play(engine.jump(to: startBeat))
        } else {
            play(engine.start())
        }
        #if DEBUG
        applyDebugEvents()
        #endif
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
        checkTask?.cancel()
        switch event {
        case .next:
            startCooldown()
            play(lines)
        case .select, .dragCheck:
            play(lines, lock: answered ? .all : .firstLine)
        case .sayTogether:
            play(lines, lock: .all, userInitiated: true)
        case .pickCard, .react, .chooseStory:
            play(lines, lock: .all)
        case .dragSelect, .dragTapTarget:
            // 點卡片聽一聽是孩子自己按的：不上鎖，下一個動作可以打斷
            play(lines, userInitiated: true)
        case .dragPlace, .dragReturn:
            play(lines)
        case .dragDeselect:
            // 自動放下選取不是孩子的動作：不打斷旁白
            if !isNarrating { scheduleHint() }
        }
        scheduleCheck()
    }

    /// 這一題已經結算（答對或揭曉）。
    private var answered: Bool {
        switch phase {
        case .question(let q): q.outcome != nil
        case .drag(let d): d.outcome != nil
        default: true
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
        checkTask?.cancel()
        cancelDrag()
        hintedKeys = []
        heardSounds = []
        play(engine.jump(to: index))
    }

    // MARK: - 拖曳

    /// 手指開始拖：算孩子有動作（取消提示），也暫停自動檢查。回傳這次拖曳的代數。
    func beginDrag() -> Int {
        isDragging = true
        hintTask?.cancel()
        checkTask?.cancel()
        return dragGeneration
    }

    /// 這次拖曳還有效嗎（進背景、跳關之後就作廢，放開時不放卡）。
    func isCurrentDrag(_ generation: Int) -> Bool {
        generation == dragGeneration && isDragging
    }

    func endDrag(_ generation: Int) {
        guard generation == dragGeneration else { return }
        isDragging = false
        scheduleCheck()
        if !isNarrating { scheduleHint() }
    }

    private func cancelDrag() {
        dragGeneration += 1
        isDragging = false
    }

    /// 全部放好、沒在拖曳時，等一下才檢查；這段時間任何移動都會重新計時（D39）。
    /// 有選起的卡時不檢查；選起後太久沒動作就自動放下選取，再走檢查。
    private func scheduleCheck() {
        checkTask?.cancel()
        guard case .drag(let d) = phase, d.outcome == nil, !isDragging else { return }
        if d.selected != nil {
            checkTask = Task { [weak self, deselectDelay] in
                try? await Task.sleep(for: deselectDelay)
                guard !Task.isCancelled, let self, !isDragging else { return }
                send(.dragDeselect)
            }
            return
        }
        guard engine.dragReadyToCheck(d) else { return }
        checkTask = Task { [weak self, checkDelay] in
            try? await Task.sleep(for: checkDelay)
            guard !Task.isCancelled, let self, !isDragging else { return }
            send(.dragCheck)
        }
    }

    // MARK: - 暫停與回來

    /// 離開畫面或進背景：停止旁白、取消拖曳與檢查、解除鎖定，記下被打斷的句子。
    func pause() {
        hintTask?.cancel()
        checkTask?.cancel()
        cancelDrag()
        if isNarrating, batch.indices.contains(batchIndex) {
            interrupted = Array(batch[batchIndex...])
            interruptedLock = batchLock == .all || (batchLock == .firstLine && batchIndex == 0) ? batchLock : .none
        }
        playToken += 1
        speaker.stop()
        isNarrating = false
        inputLocked = false
        readAlongProgress = nil
    }

    /// 回到前景：補念被打斷的句子（沿用原本的鎖）；沒有被打斷就重念目前的畫面。
    func resume() {
        let rest = interrupted
        interrupted = []
        if rest.isEmpty {
            replay()
        } else {
            play(rest, lock: interruptedLock)
        }
        scheduleCheck()
    }

    // MARK: - 播放

    private func play(_ lines: [SpeechLine], lock: Lock = .none, userInitiated: Bool = false) {
        playToken += 1
        let token = playToken
        interrupted = []
        batch = lines
        batchIndex = 0
        batchLock = lock
        readAlongProgress = nil
        guard !lines.isEmpty else {
            speaker.stop()
            finishPlayback()
            return
        }
        isNarrating = true
        inputLocked = lock != .none
        let lockedLines = lock == .firstLine ? 1 : lines.count
        let key = interactionKey
        Task {
            await speaker.speak(lines, userInitiated: userInitiated) { progress in
                self.track(progress, in: lines, token: token, lockedLines: lockedLines, soundKey: key)
            }
            // 過期的播放（已被新的取代）不得改動狀態
            guard token == playToken else { return }
            finishPlayback()
        }
    }

    private func track(_ progress: SpeechProgress, in lines: [SpeechLine], token: Int, lockedLines: Int, soundKey key: String?) {
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
        guard !isDragging, let hint = pendingHint, let key = interactionKey, !hintedKeys.contains(key) else { return }
        let token = playToken
        hintTask = Task { [weak self, hintDelay] in
            try? await Task.sleep(for: hintDelay)
            guard !Task.isCancelled, let self, token == playToken, !inputLocked, !isDragging else { return }
            hintedKeys.insert(key)
            play(engine.say([hint]))
        }
    }
}

#if DEBUG
/// 截圖驗證用（只在 Debug build）：`-events "place:cup_star:blank_where;check"` 開場後直接套用一串操作，
/// 用來拍「選卡中、答錯退回、揭曉」這些要點擊才看得到的狀態。
extension UnitStore {
    func applyDebugEvents() {
        guard !debugEvents.isEmpty else { return }
        for event in debugEvents { _ = engine.send(event) }
        debugEvents = []
        play([])
    }
}

enum DebugEvents {
    static func parse(_ text: String) -> [EngineEvent] {
        text.split(separator: ";").compactMap { token in
            let parts = token.split(separator: ":").map(String.init)
            switch (parts.first, parts.count) {
            case ("next", 1): return .next
            case ("say", 1): return .sayTogether
            case ("check", 1): return .dragCheck
            case ("select", 2): return .select(parts[1])
            case ("pick", 2): return .pickCard(parts[1])
            case ("react", 2): return .react(parts[1])
            case ("story", 2): return .chooseStory(parts[1])
            case ("dsel", 2): return .dragSelect(parts[1])
            case ("ret", 2): return .dragReturn(parts[1])
            case ("tap", 2): return .dragTapTarget(parts[1])
            case ("place", 3): return .dragPlace(item: parts[1], target: parts[2])
            default: return nil
            }
        }
    }
}
#endif
