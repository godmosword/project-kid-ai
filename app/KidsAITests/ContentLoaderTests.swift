import Foundation
import Testing
@testable import KidsAI

/// repo 裡的 content/units（測試直接讀原始檔，和 App 打包的是同一份）。
enum RepoContent {
    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("content/units")

    static func all() throws -> [UnitContent] { try ContentLoader.load(directory: directory) }

    static func unit(_ id: String) throws -> UnitContent {
        try #require(try all().first { $0.unit.id == id })
    }
}

@Suite("內容載入")
struct ContentLoaderTests {
    @Test("repo 裡 4 個單元與猜測庫都能嚴格解碼並通過契約檢查")
    func loadsAllUnits() throws {
        let units = try RepoContent.all()
        #expect(units.map(\.unit.id) == ["unit_1_recognize", "unit_2_prompt", "unit_3_verify", "unit_4_create"])
        #expect(units.allSatisfy { !$0.banks.isEmpty })
    }

    @Test("App 內打包的內容和 repo 一致")
    func bundledMatchesRepo() throws {
        let bundled = try ContentLoader.bundled()
        #expect(bundled == (try RepoContent.all()))
    }

    @Test("核准碼與 pipeline 的算法一致")
    func approvalHashMatchesPipeline() {
        #expect(Approval.hash("我猜今天會出太陽") == "1e789b536e68")
        #expect(Approval.hash("我猜是一隻狐狸") == "6567aff2ccaa")
    }

    @Test("本版只讓單元 1 可玩（D29'）")
    func onlyUnitOnePlayable() throws {
        let units = try RepoContent.all()
        #expect(UnitEngine.unsupported(units[0]).isEmpty)
        #expect(units.dropFirst().allSatisfy { !UnitEngine.unsupported($0).isEmpty })
    }

    @Test("格式錯誤的內容一律失敗", arguments: [
        #"{"id":"b","type":"dance","est_seconds":1}"#,
        #"{"id":"b","type":"intro","est_seconds":1,"lines":[],"emit":["x"]}"#,
        #"{"id":"b","type":"sandbox_ritual","est_seconds":1,"lines":[],"skippable":true}"#,
        #"{"id":"b","type":"sticker","est_seconds":1,"sticker":{"id":"s","label":\#(TestJSON.child),"image":"i","a11y_label":{"zh-Hant":"x"}},"award":"on_all_correct"}"#,
        #"{"id":"b","type":"choice","est_seconds":1,"prompt":\#(TestJSON.child),"options":[],"scoring":"open","correct_option_ids":["a"],"feedback":{"reveal":\#(TestJSON.child)},"max_attempts":1,"after_max":"reveal_and_continue"}"#,
        #"{"id":"b","type":"choice","est_seconds":1,"prompt":\#(TestJSON.child),"options":[],"scoring":"guess","feedback":{"reveal":\#(TestJSON.child)},"max_attempts":1,"after_max":"reveal_and_continue"}"#,
    ])
    func rejectsMalformedBeat(json: String) {
        #expect(throws: (any Error).self) { try JSONDecoder().decode(Beat.self, from: Data(json.utf8)) }
    }

    @Test("故事節點不能同時有 next 與 end")
    func storyNodeNeedsExactlyOneExit() {
        let json = #"{"id":"n","speaker":"narrator","lines":[],"next":"m","end":true}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(StoryNode.self, from: Data(json.utf8)) }
    }

    @Test("家長文字不得帶旁白欄位、孩子文字必須有")
    func textAudienceRules() {
        let parentWithVO = #"{"id":"p","audience":"parent","text":{"zh-Hant":"x"},"vo":"vo/p","vo_status":"tts_placeholder"}"#
        let childWithoutVO = #"{"id":"c","audience":"child","text":{"zh-Hant":"x"}}"#
        #expect(throws: (any Error).self) { try JSONDecoder().decode(TextItem.self, from: Data(parentWithVO.utf8)) }
        #expect(throws: (any Error).self) { try JSONDecoder().decode(TextItem.self, from: Data(childWithoutVO.utf8)) }
    }
}

@Suite("內容的值域與巢狀欄位")
struct ContentBoundsTests {
    private static func choice(maxAttempts: Int = 2, optionExtra: String = "") -> String {
        let option = #"{"id":"a","label":\#(TestJSON.child)\#(optionExtra)}"#
        return #"{"id":"b","type":"choice","est_seconds":5,"prompt":\#(TestJSON.child),"options":[\#(option)],"scoring":"graded","correct_option_ids":["a"],"feedback":{"success":\#(TestJSON.child),"not_yet":\#(TestJSON.child),"reveal":\#(TestJSON.child)},"max_attempts":\#(maxAttempts),"after_max":"reveal_and_continue"}"#
    }

    private func decodes(_ json: String) -> Bool {
        (try? JSONDecoder().decode(Beat.self, from: Data(json.utf8))) != nil
    }

    @Test("巢狀的未定義欄位也會被拒絕")
    func rejectsNestedUnknownField() {
        #expect(decodes(Self.choice()))
        #expect(!decodes(Self.choice(optionExtra: #","color":"red""#)))
    }

    @Test("max_attempts 只能是 1–3")
    func maxAttemptsRange() {
        #expect(decodes(Self.choice(maxAttempts: 3)))
        #expect(!decodes(Self.choice(maxAttempts: 4)))
        #expect(!decodes(Self.choice(maxAttempts: 0)))
    }

    @Test("est_seconds 只能是 1–180")
    func estSecondsRange() {
        #expect(decodes(#"{"id":"b","type":"intro","est_seconds":180,"lines":[]}"#))
        #expect(!decodes(#"{"id":"b","type":"intro","est_seconds":0,"lines":[]}"#))
        #expect(!decodes(#"{"id":"b","type":"intro","est_seconds":181,"lines":[]}"#))
    }

    @Test("有聲音的選項必須有 sound_script 與 a11y_label")
    func soundOptionNeedsLabel() {
        let base = #"{"id":"a","label":\#(TestJSON.child),"sound":"s","sound_script":{"zh-Hant":"我猜"}"#
        #expect((try? JSONDecoder().decode(Option.self, from: Data((base + #","a11y_label":{"zh-Hant":"x"}}"#).utf8))) != nil)
        #expect((try? JSONDecoder().decode(Option.self, from: Data((base + "}").utf8))) == nil)
    }

    @Test("跟讀的 after_attempts 只能是 2")
    func afterAttemptsMustBeTwo() throws {
        let url = RepoContent.directory.appendingPathComponent("unit_1_recognize.json")
        let original = try String(contentsOf: url, encoding: .utf8)
        #expect((try? JSONDecoder().decode(Unit.self, from: Data(original.utf8))) != nil)
        let changed = original.replacingOccurrences(of: #""after_attempts": 2"#, with: #""after_attempts": 3"#)
        #expect(changed != original)
        #expect((try? JSONDecoder().decode(Unit.self, from: Data(changed.utf8))) == nil)
    }

    @Test("每個沙盒定義都要有猜測庫")
    func everySandboxNeedsBank() throws {
        let content = try RepoContent.unit("unit_1_recognize")
        #expect(throws: ContentError.self) { try ContractCheck.verify(UnitContent(unit: content.unit, banks: [:])) }
    }
}

enum TestJSON {
    static let child = #"{"id":"t","audience":"child","text":{"zh-Hant":"字"},"vo":"vo/t","vo_status":"tts_placeholder"}"#
}
