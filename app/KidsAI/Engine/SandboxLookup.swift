import Foundation

/// App 對沙盒的唯一請求（S2 白名單）：只有這三個鍵，不帶任何孩子的輸入或自由文字。
struct SandboxRequest: Equatable, Sendable {
    let sandboxID: String
    let slotID: String
    let structuredChoice: String
}

/// 只在本機猜測庫查表（S1），不連網。
enum SandboxLookup {
    /// 依檔案順序回傳這個請求的所有猜測；不合格的整筆丟棄（CRITICAL-8），包括不是給孩子的文字。
    static func guesses(for request: SandboxRequest, definition: SandboxDefinition, bank: GuessBank) -> [Guess] {
        guard request.sandboxID == definition.id, bank.sandboxID == definition.id,
              let slot = definition.slots.first(where: { $0.id == request.slotID }),
              slot.choices.contains(where: { $0.id == request.structuredChoice }) else { return [] }
        return bank.guesses.filter { guess in
            guess.slotID == request.slotID
                && guess.choiceID == request.structuredChoice
                && guess.text.audience == .child
                && guess.safe
                && Approval.isApproved(guess)
                && guess.text.zhHant.count <= definition.maxGuessChars
                && (definition.requiredUncertainty.map { $0 == guess.uncertainty } ?? true)
        }
    }
}
