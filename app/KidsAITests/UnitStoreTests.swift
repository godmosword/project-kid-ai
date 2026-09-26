import Testing
@testable import KidsAI

/// 假的念句子：記下每一批；`holdsEachLine` 時每句都停住，等測試呼叫 `finishLine()`。
@MainActor
final class FakeSpeaker: LineSpeaker {
    private(set) var batches: [[SpeechLine]] = []
    var holdsEachLine = false
    private var gate: CheckedContinuation<Void, Never>?
    private var generation = 0

    func speak(_ lines: [SpeechLine], userInitiated: Bool, progress: @escaping (SpeechProgress) -> Void) async {
        stop()
        let mine = generation
        batches.append(lines)
        for index in lines.indices {
            guard mine == generation else { return }
            progress(.line(index))
            if holdsEachLine { await withCheckedContinuation { gate = $0 } }
        }
    }

    func finishLine() {
        let pending = gate
        gate = nil
        pending?.resume()
    }

    func stop() {
        generation += 1
        finishLine()
    }
}

@MainActor
@Suite("畫面狀態：鎖、提示、連點、進背景")
struct UnitStoreTests {
    private let speaker = FakeSpeaker()

    private func store(at beatID: String, hintDelay: Duration = .seconds(60), cooldown: Duration = .seconds(60)) throws -> UnitStore {
        let content = try RepoContent.unit("unit_1_recognize")
        let store = UnitStore(content: content, speaker: speaker, hintDelay: hintDelay, nextCooldown: cooldown)
        let index = try #require(content.unit.beats.firstIndex { $0.id == beatID })
        store.startBeat = index
        store.start()
        return store
    }

    /// 讓排進主執行緒的播放工作跑完。
    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    @Test("連點「下一步」不會跳過儀式")
    func doubleNextDoesNotSkipRitual() async throws {
        let store = try store(at: "u1_gate3_asr")
        await settle()
        store.send(.sayTogether)
        await settle()
        store.send(.next)
        store.send(.next)
        #expect(store.engine.beat.id == "u1_gate4_sandbox_ritual")
        await settle()
        store.send(.next)
        #expect(store.engine.beat.id == "u1_gate4_sandbox_ritual", "冷卻中還不能再前進")
    }

    @Test("冷卻結束、句子念完後可以前進")
    func nextWorksAfterCooldown() async throws {
        let store = try store(at: "u1_gate4_sandbox_ritual", cooldown: .milliseconds(10))
        await settle()
        #expect(store.canShowNext)
        store.send(.next)
        try await Task.sleep(for: .milliseconds(100))
        await settle()
        #expect(store.engine.beat.id == "u1_gate4_sandbox")
    }

    @Test("提示每題只念一次，而且留在畫面上")
    func hintPlaysOnce() async throws {
        let store = try store(at: "u1_gate1_listen", hintDelay: .milliseconds(20))
        let hint = try #require(store.engine.question?.hint?.zhHant)
        try await Task.sleep(for: .milliseconds(300))
        await settle()
        #expect(speaker.batches.filter { $0.contains { $0.text == hint } }.count == 1)
        #expect(store.hintShown)
    }

    @Test("答錯後只鎖「再聽一次」那句，後面的聲音不鎖")
    func notYetLocksFirstLineOnly() async throws {
        speaker.holdsEachLine = true
        let store = try store(at: "u1_gate1_listen")
        await settle()
        store.send(.select("family"))
        await settle()
        #expect(store.inputLocked)
        speaker.finishLine()
        await settle()
        #expect(!store.inputLocked)
        #expect(store.isNarrating)
    }

    @Test("聲音播過之後，卡上會寫出聲音裡的話")
    func heardSoundsAreShown() async throws {
        let store = try store(at: "u1_gate1_listen")
        await settle()
        #expect(["family", "toy", "ai"].allSatisfy(store.hasHeard))
    }

    @Test("進背景時解除鎖定；回來補念被打斷的回饋")
    func resumeReplaysInterruptedLines() async throws {
        speaker.holdsEachLine = true
        let store = try store(at: "u1_gate2_box")
        await settle()
        store.send(.select("car"))
        await settle()
        #expect(store.inputLocked)
        store.pause()
        #expect(!store.inputLocked && !store.isNarrating)
        store.resume()
        await settle()
        #expect(speaker.batches.last?.map(\.text) == ["你和 AI 都會猜，有時對有時錯。"])
    }

    @Test("無效的點擊不會打斷旁白")
    func invalidTapKeepsNarrating() async throws {
        speaker.holdsEachLine = true
        let store = try store(at: "u1_intro")
        await settle()
        let before = speaker.batches.count
        store.send(.select("nothing"))
        await settle()
        #expect(store.isNarrating)
        #expect(speaker.batches.count == before)
    }
}
