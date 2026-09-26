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

    private func store(at beatID: String, hintDelay: Duration = .seconds(60), cooldown: Duration = .seconds(60),
                       deselect: Duration = .seconds(3)) throws -> UnitStore {
        let unitID = beatID.hasPrefix("u2_") ? "unit_2_prompt" : "unit_1_recognize"
        let content = try RepoContent.unit(unitID)
        let store = UnitStore(content: content, speaker: speaker, hintDelay: hintDelay, nextCooldown: cooldown,
                              deselectDelay: deselect)
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

    @Test("拖曳：點卡片聽一聽不上鎖；放滿後自動檢查；提示只念一次")
    func dragCheckAndHint() async throws {
        let store = try store(at: "u2_gate2_blanks", hintDelay: .milliseconds(20))
        await settle()
        store.send(.dragSelect("cup_star"))
        #expect(!store.inputLocked)
        store.send(.dragTapTarget("blank_what"))
        store.send(.dragPlace(item: "place_table", target: "blank_where"))
        try await Task.sleep(for: .milliseconds(900))
        await settle()
        guard case .drag(let d) = store.phase else { Issue.record("應該在拖曳"); return }
        #expect(d.outcome == .success)
        let hint = try #require(store.engine.dragBeat?.hint?.zhHant)
        #expect(speaker.batches.filter { $0.contains { $0.text == hint } }.count <= 1)
    }

    @Test("拖曳中或進背景不自動檢查")
    func pauseCancelsCheck() async throws {
        let store = try store(at: "u2_gate2_blanks")
        await settle()
        store.send(.dragPlace(item: "cup_star", target: "blank_what"))
        store.send(.dragPlace(item: "place_table", target: "blank_where"))
        store.pause()
        try await Task.sleep(for: .milliseconds(900))
        guard case .drag(let d) = store.phase else { Issue.record("應該在拖曳"); return }
        #expect(d.outcome == nil && d.attempts == 0)
        let generation = store.beginDrag()
        store.resume()
        try await Task.sleep(for: .milliseconds(900))
        guard case .drag(let still) = store.phase else { Issue.record("應該在拖曳"); return }
        #expect(still.outcome == nil, "手指還拖著時不檢查")
        store.endDrag(generation)
        try await Task.sleep(for: .milliseconds(900))
        await settle()
        guard case .drag(let done) = store.phase else { Issue.record("應該在拖曳"); return }
        #expect(done.outcome == .success)
    }

    @Test("拖到一半進背景或跳關：這次拖曳作廢，放開時不放卡、不檢查（CRITICAL-12）")
    func backgroundInvalidatesDrag() async throws {
        let store = try store(at: "u2_gate2_blanks")
        await settle()
        let generation = store.beginDrag()
        #expect(store.isCurrentDrag(generation))
        store.pause()
        #expect(!store.isCurrentDrag(generation) && !store.isDragging)
        store.endDrag(generation)
        let again = store.beginDrag()
        store.jump(to: 2)
        #expect(!store.isCurrentDrag(again) && !store.isDragging, "跳關也要結束拖曳，捲動才會恢復")
    }

    @Test("全部放好但選著一張卡：先不檢查；太久沒動作就放下選取再檢查")
    func selectionDelaysCheck() async throws {
        let store = try store(at: "u2_gate2_blanks", deselect: .milliseconds(200))
        await settle()
        store.send(.dragPlace(item: "cup_star", target: "blank_what"))
        store.send(.dragPlace(item: "place_table", target: "blank_where"))
        store.send(.dragSelect("cup_star"))
        try await Task.sleep(for: .milliseconds(150))
        guard case .drag(let waiting) = store.phase else { Issue.record("應該在拖曳"); return }
        #expect(waiting.outcome == nil && waiting.selected == "cup_star")
        try await Task.sleep(for: .milliseconds(1200))
        await settle()
        guard case .drag(let done) = store.phase else { Issue.record("應該在拖曳"); return }
        #expect(done.selected == nil && done.outcome == .success)
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
