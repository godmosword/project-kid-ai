import AVFAudio
import Foundation
import Observation
import Speech

/// 畫面狀態與設定。一次嘗試的流程在 TrialRunner；彙總只存在記憶體，關掉 App 就清空。
@MainActor
@Observable
final class SpikeModel {
    static let pauseOptions: [Double] = [1.2, 1.8, 2.5]
    static let maxOptions: [Double] = [6, 8]
    static let thresholdOptions: [Int] = [-50, -45, -40]
    static let sayTogetherLine = "按一下嘴巴按鈕，我們一起說。"

    var path: SpikePath = .speechAnalyzer
    var phrase: Phrase = Phrase.catalog[0]
    var environment: TrialEnvironment = .quietNear
    var content: SpeechContent = .readAlong
    var pauseSeconds: Double = 2.5
    var maxSeconds: Double = 6
    var vadThresholdDB: Int = -45
    var sessionMode: SessionMode = .standard
    var playPrompt = true
    var airplaneMode = false
    var includePhraseInSummary = false

    private(set) var isRunning = false
    private(set) var isDownloading = false
    private(set) var levelDB: Float = -160
    private(set) var lastOutcome: TrialOutcome?
    private(set) var showSayTogether = false
    private(set) var results: [TrialResult] = []
    private(set) var availability: [String] = []
    private(set) var modelNotInstalled = false
    private(set) var downloadStatus: String?
    private(set) var blockedReason: String?

    private let runner = TrialRunner()
    private var usedPaths: Set<SpikePath> = []

    var settingsBanner: String {
        "\(path.rawValue)｜\(phrase.id)｜\(environment.rawValue)｜\(content.rawValue)｜\(String(format: "%.1f", pauseSeconds))s｜\(airplaneMode ? "飛航" : "有網")"
    }

    var currentGroupCount: Int {
        let key = currentSettings(modelInstalled: nil, coldStart: false).groupKey(includePhrase: true)
        return results.filter { $0.settings.groupKey(includePhrase: true).hasPrefix(key) }.count
    }

    var canDownload: Bool { path == .speechAnalyzer && modelNotInstalled && !isRunning && !isDownloading }

    // MARK: - 可用性

    func refreshAvailability() async {
        var lines = ["iOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
                     "麥克風權限：\(Self.label(AVAudioApplication.shared.recordPermission))",
                     "語音辨識權限：\(Self.label(SFSpeechRecognizer.authorizationStatus()))"]
        for localeID in ["zh-TW", "zh-CN", "zh-HK"] {
            lines.append("A \(localeID)：\(PathARecognizer.describe(localeID: localeID))")
        }
        if #available(iOS 26, *) {
            let reason = await PathBRecognizer.unavailableReason()
            modelNotInstalled = reason == "model_not_installed"
            lines.append("B zh-TW：\(reason ?? "模型已安裝")")
        } else {
            lines.append("B：需要 iOS 26")
        }
        availability = lines
    }

    /// D21(b)：spike 限定的網路例外；畫面上先經大人確認才會呼叫。
    func downloadModel() async {
        guard canDownload, #available(iOS 26, *) else { return }
        isDownloading = true
        defer { isDownloading = false }
        downloadStatus = "下載中…"
        let started = ContinuousClock.now
        do {
            let downloaded = try await PathBRecognizer.downloadModel()
            downloadStatus = downloaded ? "完成，\(TrialRunner.ms(ContinuousClock.now - started)) ms" : "不需要下載或不支援"
        } catch {
            let error = error as NSError
            downloadStatus = "失敗 \(error.domain)#\(error.code)"
        }
        await refreshAvailability()
    }

    // MARK: - 執行

    func runTrial() async {
        guard !isRunning, !isDownloading else { return }
        if content == .promptOnly, !playPrompt {
            blockedReason = "「只播提示」要打開「先播提示語音」"
            return
        }
        blockedReason = nil
        isRunning = true
        showSayTogether = false
        defer {
            isRunning = false
            levelDB = -160
        }
        var modelInstalled: Bool?
        if path == .speechAnalyzer, #available(iOS 26, *) {
            modelInstalled = await PathBRecognizer.unavailableReason() != "model_not_installed"
        }
        let settings = currentSettings(modelInstalled: modelInstalled, coldStart: !usedPaths.contains(path))
        usedPaths.insert(path)
        let result = await runner.run(settings: settings, phrase: phrase) { [weak self] level in
            self?.levelDB = level
        }
        results.append(result)
        lastOutcome = result.outcome
        if case .unavailable = result.outcome { showSayTogether = true }
    }

    func deleteLast() {
        guard !isRunning, !results.isEmpty else { return }
        results.removeLast()
        lastOutcome = results.last?.outcome
    }

    func clearResults() {
        results.removeAll()
        lastOutcome = nil
    }

    private func currentSettings(modelInstalled: Bool?, coldStart: Bool) -> TrialSettings {
        TrialSettings(path: path, phraseID: phrase.id, environment: environment, content: content,
                      pauseSeconds: pauseSeconds, maxSeconds: maxSeconds, vadThresholdDB: vadThresholdDB,
                      sessionMode: sessionMode, playPrompt: playPrompt, airplaneMode: airplaneMode,
                      modelInstalled: modelInstalled, coldStart: coldStart)
    }

    private static func label(_ permission: AVAudioApplication.recordPermission) -> String {
        switch permission {
        case .granted: "允許"
        case .denied: "拒絕（含螢幕使用時間限制）"
        case .undetermined: "尚未詢問"
        @unknown default: "未知"
        }
    }

    private static func label(_ status: SFSpeechRecognizerAuthorizationStatus) -> String {
        switch status {
        case .authorized: "允許"
        case .denied: "拒絕"
        case .restricted: "受限制"
        case .notDetermined: "尚未詢問"
        @unknown default: "未知"
        }
    }
}
