import AVFAudio
import UIKit

/// 念到哪裡：第幾句開始了、目前這句念到哪個字（一起說逐字亮起用）。
enum SpeechProgress: Equatable, Sendable {
    case line(Int)
    case word(NSRange)
}

/// 念句子的介面：畫面狀態只依賴這個，測試可換成假的。
@MainActor
protocol LineSpeaker: AnyObject {
    /// 依序念完一批；念完、失敗、被取消或逾時都會返回（CRITICAL-7）。
    /// `progress(.line(i))` 在第 i 句開始前呼叫；`userInitiated` 是孩子自己按的（🔊、一起說、重念）。
    func speak(_ lines: [SpeechLine], userInitiated: Bool, progress: @escaping (SpeechProgress) -> Void) async
    func stop()
}

/// 用系統語音念內容文字（旁白音檔還沒錄，vo_status 為 tts_placeholder）。
/// 只播放、不錄音，不需要任何權限。
@MainActor
final class Narrator: NSObject, LineSpeaker, AVSpeechSynthesizerDelegate {
    private struct Pending {
        let continuation: CheckedContinuation<Void, Never>
        let timer: Task<Void, Never>
    }

    private let synthesizer = AVSpeechSynthesizer()
    private var pending: [ObjectIdentifier: Pending] = [:]
    private var generation = 0
    private var progress: ((SpeechProgress) -> Void)?
    /// 裝置沒有中文語音時只顯示文字，不叫系統下載語音。
    let hasChineseVoice: Bool

    override init() {
        hasChineseVoice = AVSpeechSynthesisVoice.speechVoices().contains { $0.language == "zh-TW" }
        super.init()
        synthesizer.delegate = self
        // 只播放：靜音開關開著也聽得到；不會要求麥克風
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    func speak(_ lines: [SpeechLine], userInitiated: Bool, progress: @escaping (SpeechProgress) -> Void) async {
        stop()
        let mine = generation
        // VoiceOver 開著時只停自動旁白（避免和讀螢幕搶話）；孩子自己按的仍要念
        let voiceOver = UIAccessibility.isVoiceOverRunning
        guard hasChineseVoice, userInitiated || !voiceOver else {
            // CRITICAL-9：念不出來就整段字立刻都在畫面上，不用閱讀時間把「下一步」藏起來
            lines.indices.forEach { progress(.line($0)) }
            if voiceOver, !lines.isEmpty {
                UIAccessibility.post(notification: .announcement, argument: lines.map(\.text).joined(separator: " "))
            }
            return
        }
        self.progress = progress
        for (index, line) in lines.enumerated() {
            guard mine == generation else { return }
            progress(.line(index))
            await speakOne(line)
        }
        if mine == generation { self.progress = nil }
    }

    /// 孩子一有動作就停止旁白；等待中的句子全部算結束。
    func stop() {
        generation += 1
        progress = nil
        synthesizer.stopSpeaking(at: .immediate)
        for id in Array(pending.keys) { finish(id) }
    }

    private func speakOne(_ line: SpeechLine) async {
        let utterance = AVSpeechUtterance(string: line.text)
        utterance.voice = AVSpeechSynthesisVoice(language: "zh-TW")
        let (rate, pitch) = Self.voice(for: line.role)
        utterance.rate = rate
        utterance.pitchMultiplier = pitch
        utterance.preUtteranceDelay = line.pauseBefore
        utterance.postUtteranceDelay = line.pauseAfter
        let id = ObjectIdentifier(utterance)
        let timeout = Self.timeoutMilliseconds(line)
        await withCheckedContinuation { continuation in
            let timer = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(timeout))
                guard !Task.isCancelled else { return }
                self?.finish(id)
            }
            pending[id] = Pending(continuation: continuation, timer: timer)
            synthesizer.speak(utterance)
        }
    }

    private func finish(_ id: ObjectIdentifier) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.timer.cancel()
        entry.continuation.resume()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.finish(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange,
                                       utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard self.pending[id] != nil else { return }
            self.progress?(.word(characterRange))
        }
    }

    /// 三段聲音各自的語速與音高；用明確的對照表，不從 key 猜（實機再調）。
    private static let soundVoices: [String: (rate: Float, pitch: Float)] = [
        "sfx_voice_family_short": (0.44, 0.9),
        "sfx_voice_toy_short": (0.5, 1.5),
        "sfx_voice_ai_short": (0.45, 1.28),
        // 單元 2 第 1 關：小熊（低、慢）和小兔（高、快）要聽得出是不同角色
        "sfx_u2_bear_vague": (0.4, 0.78),
        "sfx_u2_rabbit_clear": (0.47, 1.35),
        // 單元 3 分組字卡：用旁白的聲音念句子
        "sfx_u3_fish": (0.42, 1.0),
        "sfx_u3_moon": (0.42, 1.0),
        "sfx_u3_ice": (0.42, 1.0),
        "sfx_u3_sun": (0.42, 1.0),
    ]

    static func voice(for role: VoiceRole) -> (rate: Float, pitch: Float) {
        switch role {
        case .narrator: (0.42, 1.0)
        case .aiPersona: (0.45, 1.28)
        case .readAlong: (0.38, 1.0)
        case .sound(let key): soundVoices[key] ?? (0.44, 0.9)
        }
    }

    /// 語音引擎沒有回報時的保險：大約是正常念完時間的 3 倍。
    static func timeoutMilliseconds(_ line: SpeechLine) -> Int {
        Int(Double(line.text.count) * 280 * 3 + (line.pauseBefore + line.pauseAfter) * 1000) + 2000
    }
}
