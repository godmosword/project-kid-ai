import Foundation
import Testing
@testable import KidsAI

@Suite("沙盒：有對錯、多張卡、依選擇的跟讀")
struct GradedSandboxTests {
    private func engine(_ unitID: String, at beatID: String) throws -> UnitEngine {
        let content = try RepoContent.unit(unitID)
        var e = UnitEngine(content: content)
        _ = e.jump(to: try #require(content.unit.beats.firstIndex { $0.id == beatID }))
        return e
    }

    private func sandbox(_ e: UnitEngine) -> SandboxState? {
        if case .sandbox(let s) = e.phase { return s }
        return nil
    }

    @Test("小狗卡（AI 說錯）：同意算一次答錯並停用，抓到了才對")
    func wrongReactionCountsOnce() throws {
        var e = try engine("unit_3_verify", at: "u3_sandbox")
        #expect(!e.canProceed)
        #expect(e.send(.react("agree")).map(\.text) == ["再看看圖，想一想。"])
        let s = try #require(sandbox(e))
        #expect(s.attempts == 1 && s.disabled == ["agree"] && !e.canProceed)
        #expect(e.send(.react("agree")).isEmpty, "停用的不能再按")
        #expect(e.send(.react("catch")).map(\.text) == ["你對過圖了，真是小偵探。"])
        #expect(sandbox(e)?.graded == .success && e.canProceed)
    }

    @Test("「我不確定」第一次不算答錯、不停用；第二次直接揭曉（D40）")
    func unsureRule() throws {
        var e = try engine("unit_3_verify", at: "u3_sandbox")
        #expect(e.send(.react("not_sure")).map(\.text) == ["再看看圖，想一想。"])
        var s = try #require(sandbox(e))
        #expect(s.attempts == 0 && s.disabled.isEmpty && s.unsureTaps == 1)
        _ = e.send(.react("not_sure"))
        s = try #require(sandbox(e))
        #expect(s.graded == .revealed(correct: "catch") && s.reaction == "not_sure" && e.canProceed)
    }

    @Test("每張卡各自計次，換卡歸零；夜晚卡（AI 說對）要按同意")
    func attemptsResetPerCard() throws {
        var e = try engine("unit_3_verify", at: "u3_sandbox")
        _ = e.send(.react("agree"))
        _ = e.send(.react("catch"))
        _ = e.send(.next)
        let s = try #require(sandbox(e))
        #expect(s.slotIndex == 1 && s.attempts == 0 && s.disabled.isEmpty && s.graded == nil)
        _ = e.send(.react("agree"))
        #expect(sandbox(e)?.graded == .success)
    }

    @Test("反應題念完，依序念出每個反應並標亮")
    func reactionLabelsAreRead() throws {
        let e = try engine("unit_3_verify", at: "u3_sandbox")
        let highlights = e.replayLines().compactMap(\.highlight)
        #expect(highlights == ["agree", "catch", "not_sure"])
    }

    @Test("單元 2：兩張卡都玩；第二張不念 prompt；兩張都玩完才揭曉一次")
    func multiCardSlot() throws {
        var e = try engine("unit_2_prompt", at: "u2_sandbox")
        let prompt = try #require(e.sandboxBeat?.prompt.zhHant)
        let reveal = try #require(e.sandboxBeat?.feedback.reveal?.zhHant)
        #expect(e.replayLines().first?.text == prompt)
        #expect(!e.canProceed, "要先選一張")
        let first = e.send(.pickCard("prompt_vague"))
        #expect(first.contains { $0.text == EngineText.unsure })
        #expect(e.send(.react("closer")).isEmpty, "第一張反應完先不揭曉")
        #expect(e.canProceed)
        let second = e.send(.next)
        #expect(!second.contains { $0.text == prompt })
        #expect(sandbox(e)?.choiceID == "prompt_clear" && sandbox(e)?.played.count == 1)
        #expect(e.send(.react("closer")).map(\.text) == [reveal])
        let closing = e.send(.next)
        #expect(sandbox(e)?.closing == true)
        #expect(!closing.contains { $0.text == reveal } && !e.replayLines().contains { $0.text == reveal }, "揭曉句只念一次")
    }

    @Test("單元 4：跟讀句依最後一次反應；跳關沒紀錄時用反應順序的第一句")
    func readAlongByOption() throws {
        var e = try engine("unit_4_create", at: "u4_sandbox")
        for reaction in ["rescue", "share", "keep_going"] {
            _ = e.send(.react(reaction))
            _ = e.send(.next)
        }
        _ = e.send(.next)
        #expect(e.beat.id == "u4_gate4_asr")
        #expect(e.readAlongLine?.zhHant == "我們不放棄，一直努力。")
        #expect(e.send(.sayTogether).first?.text == "我們不放棄，一直努力。")

        let fresh = try engine("unit_4_create", at: "u4_gate4_asr")
        #expect(fresh.readAlongLine?.zhHant == "我們一起救朋友。")
    }

    @Test("跳關、重玩會清掉記住的選擇")
    func jumpClearsChoices() throws {
        var e = try engine("unit_4_create", at: "u4_sandbox")
        _ = e.send(.react("share"))
        #expect(e.choices["u4_sandbox"] == "share")
        _ = e.jump(to: 0)
        #expect(e.choices.isEmpty)
        _ = e.send(.next)
        _ = e.start()
        #expect(e.choices.isEmpty)
    }
}

@Suite("v2 內容契約")
struct ContractV2Tests {
    private func unitJSON(_ name: String) throws -> String {
        try String(contentsOf: RepoContent.directory.appendingPathComponent(name), encoding: .utf8)
    }

