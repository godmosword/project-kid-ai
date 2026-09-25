import Foundation

/// 關鍵詞比對。辨識文字只在這裡用來比對，呼叫端不得保存、顯示或記錄它。
enum TextMatch {
    static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.widthInsensitive, .caseInsensitive], locale: Locale(identifier: "zh_TW"))
        return String(folded.unicodeScalars.filter { scalar in
            !CharacterSet.whitespacesAndNewlines.contains(scalar) && !CharacterSet.punctuationCharacters.contains(scalar)
        })
    }

    /// 回傳命中的關鍵詞在 accept 裡的編號；較長的詞優先，才看得出是整個詞還是單字命中。沒有命中回傳 nil。
    static func matchedIndex(_ transcript: String, accept: [String]) -> Int? {
        let haystack = normalize(transcript)
        return accept.indices
            .sorted { accept[$0].count > accept[$1].count }
            .first { haystack.contains(normalize(accept[$0])) }
    }
}
