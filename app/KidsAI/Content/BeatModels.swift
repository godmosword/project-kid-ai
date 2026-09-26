import Foundation

// 各種 beat。先讀 type，再依 case 解碼；每個 case 只接受自己定義的欄位。

struct Attempts: Hashable, Sendable {
    let max: Int

    init(_ c: StrictContainer) throws {
        max = try c.required("max_attempts")
        guard (1...3).contains(max) else { throw c.fail("max_attempts 必須是 1–3") }
        guard try c.required("after_max") as String == "reveal_and_continue" else { throw c.fail("after_max 只能是 reveal_and_continue") }
    }
}

enum ChoiceScoring: Hashable, Sendable {
    case graded(correct: [String])
    case open
}

struct ChoiceBeat: Hashable, Sendable {
    static let keys: Set<String> = ["prompt", "hint", "stage", "options", "scoring", "correct_option_ids", "feedback", "max_attempts", "after_max"]
    let prompt: TextItem
    let hint: TextItem?
    let stage: Stage?
    let options: [Option]
    let scoring: ChoiceScoring
    let feedback: Feedback
    let attempts: Attempts

    init(_ c: StrictContainer) throws {
        prompt = try c.required("prompt")
        hint = try c.optional("hint")
        stage = try c.optional("stage")
        options = try c.required("options")
        attempts = try Attempts(c)
        switch try c.required("scoring") as String {
        case "graded":
            scoring = .graded(correct: try c.required("correct_option_ids"))
            feedback = try Feedback.graded(c)
        case "open":
            try c.forbid(["correct_option_ids"])
            guard attempts.max == 1 else { throw c.fail("沒有標準答案的關只能選一次") }
            scoring = .open
            feedback = try Feedback.open(c)
        default:
            throw c.fail("未知的 scoring")
        }
    }
}

enum DragMode: Hashable, Sendable {
    case match(targets: [Option], pairs: [String: String])
    case order(correct: [String], alternatives: [[String]])
    case group(groups: [Option], assignments: [String: String])
}

struct DragBeat: Hashable, Sendable {
    static let keys: Set<String> = ["prompt", "hint", "mode", "items", "targets", "pairs", "correct_order", "alt_orders",
                                    "groups", "assignments", "feedback", "max_attempts", "after_max"]
    let prompt: TextItem
    let hint: TextItem?
    let items: [Option]
    let mode: DragMode
    let feedback: Feedback
    let attempts: Attempts

    init(_ c: StrictContainer) throws {
        prompt = try c.required("prompt")
        hint = try c.optional("hint")
        items = try c.required("items")
        feedback = try Feedback.graded(c)
        attempts = try Attempts(c)
        switch try c.required("mode") as String {
        case "match":
            try c.forbid(["correct_order", "alt_orders", "groups", "assignments"])
            mode = .match(targets: try c.required("targets"), pairs: try c.required("pairs"))
        case "order":
            try c.forbid(["targets", "pairs", "groups", "assignments"])
            mode = .order(correct: try c.required("correct_order"), alternatives: try c.optional("alt_orders") ?? [])
        case "group":
            try c.forbid(["targets", "pairs", "correct_order", "alt_orders"])
            mode = .group(groups: try c.required("groups"), assignments: try c.required("assignments"))
        default:
            throw c.fail("未知的 drag mode")
        }
    }
}

struct FallbackPath: Hashable, Sendable {
    let lines: [TextItem]

    static func decode(_ c: StrictContainer, key: String, mode expected: String, attemptsKey: Bool) throws -> FallbackPath {
        let allowed: Set<String> = attemptsKey ? ["mode", "lines", "after_attempts"] : ["mode", "lines"]
        let f = try c.superDecoder(forKey: AnyKey(key)).strict(allowed)
        guard try f.required("mode") as String == expected else { throw f.fail("\(key) 的 mode 必須是 \(expected)") }
        if attemptsKey, try f.required("after_attempts") as Int != 2 { throw f.fail("after_attempts 必須是 2") }
        return FallbackPath(lines: try f.required("lines"))
    }
}

enum AsrTarget: Hashable, Sendable {
    case line(TextItem)
    case byOption(fromBeat: String, lines: [String: TextItem])
}

