import CryptoKit
import Foundation

struct ContentError: Error, CustomStringConvertible {
    let file: String
    let message: String
    var description: String { "\(file)：\(message)" }
}

/// 一個單元與它的猜測庫。
struct UnitContent: Hashable, Sendable {
    let unit: Unit
    let banks: [String: GuessBank]

    func story(_ id: String) -> Story? { unit.stories.first { $0.id == id } }
    func sandbox(_ id: String) -> SandboxDefinition? { unit.sandboxes.first { $0.id == id } }
}

/// 從資料夾載入 content/units 的 JSON：嚴格解碼，再檢查跨物件引用。
enum ContentLoader {
    /// App 內打包的內容（XcodeGen 以 folder reference 打包成 `units/`）。
    static func bundled() throws -> [UnitContent] {
        guard let url = Bundle.main.url(forResource: "units", withExtension: nil) else {
            throw ContentError(file: "units", message: "App 內找不到內容資料夾")
        }
        return try load(directory: url)
    }

    static func load(directory: URL) throws -> [UnitContent] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        var units: [Unit] = []
        var banks: [GuessBank] = []
        for file in files {
            let data = try Data(contentsOf: file)
            let kind = try JSONDecoder().decode(KindProbe.self, from: data).kind
            do {
                switch kind {
                case "unit": units.append(try JSONDecoder().decode(Unit.self, from: data))
                case "guess_bank": banks.append(try JSONDecoder().decode(GuessBank.self, from: data))
                default: throw ContentError(file: file.lastPathComponent, message: "未知的 kind：\(kind)")
                }
            } catch let error as DecodingError {
                throw ContentError(file: file.lastPathComponent, message: describe(error))
            }
        }
        let contents = try units.map { unit in
            let own = banks.filter { $0.unitID == unit.id }
            let content = UnitContent(unit: unit, banks: Dictionary(uniqueKeysWithValues: own.map { ($0.sandboxID, $0) }))
            try ContractCheck.verify(content)
            return content
        }
        let known = Set(units.map(\.id))
        if let orphan = banks.first(where: { !known.contains($0.unitID) }) {
            throw ContentError(file: orphan.unitID, message: "猜測庫找不到對應的單元")
        }
        return contents.sorted { $0.unit.id < $1.unit.id }
    }

    private struct KindProbe: Decodable { let kind: String }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .dataCorrupted(let context), .keyNotFound(_, let context), .typeMismatch(_, let context), .valueNotFound(_, let context):
            let path = context.codingPath.map { $0.intValue.map(String.init) ?? $0.stringValue }.joined(separator: ".")
            return "\(path)：\(context.debugDescription)"
        @unknown default:
            return "\(error)"
        }
    }
}