    private func verify(unit: String, bank: String? = nil, unitID: String) throws {
        let decoded = try JSONDecoder().decode(Unit.self, from: Data(unit.utf8))
        let original = try RepoContent.unit(unitID)
        let banks = try bank.map { json -> [String: GuessBank] in
            let b = try JSONDecoder().decode(GuessBank.self, from: Data(json.utf8))
            return [b.sandboxID: b]
        } ?? original.banks
        try ContractCheck.verify(UnitContent(unit: decoded, banks: banks))
    }

    private func replacing(_ text: String, _ old: String, _ new: String) throws -> String {
        let changed = text.replacingOccurrences(of: old, with: new)
        try #require(changed != text, "測試用的取代沒有命中：\(old)")
        return changed
    }

    @Test("拖曳配對不完整會被拒")
    func incompletePairsRejected() throws {
        let json = try unitJSON("unit_2_prompt.json")
        try verify(unit: json, unitID: "unit_2_prompt")
        let broken = try replacing(json, #""pairs": { "cup_star": "blank_what", "place_table": "blank_where" }"#, #""pairs": { "cup_star": "blank_what" }"#)
        #expect(throws: ContentError.self) { try verify(unit: broken, unitID: "unit_2_prompt") }
    }

    @Test("有對錯的沙盒，猜測缺 truth 會被拒")
    func gradedGuessNeedsTruth() throws {
        let unit = try unitJSON("unit_3_verify.json")
        let bank = try replacing(try unitJSON("unit_3_verify.guesses.json"), #""truth": "wrong","#, "")
        #expect(throws: ContentError.self) { try verify(unit: unit, bank: bank, unitID: "unit_3_verify") }
    }

    @Test("排序不得重複列出同一個順序（同 pipeline）")
    func duplicateOrderRejected() throws {
        let json = try unitJSON("unit_4_create.json")
        let broken = try replacing(json, #"["rain", "umbrella", "go_out"]"#, #"["rain", "umbrella", "go_out"], ["rain", "umbrella", "go_out"]"#)
        #expect(throws: ContentError.self) { try verify(unit: broken, unitID: "unit_4_create") }
    }

    @Test("同一張卡有多筆猜測可以通過（單元 4 每個世界三個點子）")
    func multipleGuessesPerChoicePass() throws {
        let content = try RepoContent.unit("unit_4_create")
        let bank = try #require(content.banks.values.first)
        let keys = bank.guesses.map { "\($0.slotID)|\($0.choiceID)" }
        #expect(Set(keys).count < keys.count)
        try ContractCheck.verify(content)
    }

    @Test("依選擇的跟讀句，key 要剛好等於來源的反應")
    func readAlongKeysMatchSource() throws {
        let json = try unitJSON("unit_4_create.json")
        let broken = try replacing(json, #""keep_going": {"#, #""give_up": {"#)
        #expect(throws: ContentError.self) { try verify(unit: broken, unitID: "unit_4_create") }
    }
}
