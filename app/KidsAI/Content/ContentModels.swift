import Foundation

// 對應 content/schema v1。只收已定義的欄位；discriminator 先讀、再依 case 解碼。

enum Audience: String, Decodable, Sendable { case child, parent }

/// 一段文字。v1 只有 zh-Hant。
struct TextItem: Decodable, Hashable, Sendable {
    let id: String
    let audience: Audience
    let zhHant: String

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["id", "audience", "text", "vo", "vo_status"])
        id = try c.required("id")
        audience = try c.required("audience")
        let text: LocalizedText = try c.required("text")
        zhHant = text.zhHant
        if audience == .child {
            let _: String = try c.required("vo")
            let _: String = try c.required("vo_status")
        } else {
            try c.forbid(["vo", "vo_status"])
        }
    }
}

struct LocalizedText: Decodable, Hashable, Sendable {
    let zhHant: String

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["zh-Hant"])
        zhHant = try c.required("zh-Hant")
    }
}

struct Option: Decodable, Hashable, Sendable {
    let id: String
    let label: TextItem
    let image: String?
    let sound: String?
    /// 聲音裡說的話：只給旁白念，不顯示、不進無障礙標籤（避免洩漏答案）。
    let soundScript: String?
    let a11yLabel: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["id", "label", "image", "sound", "sound_script", "a11y_label"])
        id = try c.required("id")
        label = try c.required("label")
        image = try c.optional("image")
        sound = try c.optional("sound")
        soundScript = (try c.optional("sound_script") as LocalizedText?)?.zhHant
        a11yLabel = (try c.optional("a11y_label") as LocalizedText?)?.zhHant
        if image != nil, a11yLabel == nil { throw c.fail("有圖必須有 a11y_label") }
        if sound != nil, soundScript == nil || a11yLabel == nil { throw c.fail("有聲音必須有 sound_script 與 a11y_label") }
    }
}

struct Stage: Decodable, Hashable, Sendable {
    let image: String
    let a11yLabel: String

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["image", "a11y_label"])
        image = try c.required("image")
        a11yLabel = (try c.required("a11y_label") as LocalizedText).zhHant
    }
}

/// 有答案的關：success／not_yet／reveal 都要有；沒答案的關只有 reveal。
struct Feedback: Hashable, Sendable {
    let success: TextItem?
    let notYet: TextItem?
    let reveal: TextItem?

    static func graded(_ c: StrictContainer, key: String = "feedback") throws -> Feedback {
        let f = try c.superDecoder(forKey: AnyKey(key)).strict(["success", "not_yet", "reveal"])
        return Feedback(success: try f.required("success"), notYet: try f.required("not_yet"), reveal: try f.required("reveal"))
    }

    static func open(_ c: StrictContainer) throws -> Feedback {
        let f = try c.superDecoder(forKey: AnyKey("feedback")).strict(["reveal"])
        return Feedback(success: nil, notYet: nil, reveal: try f.required("reveal"))
    }
}

enum TransitionHint: String, Decodable, Sendable { case none, gentle, celebrate }

enum Speaker: String, Decodable, Sendable {
    case narrator
    case aiPersona = "ai_persona"
}

struct StoryChoice: Decodable, Hashable, Sendable {
    let id: String
    let label: TextItem
    let image: String?
    let a11yLabel: String?
    let next: String

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["id", "label", "image", "a11y_label", "next"])
        id = try c.required("id")
        label = try c.required("label")
        image = try c.optional("image")
        a11yLabel = (try c.optional("a11y_label") as LocalizedText?)?.zhHant
        next = try c.required("next")
    }
}

struct StoryNode: Decodable, Hashable, Sendable {
    enum Exit: Hashable, Sendable {
        case choices([StoryChoice])
        case next(String)
        case end
    }

    let id: String
    let speaker: Speaker
    let lines: [TextItem]
    let exit: Exit

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["id", "speaker", "lines", "choices", "next", "end", "transition_hint"])
        id = try c.required("id")
        speaker = try c.required("speaker")
        lines = try c.required("lines")
        let _: TransitionHint? = try c.optional("transition_hint")
        let choices: [StoryChoice]? = try c.optional("choices")
        let next: String? = try c.optional("next")
        let end: Bool? = try c.optional("end")
        switch (choices, next, end) {
        case let (choices?, nil, nil): exit = .choices(choices)
        case let (nil, next?, nil): exit = .next(next)
        case (nil, nil, true?): exit = .end
        default: throw c.fail("故事節點必須剛好有 choices、next、end 其中一個")
        }
    }
}

struct Story: Decodable, Hashable, Sendable {
    let id: String
    let start: String
    let nodes: [StoryNode]

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["id", "start", "nodes"])
        id = try c.required("id")
        start = try c.required("start")
        nodes = try c.required("nodes")
    }

    func node(_ id: String) -> StoryNode? { nodes.first { $0.id == id } }
}

enum Uncertainty: String, Decodable, Sendable { case unsure, sure }

struct SandboxSlot: Decodable, Hashable, Sendable {
    let id: String
    let label: TextItem
    let image: String?
    let a11yLabel: String?
    let choices: [Option]

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["id", "label", "image", "a11y_label", "choices"])
        id = try c.required("id")
        label = try c.required("label")
        image = try c.optional("image")
        a11yLabel = (try c.optional("a11y_label") as LocalizedText?)?.zhHant
        choices = try c.required("choices")
    }
}

struct SandboxDefinition: Decodable, Hashable, Sendable {
    let id: String
    let requiredUncertainty: Uncertainty?
    let maxGuessChars: Int
    let slots: [SandboxSlot]

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["id", "mode", "required_uncertainty", "max_guess_chars", "slots"])
        id = try c.required("id")
        let mode: String = try c.required("mode")
        guard mode == "pregenerated" else { throw c.fail("v1 沙盒只允許 pregenerated") }
        requiredUncertainty = try c.optional("required_uncertainty")
        maxGuessChars = try c.optional("max_guess_chars") ?? 24
        slots = try c.required("slots")
    }
}

struct Guess: Decodable, Hashable, Sendable {
    let id: String
    let slotID: String
    let choiceID: String
    let text: TextItem
    let uncertainty: Uncertainty
    let truth: String?
    let image: String?
    let a11yLabel: String?
    let safe: Bool
    let approvedHash: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["id", "slot_id", "choice_id", "guess_text", "uncertainty_mark", "truth",
                                    "image", "a11y_label", "safe", "approved_hash"])
        id = try c.required("id")
        slotID = try c.required("slot_id")
        choiceID = try c.required("choice_id")
        text = try c.required("guess_text")
        uncertainty = try c.required("uncertainty_mark")
        truth = try c.optional("truth")
        image = try c.optional("image")
        a11yLabel = (try c.optional("a11y_label") as LocalizedText?)?.zhHant
        safe = try c.required("safe")
        approvedHash = try c.optional("approved_hash")
    }
}

struct GuessBank: Decodable, Hashable, Sendable {
    let unitID: String
    let sandboxID: String
    let guesses: [Guess]

    init(from decoder: Decoder) throws {
        let c = try decoder.strict(["kind", "schema_version", "unit_id", "sandbox_id", "guesses"])
        guard try c.required("kind") as String == "guess_bank" else { throw c.fail("kind 必須是 guess_bank") }
        let _: String = try c.required("schema_version")
        unitID = try c.required("unit_id")
        sandboxID = try c.required("sandbox_id")
        guesses = try c.required("guesses")
    }
}