struct AsrBeat: Hashable, Sendable {
    static let keys: Set<String> = ["prompt", "hint", "target_line", "target_lines_by_option", "accept", "match", "feedback",
                                    "on_mic_denied", "on_device_unavailable", "on_no_match"]
    let prompt: TextItem
    let hint: TextItem?
    let target: AsrTarget
    let success: TextItem
    /// 本版一律走這條（D31）：裝置端辨識不可用 → 一起說。
    let sayTogether: FallbackPath

    init(_ c: StrictContainer) throws {
        prompt = try c.required("prompt")
        hint = try c.optional("hint")
        let line: TextItem? = try c.optional("target_line")
        if let line {
            try c.forbid(["target_lines_by_option"])
            target = .line(line)
        } else {
            let t = try c.superDecoder(forKey: AnyKey("target_lines_by_option")).strict(["from_beat", "lines"])
            target = .byOption(fromBeat: try t.required("from_beat"), lines: try t.required("lines"))
        }
        let accept = try c.superDecoder(forKey: AnyKey("accept")).strict(["zh-Hant"])
        let _: [String] = try accept.required("zh-Hant")
        guard try c.required("match") as String == "keyword_or_voice" else { throw c.fail("match 必須是 keyword_or_voice") }
        let feedback = try c.superDecoder(forKey: AnyKey("feedback")).strict(["success"])
        success = try feedback.required("success")
        _ = try FallbackPath.decode(c, key: "on_mic_denied", mode: "say_together", attemptsKey: false)
        sayTogether = try FallbackPath.decode(c, key: "on_device_unavailable", mode: "say_together", attemptsKey: false)
        _ = try FallbackPath.decode(c, key: "on_no_match", mode: "tap_to_read", attemptsKey: true)
    }
}

enum SandboxScoring: Hashable, Sendable {
    case open
    case graded(right: String, wrong: String)
}

struct SandboxBeat: Hashable, Sendable {
    static let keys: Set<String> = ["sandbox_ref", "prompt", "reaction_prompt", "reactions", "scoring", "reaction_for_truth",
                                    "closing_line", "feedback", "max_attempts", "after_max"]
    let sandboxRef: String
    let prompt: TextItem
    let reactionPrompt: TextItem
    let reactions: [Option]
    let scoring: SandboxScoring
    let closingLine: TextItem
    let feedback: Feedback
    let attempts: Attempts

    init(_ c: StrictContainer) throws {
        sandboxRef = try c.required("sandbox_ref")
        prompt = try c.required("prompt")
        reactionPrompt = try c.required("reaction_prompt")
        reactions = try c.required("reactions")
        closingLine = try c.required("closing_line")
        attempts = try Attempts(c)
        switch try c.required("scoring") as String {
        case "open":
            try c.forbid(["reaction_for_truth"])
            guard attempts.max == 1 else { throw c.fail("沒有標準答案的沙盒只能選一次") }
            scoring = .open
            feedback = try Feedback.open(c)
        case "graded":
            let t = try c.superDecoder(forKey: AnyKey("reaction_for_truth")).strict(["right", "wrong"])
            scoring = .graded(right: try t.required("right"), wrong: try t.required("wrong"))
            feedback = try Feedback.graded(c)
        default:
            throw c.fail("未知的 scoring")
        }
    }
}

struct ReviewQuestion: Decodable, Hashable, Sendable {
    let id: String
    let prompt: TextItem
    let options: [Option]
    let correct: [String]
    let feedback: Feedback
    let attempts: Attempts

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["id", "prompt", "options", "correct_option_ids", "feedback", "max_attempts", "after_max"])
        id = try c.required("id")
        prompt = try c.required("prompt")
        options = try c.required("options")
        correct = try c.required("correct_option_ids")
        feedback = try Feedback.graded(c)
        attempts = try Attempts(c)
    }
}

struct Sticker: Decodable, Hashable, Sendable {
    let id: String
    let label: TextItem
    let image: String
    let a11yLabel: String

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["id", "label", "image", "a11y_label"])
        id = try c.required("id")
        label = try c.required("label")
        image = try c.required("image")
        a11yLabel = (try c.required("a11y_label") as LocalizedText).zhHant
    }
}

enum BeatKind: Hashable, Sendable {
    case intro(lines: [TextItem])
    case choice(ChoiceBeat)
    case drag(DragBeat)
    case asr(AsrBeat)
    case ritual(lines: [TextItem])
    case sandbox(SandboxBeat)
    case story(ref: String)
    case review(questions: [ReviewQuestion])
    case sticker(Sticker, lines: [TextItem])
}

