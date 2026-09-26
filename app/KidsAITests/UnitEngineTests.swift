import Testing
@testable import KidsAI

@Suite("單元 1 流程")
struct UnitEngineTests {
    private func engine() throws -> UnitEngine {
        UnitEngine(content: try RepoContent.unit("unit_1_recognize"))
    }

    /// 前進到指定 beat（每一步都用合法的操作走過去）。
    private func advance(_ e: inout UnitEngine, to beatID: String) {
        var guardCount = 0
        while e.beat.id != beatID, guardCount < 200 {
            guardCount += 1
            solveCurrent(&e)
            _ = e.send(.next)
        }
    }

    private func solveCurrent(_ e: inout UnitEngine) {
        switch e.phase {
        case .question:
            if let q = e.question { _ = e.send(.select((q.correct ?? q.options.map(\.id)).first!)) }
        case .sayTogether(false):
            _ = e.send(.sayTogether)
        case .sandbox(let s) where s.reaction == nil && !s.guesses.isEmpty:
            _ = e.send(.react(e.sandboxBeat!.reactions[0].id))
        case .story(let id):
            if let node = e.storyNode(id), case .choices(let choices) = node.exit { _ = e.send(.chooseStory(choices[0].id)) }
        default:
            break
        }
    }

    @Test("從頭走到尾，每一步都能前進，最後結束")
    func walksWholeUnit() throws {
        var e = try engine()
        var spoken = e.start()
        var steps = 0
        while e.phase != .finished, steps < 300 {
            steps += 1
            solveCurrent(&e)
            spoken += e.send(.next)
        }
        #expect(e.phase == .finished)
        let parentText = e.content.unit.parentCard.zhHant
        #expect(!spoken.contains { $0.text == parentText }, "家長卡不得被念出來")
        #expect(spoken.contains { $0.text == EngineText.unsure && $0.role == .aiPersona })
    }

    @Test("有答案的關：答錯 2 次就揭曉並可繼續，不會卡住")
    func gradedRevealsAfterMaxAttempts() throws {
        var e = try engine()
        _ = e.start()
        advance(&e, to: "u1_gate1_listen")
        #expect(!e.canProceed)
        let first = e.send(.select("family"))
        #expect(first.contains { $0.text == "再聽一次，誰說「我猜」？" })
        #expect(e.send(.select("family")).isEmpty, "已停用的選項不能再算一次")
        _ = e.send(.select("toy"))
        guard case .question(let q) = e.phase else { Issue.record("應該還在題目"); return }
        #expect(q.outcome == .revealed(selected: "toy", correct: ["ai"]))
        #expect(e.canProceed)
    }

    @Test("作答後再點選項不會多算一次（防連點）")
    func ignoresTapsAfterOutcome() throws {
        var e = try engine()
        _ = e.start()
        advance(&e, to: "u1_gate1_listen")
        _ = e.send(.select("ai"))
        #expect(e.send(.select("toy")).isEmpty)
        guard case .question(let q) = e.phase else { Issue.record("應該還在題目"); return }
        #expect(q.outcome == .success(selected: "ai") && q.attempts == 0)
    }

    @Test("第 1 關會依序念三段聲音，並標出念到哪張卡")
    func listenGatePlaysSounds() throws {
        var e = try engine()
        _ = e.start()
        advance(&e, to: "u1_gate1_listen")
        let highlights = e.questionPrompt().compactMap(\.highlight)
        #expect(highlights == ["family", "toy", "ai"])
    }

    @Test("沒有答案的關選一次就揭曉")
    func openChoiceRevealsOnce() throws {
        var e = try engine()
        _ = e.start()
        advance(&e, to: "u1_gate2_box")
        let lines = e.send(.select("car"))
        #expect(lines.map(\.text) == ["你和 AI 都會猜，有時對有時錯。"])
        #expect(e.canProceed)
    }

    @Test("一起說：按嘴巴之前不能前進；按下只念目標句（先停 0.5 秒），可以再按")
    func sayTogether() throws {
        var e = try engine()
        _ = e.start()
        advance(&e, to: "u1_gate3_asr")
        #expect(!e.canProceed)
        #expect(e.send(.next).isEmpty)
        let target = SpeechLine(text: "AI 會猜。", role: .readAlong, pauseAfter: 0.6, pauseBefore: 0.5)
        #expect(e.send(.sayTogether) == [target])
        #expect(e.canProceed)
        #expect(e.send(.sayTogether) == [target], "做完後還能再說一次")
    }