/// 猜測的核准碼：zh-Hant 文字（NFC、UTF-8）的 SHA-256 前 12 碼，與 pipeline/content_rules.py 相同。
enum Approval {
    static func hash(_ text: String) -> String {
        let digest = SHA256.hash(data: Data(text.precomposedStringWithCanonicalMapping.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(12).description
    }

    static func isApproved(_ guess: Guess) -> Bool {
        guess.approvedHash == hash(guess.text.zhHant)
    }
}

/// JSON Schema 表達不了、而引擎依賴的引用關係。
enum ContractCheck {
    static func verify(_ content: UnitContent) throws {
        let unit = content.unit
        func fail(_ message: String) -> ContentError { ContentError(file: unit.id, message: message) }
        // 每個沙盒定義都要有猜測庫，引擎才不會在查不到時卡住
        if let orphan = unit.sandboxes.first(where: { content.banks[$0.id] == nil }) {
            throw fail("沙盒 \(orphan.id) 沒有猜測庫")
        }
        for (index, beat) in unit.beats.enumerated() {
            switch beat.kind {
            case .choice(let choice):
                if case .graded(let correct) = choice.scoring, !Set(correct).isSubset(of: choice.options.map(\.id)) {
                    throw fail("\(beat.id) 的正確答案不在選項裡")
                }
            case .review(let questions):
                for question in questions where !Set(question.correct).isSubset(of: question.options.map(\.id)) {
                    throw fail("\(question.id) 的正確答案不在選項裡")
                }
            case .story(let ref):
                guard let story = content.story(ref) else { throw fail("\(beat.id) 找不到故事 \(ref)") }
                try verify(story, fail: fail)
            case .sandbox(let sandbox):
                guard let definition = content.sandbox(sandbox.sandboxRef) else { throw fail("\(beat.id) 找不到沙盒 \(sandbox.sandboxRef)") }
                guard let bank = content.banks[definition.id] else { throw fail("沙盒 \(definition.id) 沒有猜測庫") }
                try verify(bank, definition, fail: fail)
                try verify(sandbox, bank, beatID: beat.id, fail: fail)
            case .drag(let drag):
                try verify(drag, beatID: beat.id, fail: fail)
            case .asr(let asr):
                if case .byOption(let from, let lines) = asr.target {
                    guard let source = unit.beats[..<index].first(where: { $0.id == from }) else {
                        throw fail("\(beat.id) 的 from_beat 必須是前面的 beat")
                    }
                    guard Set(lines.keys) == Set(UnitEngine.optionIDs(of: source)) else {
                        throw fail("\(beat.id) 的跟讀句必須剛好對應 \(from) 的每個選項")
                    }
                }
            default:
                break
            }
        }
    }

    private static func verify(_ story: Story, fail: (String) -> ContentError) throws {
        let ids = Set(story.nodes.map(\.id))
        guard ids.contains(story.start) else { throw fail("故事 \(story.id) 的起點不存在") }
        for node in story.nodes {
            let targets: [String] = switch node.exit {
            case .choices(let choices): choices.map(\.next)
            case .next(let next): [next]
            case .end: []
            }
            if let missing = targets.first(where: { !ids.contains($0) }) { throw fail("故事節點 \(node.id) 指向不存在的 \(missing)") }
        }
    }

    private static func verify(_ bank: GuessBank, _ definition: SandboxDefinition, fail: (String) -> ContentError) throws {
        let choices = Dictionary(uniqueKeysWithValues: definition.slots.map { ($0.id, Set($0.choices.map(\.id))) })
        for guess in bank.guesses where choices[guess.slotID]?.contains(guess.choiceID) != true {
            throw fail("猜測 \(guess.id) 對應到不存在的 slot／選項")
        }
        // 同 pipeline：每張卡至少一筆猜測（多筆可以）
        for slot in definition.slots {
            for choice in slot.choices where !bank.guesses.contains(where: { $0.slotID == slot.id && $0.choiceID == choice.id }) {
                throw fail("沙盒 \(definition.id) 的 \(slot.id)／\(choice.id) 沒有猜測")
            }
        }
    }

    /// 有對錯的沙盒：每筆猜測都有 truth、open 沒有；反應對照指向存在的反應。
    private static func verify(_ sandbox: SandboxBeat, _ bank: GuessBank, beatID: String, fail: (String) -> ContentError) throws {
        let reactions = Set(sandbox.reactions.map(\.id))
        switch sandbox.scoring {
        case .open:
            if bank.guesses.contains(where: { $0.truth != nil }) { throw fail("\(beatID) 沒有對錯，猜測不得有 truth") }
        case .graded(let right, let wrong):
            guard reactions.contains(right), reactions.contains(wrong) else { throw fail("\(beatID) 的 reaction_for_truth 指向不存在的反應") }
            if bank.guesses.contains(where: { $0.truth != "right" && $0.truth != "wrong" }) {
                throw fail("\(beatID) 有對錯，每筆猜測都要有 truth（right／wrong）")
            }
        }
    }

    /// 拖曳：每張卡都有答案、答案指向存在的目標；每個順序都剛好是所有卡各一次。
    private static func verify(_ drag: DragBeat, beatID: String, fail: (String) -> ContentError) throws {
        let items = Set(drag.items.map(\.id))
        switch drag.mode {
        case .match(let targets, let pairs):
            guard Set(pairs.keys) == items, Set(pairs.values).isSubset(of: targets.map(\.id)) else { throw fail("\(beatID) 的配對不完整") }
        case .group(let groups, let assignments):
            guard Set(assignments.keys) == items, Set(assignments.values).isSubset(of: groups.map(\.id)) else { throw fail("\(beatID) 的分組不完整") }
        case .order(let correct, let alternatives):
            for order in [correct] + alternatives where order.count != items.count || Set(order) != items {
                throw fail("\(beatID) 的順序必須剛好包含每張卡各一次")
            }
            // 同 pipeline：不得重複列出同一個順序
            guard Set(([correct] + alternatives).map { $0.joined(separator: "|") }).count == alternatives.count + 1 else {
                throw fail("\(beatID) 重複列出同一個順序")
            }
        }
    }
}
