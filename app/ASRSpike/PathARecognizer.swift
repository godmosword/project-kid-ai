import AVFAudio
import Foundation
import Speech

/// 路徑 A：SFSpeechRecognizer，只在裝置端辨識。
/// 規則（CRITICAL-2）：requiresOnDeviceRecognition 一律寫死 true；不支援裝置端或任何失敗，
/// 都直接回報不可用、改走「一起說」——不重試、不改旗標、不換語言。
/// 規則（CRITICAL-5）：能不能用只看 supportsOnDeviceRecognition；isAvailable 會隨網路改變，只記錄、不當門檻，
/// 否則飛航模式下根本不會送出裝置端請求。
/// 規則（CRITICAL-3）：辨識文字只用來比對關鍵詞，不保存、不顯示、不記錄。
final class PathARecognizer: @unchecked Sendable {
    static let localeID = "zh-TW"

    private let lock = NSLock()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// 可用性顯示用：是否支援裝置端、isAvailable（僅記錄）。
    static func describe(localeID: String) -> String {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: localeID)) else { return "沒有辨識器" }
        return "supportsOnDevice=\(recognizer.supportsOnDeviceRecognition ? "yes" : "no")、isAvailable=\(recognizer.isAvailable ? "yes" : "no")"
    }

    func start(inputFormat: AVAudioFormat, accept: [String], state: TrialState) -> String? {
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: Self.localeID)) else { return "no_recognizer" }
        guard recognizer.supportsOnDeviceRecognition else { return "no_on_device" }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = true
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let error = error as NSError? {
                state.markRecognizerEnded(errorCode: "\(error.domain)#\(error.code)")
                return
            }
            if let result, let index = TextMatch.matchedIndex(result.bestTranscription.formattedString, accept: accept) {
                state.markKeyword(index: index)
            }
            if result?.isFinal == true {
                state.markRecognizerEnded(errorCode: nil)
            }
        }
        lock.withLock {
            self.recognizer = recognizer
            self.request = request
            self.task = task
        }
        return nil
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.withLock { request }?.append(buffer)
    }

    func finish() {
        lock.withLock { request }?.endAudio()
    }

    func cancel() {
        let task = lock.withLock {
            defer {
                self.task = nil
                request = nil
                recognizer = nil
            }
            return self.task
        }
        task?.cancel()
    }
}
