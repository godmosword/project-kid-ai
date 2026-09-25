import AVFAudio

/// 用裝置內建語音播提示句。播完才開麥克風，避免提示句裡的關鍵詞被收進去。
@MainActor
final class PromptSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var continuation: CheckedContinuation<Void, Never>?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) async {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-TW")
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            synthesizer.speak(utterance)
        }
    }

    private func resume() {
        continuation?.resume()
        continuation = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resume() }
    }
}
