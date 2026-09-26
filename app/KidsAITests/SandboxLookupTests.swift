import Foundation
import Testing
@testable import KidsAI

@Suite("沙盒查表（S1／S2）")
struct SandboxLookupTests {
    @Test("請求只有三個欄位")
    func requestHasOnlyThreeFields() {
        let request = SandboxRequest(sandboxID: "s", slotID: "t", structuredChoice: "c")
        #expect(Mirror(reflecting: request).children.map(\.label) == ["sandboxID", "slotID", "structuredChoice"])
    }

    @Test("一個鍵多筆猜測時保持檔案順序（單元 4）")
    func keepsOrderForMultipleGuesses() throws {
        let content = try RepoContent.unit("unit_4_create")
        let definition = try #require(content.unit.sandboxes.first)
        let bank = try #require(content.banks[definition.id])
        let request = SandboxRequest(sandboxID: definition.id, slotID: "world_cars", structuredChoice: "world_cars_card")
        let texts = SandboxLookup.guesses(for: request, definition: definition, bank: bank).map(\.text.zhHant)
        #expect(texts == ["小車卡在泥巴，拉它出來", "小車請大家吃餅乾", "小車爬坡，一直往上"])
    }

    @Test("核准碼對不上、不安全、不在白名單的猜測都被丟棄")
    func dropsUnapprovedOrUnsafe() throws {
        let content = try RepoContent.unit("unit_1_recognize")
        let definition = try #require(content.unit.sandboxes.first)
        let good = try #require(content.banks[definition.id]?.guesses.first)
        let bank = try GuessBank.make(sandboxID: definition.id, guesses: [
            good.json(text: "改過的文字"),       // 核准碼對不上
            good.json(safe: false),             // 不安全（格式上不該出現，App 再防一層）
            good.json(audience: .parent),       // 不是給孩子的文字
        ])
        let request = SandboxRequest(sandboxID: definition.id, slotID: good.slotID, structuredChoice: good.choiceID)
        #expect(SandboxLookup.guesses(for: request, definition: definition, bank: bank).isEmpty)
        let offList = SandboxRequest(sandboxID: definition.id, slotID: good.slotID, structuredChoice: "not_a_card")
        #expect(SandboxLookup.guesses(for: offList, definition: definition, bank: bank).isEmpty)
    }
}

extension Guess {
    /// 以這筆猜測為底，產生一段可調整的 JSON（測試用）。
    func json(text: String? = nil, safe: Bool = true, audience: Audience = .child) -> String {
        let body = text ?? self.text.zhHant
        let voice = audience == .child ? #","vo":"vo/g","vo_status":"tts_placeholder""# : ""
        return """
        {"id":"\(id)","slot_id":"\(slotID)","choice_id":"\(choiceID)",
         "guess_text":{"id":"g","audience":"\(audience.rawValue)","text":{"zh-Hant":"\(body)"}\(voice)},
         "uncertainty_mark":"\(uncertainty.rawValue)","safe":\(safe),"approved_hash":"\(approvedHash ?? "")"}
        """
    }
}

extension GuessBank {
    static func make(sandboxID: String, guesses: [String]) throws -> GuessBank {
        let json = #"{"kind":"guess_bank","schema_version":"1.0.0","unit_id":"unit_1_recognize","sandbox_id":"\#(sandboxID)","guesses":[\#(guesses.joined(separator: ","))]}"#
        return try JSONDecoder().decode(GuessBank.self, from: Data(json.utf8))
    }
}
