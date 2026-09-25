import Foundation

/// 三條要比較的路徑。
enum SpikePath: String, CaseIterable, Identifiable, Sendable {
    case speechRecognizer = "A"
    case speechAnalyzer = "B"
    case voiceOnly = "C"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .speechRecognizer: "A｜SFSpeechRecognizer"
        case .speechAnalyzer: "B｜SpeechAnalyzer（iOS 26+）"
        case .voiceOnly: "C｜只偵測出聲"
        }
    }
}

/// 單元 1–4 已核准的跟讀句與關鍵詞（對照 content/units/*.json 的 asr_repeat）。
struct Phrase: Identifiable, Hashable, Sendable {
    let id: String
    let line: String
    let accept: [String]

    static let catalog: [Phrase] = [
        Phrase(id: "u1", line: "AI 會猜。", accept: ["AI", "會猜", "猜"]),
        Phrase(id: "u2", line: "請畫一隻坐著的小黃貓。", accept: ["小黃貓", "坐著", "黃貓", "貓"]),
        Phrase(id: "u3", line: "AI 會說錯，我可以檢查。", accept: ["檢查", "說錯", "可以"]),
        Phrase(id: "u4_rescue", line: "我們一起救朋友。", accept: ["一起", "救朋友", "分享", "不放棄"]),
        Phrase(id: "u4_share", line: "我們一起分享食物。", accept: ["一起", "救朋友", "分享", "不放棄"]),
        Phrase(id: "u4_keep", line: "我們不放棄，一直努力。", accept: ["一起", "救朋友", "分享", "不放棄"]),
    ]
}

/// 測試環境（見 docs/spikes/asr-spike-protocol.md）。
enum TrialEnvironment: String, CaseIterable, Identifiable, Sendable {
    case quietNear = "安靜30cm"
    case tableFar = "平放1m"
    case tvNoise = "電視聲"
    case otherVoices = "旁人說話"

    var id: String { rawValue }
}

/// 這一次說了什麼。負例應該都不算完成。
enum SpeechContent: String, CaseIterable, Identifiable, Sendable {
    case readAlong = "跟讀"
    case childlike = "孩子說法"
    case speakDuringPrompt = "搶先說"
    case silence = "負例：沒聲音"
    case promptOnly = "負例：只播提示"
    case otherWords = "負例：說別的話"

    var id: String { rawValue }
    var isNegative: Bool { self == .silence || self == .promptOnly || self == .otherWords }
    /// D25：出聲誤觸發只看這兩種負例（說別的話依 A4 本來就算出聲）。
    var countsForVoiceFalseTrigger: Bool { self == .silence || self == .promptOnly }
}

/// 一次嘗試的全部設定。彙總依這些欄位分組，避免不同變因混在一起（CRITICAL-6）。
struct TrialSettings: Hashable, Sendable {
    let path: SpikePath
    let phraseID: String
    let environment: TrialEnvironment
    let content: SpeechContent
    let pauseSeconds: Double
    let maxSeconds: Double
    let vadThresholdDB: Int
    let sessionMode: SessionMode
    let playPrompt: Bool
    /// 大人手動確認的網路狀態
    let airplaneMode: Bool
    /// 路徑 B：開始時模型是否已安裝
    let modelInstalled: Bool?
    /// App 啟動後這條路徑的第一次
    let coldStart: Bool

    func groupKey(includePhrase: Bool) -> String {
        var parts = [path.rawValue, environment.rawValue, content.rawValue,
                     String(format: "%.1fs", pauseSeconds), "上限\(Int(maxSeconds))s", "\(vadThresholdDB)dB",
                     sessionMode.rawValue, playPrompt ? "有提示" : "無提示", airplaneMode ? "飛航" : "有網"]
        if let modelInstalled { parts.append(modelInstalled ? "模型已裝" : "模型未裝") }
        if coldStart { parts.append("冷啟動") }
        if includePhrase { parts.insert(phraseID, at: 1) }
        return parts.joined(separator: "｜")
    }
}

/// 一次嘗試的結果分類。只記分類與數字，不記辨識文字。
enum TrialOutcome: Hashable, Sendable {
    case keyword
    case voiceOnly
    case nothing
    case unavailable(String)
    case interrupted(String)

    var label: String {
        switch self {
        case .keyword: "關鍵詞"
        case .voiceOnly: "只靠出聲"
        case .nothing: "都沒有"
        case .unavailable(let reason): "不可用 \(reason)"
        case .interrupted(let reason): "中斷 \(reason)"
        }
    }

    /// 依 A4：說中關鍵詞或有出聲，都算完成。
    var countsAsDone: Bool { self == .keyword || self == .voiceOnly }
    var isExcludedFromRates: Bool {
        switch self {
        case .unavailable, .interrupted: true
        default: false
        }
    }
}

/// 這一次為什麼結束。
enum EndReason: String, Sendable {
    case keyword = "命中"
    case endpoint = "偵測到停頓"
    case noVoice = "沒開口"
    case timeout = "撞上限"
    case recognizerFailed = "辨識器失敗"
    case interrupted = "中斷"
    case unavailable = "不可用"
}

struct TrialResult: Identifiable, Sendable {
    let id = UUID()
    let settings: TrialSettings
    let outcome: TrialOutcome
    let endReason: EndReason
    /// 命中的是 accept 清單裡第幾個詞（只記編號，不記孩子說了什麼）
    let matchedKeywordIndex: Int?
    /// 有提示：提示播完到收到第一段音訊；無提示：按下開始到收到第一段音訊
    let captureDelayMs: Int?
    /// 開始收音到偵測到開口
    let voiceOnsetMs: Int?
    /// D25：出現鼓勵的時間減去講完的時間。負值表示孩子還在說話就被鼓勵。
    let feedbackAfterSilenceMs: Int?
    /// 開口前的背景音量（整數 dB，不是音訊）
    let noiseMedianDB: Int?
    let noiseMaxDB: Int?
    /// 實際每段音訊的長度
    let bufferMs: Int?
    /// 辨識器回報的錯誤 domain#code（只記代碼）
    let errorCode: String?
}

enum Percentile {
    static func value(_ values: [Int], _ p: Double) -> Int? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[index]
    }
}
