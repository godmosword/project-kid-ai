import AVFAudio
import Foundation
import Speech

/// 路徑 B：SpeechAnalyzer＋SpeechTranscriber（iOS 26+），只用已安裝在裝置上的模型。
/// tap 裡只複製音訊，格式轉換在另一個工作裡做，不佔用即時音訊執行緒。
/// 辨識文字只用來比對關鍵詞，不保存、不顯示、不記錄。
@available(iOS 26, *)
final class PathBRecognizer: @unchecked Sendable {
    private let lock = NSLock()
    private var rawContinuation: AsyncStream<CopiedBuffer>.Continuation?
    private var analyzerContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzer: SpeechAnalyzer?
    private var tasks: [Task<Void, Never>] = []

    private static func zhTW() async -> Locale? {
        await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "zh-TW"))
    }

    /// nil 表示可用；否則回傳不可用的原因代碼。不會觸發任何下載。
    static func unavailableReason() async -> String? {
        guard SpeechTranscriber.isAvailable else { return "transcriber_unavailable" }
        guard let locale = await zhTW() else { return "zh_TW_unsupported" }
        let installed = await SpeechTranscriber.installedLocales
        guard installed.contains(where: { $0.identifier(.bcp47) == locale.identifier(.bcp47) }) else { return "model_not_installed" }
        return nil
    }

    /// D21(b)：spike 限定的網路例外。由大人確認後，請系統向 Apple 下載 zh-TW 模型；不會送出任何聲音。正式 App 不得使用。
    static func downloadModel() async throws -> Bool {
        guard let locale = await zhTW() else { return false }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) else { return false }
        try await request.downloadAndInstall()
        return true
    }

    func start(inputFormat: AVAudioFormat, accept: [String], state: TrialState) async -> String? {
        if let reason = await Self.unavailableReason() { return reason }
        guard let locale = await Self.zhTW() else { return "zh_TW_unsupported" }
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else { return "no_audio_format" }
        let (rawStream, rawContinuation) = AsyncStream<CopiedBuffer>.makeStream()
        let (analyzerStream, analyzerContinuation) = AsyncStream<AnalyzerInput>.makeStream()
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let converter = format == inputFormat ? nil : AVAudioConverter(from: inputFormat, to: format)
        let feeder = Task {
            for await copied in rawStream {
                if let input = Self.analyzerInput(copied.buffer, converter: converter, format: format) {
                    analyzerContinuation.yield(input)
                }
            }
            analyzerContinuation.finish()
        }
        let reader = Task {
            do {
                for try await result in transcriber.results {
                    if let index = TextMatch.matchedIndex(String(result.text.characters), accept: accept) {
                        state.markKeyword(index: index)
                    }
                }
                state.markRecognizerEnded(errorCode: nil)
            } catch {
                let error = error as NSError
                state.markRecognizerEnded(errorCode: "\(error.domain)#\(error.code)")
            }
        }
        lock.withLock {
            self.rawContinuation = rawContinuation
            self.analyzerContinuation = analyzerContinuation
            self.analyzer = analyzer
            self.tasks = [feeder, reader]
        }
        do {
            try await analyzer.start(inputSequence: analyzerStream)
        } catch {
            let error = error as NSError
            return "\(error.domain)#\(error.code)"
        }
        return nil
    }

    /// 在即時音訊執行緒呼叫：只複製 buffer，其餘交給 feeder。
    func append(_ buffer: AVAudioPCMBuffer) {
        guard let copy = CopiedBuffer(buffer) else { return }
        lock.withLock { rawContinuation }?.yield(copy)
    }

    func finish() async {
        let (raw, analyzer) = lock.withLock { (rawContinuation, self.analyzer) }
        raw?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
    }

    func cancel() async {
        let (raw, fed, analyzer, tasks) = lock.withLock {
            defer {
                rawContinuation = nil
                analyzerContinuation = nil
                self.analyzer = nil
                self.tasks = []
            }
            return (rawContinuation, analyzerContinuation, self.analyzer, self.tasks)
        }
        raw?.finish()
        fed?.finish()
        await analyzer?.cancelAndFinishNow()
        tasks.forEach { $0.cancel() }
    }

    private static func analyzerInput(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter?, format: AVAudioFormat) -> AnalyzerInput? {
        guard let converter else { return AnalyzerInput(buffer: buffer) }
        let ratio = format.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return nil }
        let feed = OneShotFeed(buffer)
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            feed.next(inputStatus)
        }
        guard error == nil, status != .error, output.frameLength > 0 else { return nil }
        return AnalyzerInput(buffer: output)
    }
}

/// tap 交出來的 buffer 會被引擎重複使用，所以先完整複製一份，所有權轉給 feeder。
private struct CopiedBuffer: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer

    init?(_ source: AVAudioPCMBuffer) {
        guard let copy = AVAudioPCMBuffer(pcmFormat: source.format, frameCapacity: source.frameLength),
              let from = source.floatChannelData, let to = copy.floatChannelData else { return nil }
        copy.frameLength = source.frameLength
        let bytes = Int(source.frameLength) * MemoryLayout<Float>.size
        for channel in 0..<Int(source.format.channelCount) {
            memcpy(to[channel], from[channel], bytes)
        }
        buffer = copy
    }
}

/// AVAudioConverter 的輸入回呼：同一個 buffer 只餵一次。只在 feeder 工作內使用。
private final class OneShotFeed: @unchecked Sendable {
    private var buffer: AVAudioPCMBuffer?

    init(_ buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }

    func next(_ status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}