struct Beat: Decodable, Hashable, Sendable {
    private static let common: Set<String> = ["id", "type", "est_seconds", "transition_hint", "coplay_prompt"]

    let id: String
    let estSeconds: Int
    let transition: TransitionHint
    let kind: BeatKind

    init(from decoder: Decoder) throws {
        let type = try decoder.container(keyedBy: AnyKey.self).decode(String.self, forKey: AnyKey("type"))
        let allowed: Set<String> = switch type {
        case "intro": ["lines"]
        case "choice": ChoiceBeat.keys
        case "drag": DragBeat.keys
        case "asr_repeat": AsrBeat.keys
        case "sandbox_ritual": ["lines", "skippable"]
        case "sandbox": SandboxBeat.keys
        case "story": ["story_ref"]
        case "review": ["questions"]
        case "sticker": ["sticker", "lines", "award"]
        default: throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "未知的 beat type：\(type)"))
        }
        let c = try decoder.strict(Self.common.union(allowed))
        id = try c.required("id")
        estSeconds = try c.required("est_seconds")
        guard (1...180).contains(estSeconds) else { throw c.fail("est_seconds 必須是 1–180") }
        transition = try c.optional("transition_hint") ?? .none
        let _: TextItem? = try c.optional("coplay_prompt")
        kind = switch type {
        case "intro": .intro(lines: try c.required("lines"))
        case "choice": .choice(try ChoiceBeat(c))
        case "drag": .drag(try DragBeat(c))
        case "asr_repeat": .asr(try AsrBeat(c))
        case "sandbox_ritual": try Self.ritual(c)
        case "sandbox": .sandbox(try SandboxBeat(c))
        case "story": .story(ref: try c.required("story_ref"))
        case "review": .review(questions: try c.required("questions"))
        default: try Self.sticker(c)
        }
    }

    private static func ritual(_ c: StrictContainer) throws -> BeatKind {
        guard try c.required("skippable") as Bool == false else { throw c.fail("儀式不可跳過") }
        return .ritual(lines: try c.required("lines"))
    }

    private static func sticker(_ c: StrictContainer) throws -> BeatKind {
        guard try c.required("award") as String == "on_reach" else { throw c.fail("貼紙不得綁表現") }
        return .sticker(try c.required("sticker"), lines: try c.optional("lines") ?? [])
    }
}

struct Unit: Decodable, Hashable, Sendable {
    let id: String
    let title: TextItem
    let goldenLine: TextItem
    let beats: [Beat]
    let stories: [Story]
    let sandboxes: [SandboxDefinition]
    let parentCard: TextItem

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["kind", "schema_version", "unit_id", "meta", "narrator", "ai_persona", "beats",
                                    "stories", "sandboxes", "parent_card", "age_overrides"])
        guard try c.required("kind") as String == "unit" else { throw c.fail("kind 必須是 unit") }
        let _: String = try c.required("schema_version")
        id = try c.required("unit_id")
        let meta = try c.superDecoder(forKey: AnyKey("meta")).strict(["title", "golden_line", "max_seconds"])
        title = try meta.required("title")
        goldenLine = try meta.required("golden_line")
        let _: Int = try meta.required("max_seconds")
        let narrator = try c.superDecoder(forKey: AnyKey("narrator")).strict(["id", "is_ai"])
        let persona = try c.superDecoder(forKey: AnyKey("ai_persona")).strict(["id", "is_ai"])
        guard try narrator.required("is_ai") as Bool == false, try persona.required("is_ai") as Bool == true,
              try narrator.required("id") as String != (try persona.required("id") as String) else {
            throw c.fail("點點不是 AI、猜猜帽是 AI，而且兩者 id 不同")
        }
        beats = try c.required("beats")
        stories = try c.required("stories")
        sandboxes = try c.required("sandboxes")
        parentCard = try c.required("parent_card")
        guard parentCard.audience == .parent else { throw c.fail("家長卡必須是 audience: parent") }
        // 格式允許 age_overrides，但本版引擎還不會套用；與其默默忽略，不如明確拒絕。
        guard !c.contains(AnyKey("age_overrides")) else { throw c.fail("本版引擎尚未支援 age_overrides") }
    }
}
