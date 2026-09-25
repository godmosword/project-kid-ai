import AVFAudio
import Foundation

enum SessionMode: String, CaseIterable, Identifiable, Sendable {
    case standard = "一般"
    case voiceChat = "回音消除"

    var id: String { rawValue }
}

/// 把麥克風音訊即時交給辨識端。音訊只在記憶體流動：不寫檔、不保存、不記錄。
/// tap 在即時音訊執行緒回呼，這裡只算音量並把 buffer 交給 sink，不碰 UI。
final class AudioCapture: @unchecked Sendable {
    typealias Sink = @Sendable (AVAudioPCMBuffer) -> Void

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var running = false

    var inputFormat: AVAudioFormat { engine.inputNode.outputFormat(forBus: 0) }

    static func configureSession(_ mode: SessionMode) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: mode == .voiceChat ? .voiceChat : .default, options: [.defaultToSpeaker])
        try session.setActive(true)
    }

    static func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func start(state: TrialState, sink: Sink?) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            let seconds = Double(buffer.frameLength) / format.sampleRate
            state.ingest(levelDB: Self.levelDB(buffer), seconds: seconds)
            sink?(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            // 啟動失敗也要移除 tap，下一次才能重新開始
            input.removeTap(onBus: 0)
            throw error
        }
        lock.withLock { running = true }
    }

    func stop() {
        let wasRunning = lock.withLock {
            defer { running = false }
            return running
        }
        guard wasRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private static func levelDB(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return -160 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for index in 0..<count {
            sum += samples[index] * samples[index]
        }
        let rms = (sum / Float(count)).squareRoot()
        return 20 * log10(max(rms, 1e-8))
    }
}