    @Test("沙盒：三張卡都玩一次，最後才念結語（D36）")
    func sandboxPlaysEveryCard() throws {
        var e = try engine()
        _ = e.start()
        advance(&e, to: "u1_gate4_sandbox")
        var slots: [Int] = []
        while case .sandbox(let s) = e.phase, !s.closing {
            slots.append(s.slotIndex)
            #expect(s.guesses.count == 1)
            _ = e.send(.react("seem_wrong"))
            _ = e.send(.next)
        }
        #expect(slots == [0, 1, 2])
        guard case .sandbox(let s) = e.phase else { Issue.record("應該在結語"); return }
        #expect(s.closing)
    }

    @Test("沙盒卡片自動選好時，不念「選一張卡」")
    func sandboxSkipsPickPromptWhenAutoPicked() throws {
        var e = try engine()
        let lines = e.jump(to: try index(of: "u1_gate4_sandbox", in: e))
        let prompt = try #require(e.sandboxBeat?.prompt.zhHant)
        #expect(!lines.contains { $0.text == prompt })
        #expect(lines.first?.role == .aiPersona, "直接由猜猜帽說出猜測")
    }

    @Test("缺猜測庫時念揭曉句並能前進，不會卡住")
    func missingBankDoesNotStall() throws {
        let content = try RepoContent.unit("unit_1_recognize")
        var e = UnitEngine(content: UnitContent(unit: content.unit, banks: [:]))
        let lines = e.jump(to: try index(of: "u1_gate4_sandbox", in: e))
        let reveal = try #require(e.sandboxBeat?.feedback.reveal)
        #expect(lines.map(\.text) == [reveal.zhHant])
        var steps = 0
        while e.beat.id == "u1_gate4_sandbox", steps < 10 {
            steps += 1
            #expect(e.canProceed)
            _ = e.send(.next)
        }
        #expect(e.beat.id == "u1_story")
    }

    @Test("跳回同一關會重新開始，不留下前一次的狀態")
    func jumpReentersFresh() throws {
        var e = try engine()
        let sandbox = try index(of: "u1_gate4_sandbox", in: e)
        _ = e.jump(to: sandbox)
        _ = e.send(.react("seem_wrong"))
        _ = e.send(.next)
        _ = e.jump(to: sandbox)
        guard case .sandbox(let s) = e.phase else { Issue.record("應該在沙盒"); return }
        #expect(s.slotIndex == 0 && s.reaction == nil && s.guesses.count == 1 && !s.closing)
    }

    @Test("沙盒結語時重念的是結語，不是反應題")
    func replayInClosingSaysClosingLine() throws {
        var e = try engine()
        _ = e.jump(to: try index(of: "u1_gate4_sandbox", in: e))
        while case .sandbox(let s) = e.phase, !s.closing {
            _ = e.send(.react("seem_wrong"))
            _ = e.send(.next)
        }
        let closing = try #require(e.sandboxBeat?.closingLine.zhHant)
        #expect(e.replayLines().map(\.text) == [closing])
    }

    private func index(of beatID: String, in e: UnitEngine) throws -> Int {
        try #require(e.content.unit.beats.firstIndex { $0.id == beatID })
    }

    @Test("故事：兩條分歧都能走到結局")
    func storyBranchesReachEnd() throws {
        for first in ["guess_again", "find_myself"] {
            var e = try engine()
            _ = e.start()
            advance(&e, to: "u1_story")
            #expect(e.send(.chooseStory(first)).isEmpty, "起點沒有分歧，不能選")
            _ = e.send(.next)
            _ = e.send(.chooseStory(first))
            _ = e.send(.next)
            _ = e.send(.chooseStory("give_hint"))
            _ = e.send(.chooseStory("hint_bag"))
            guard case .story(let id) = e.phase else { Issue.record("應該在故事"); continue }
            #expect(id == "u1_story_ending")
            _ = e.send(.next)
            #expect(e.beat.id == "u1_review")
        }
    }
}
