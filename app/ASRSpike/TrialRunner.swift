import AVFAudio
import Foundation
import Speech

/// 一次嘗試的流程：權限 → 提示語音 → 靜音間隔 → 收音與辨識 → 判定。
/// 不寫檔、不記錄、不連網；辨識文字只在辨識器內部用來比對關鍵詞。
@MainActor
final class TrialRunner {
    /// 提示播完到開麥之間的靜音，避免提示句（含關鍵詞）的殘響被收進去。
    static let promptGap: Duration = .milliseconds(300)
    static let preVoiceWait: Duration = .seconds(4)
    /// 命中關鍵詞後繼續聽，最多再這麼久，用來量「孩子還在說話就被鼓勵」。
    static let afterKeywordListen: Duration = .milliseconds(1200)
    /// 講完後等辨識器收尾（只影響分類，不影響鼓勵出現的時間）。
    static let recognizerGrace: Duration = .milliseconds(1500)

    private let speaker = PromptSpeaker()
    private var interruption: String?
    private var activeAudio: AudioCapture?
    private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            guard raw.flatMap(AVAudioSession.InterruptionType.init) == .began else { return }
            MainActor.assumeIsolated { self?.interrupt("interruption") }
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard let reason = raw.flatMap(AVAudioSession.RouteChangeReason.init),
                  reason == .newDeviceAvailable || reason == .oldDeviceUnavailable else { return }
            MainActor.assumeIsolated { self?.interrupt("route_change") }
        })
    }

    private func interrupt(_ reason: String) {
        guard activeAudio != nil else { return }
        interruption = reason
        activeAudio?.stop()
    }

    func run(settings: TrialSettings, phrase: Phrase, level: @escaping (Float) -> Void) async -> TrialResult {
        interruption = nil
        let pressed = ContinuousClock.now
        if let problem = await permissionProblem(path: settings.path) {
            return unavailable(settings, problem)
        }
        do {
            try AudioCapture.configureSession(settings.sessionMode)
        } catch {
            return unavailable(settings, "session")
        }
        defer { AudioCapture.deactivateSession() }
        var promptEnd: ContinuousClock.Instant?
        if settings.playPrompt {
            await speaker.speak("跟我一起說：\(phrase.line)")
            promptEnd = .now
            try? await Task.sleep(for: Self.promptGap)
        }
        return await capture(settings: settings, phrase: phrase, reference: promptEnd ?? pressed, level: level)
    }

    private func capture(settings: TrialSettings, phrase: Phrase, reference: ContinuousClock.Instant,
                         level: @escaping (Float) -> Void) async -> TrialResult {
        let state = TrialState(thresholdDB: settings.vadThresholdDB)
        let audio = AudioCapture()
        guard let recognizer = makeRecognizer(settings.path) else {
            if settings.path == .speechAnalyzer { return unavailable(settings, "needs_ios26") }
            return await listen(settings: settings, state: state, audio: audio, recognizer: nil, reference: reference, level: level)
        }
        if let reason = await recognizer.start(inputFormat: audio.inputFormat, accept: phrase.accept, state: state) {
            await recognizer.cancel()
            return unavailable(settings, reason)
        }
        return await listen(settings: settings, state: state, audio: audio, recognizer: recognizer, reference: reference, level: level)
    }

    private func listen(settings: TrialSettings, state: TrialState, audio: AudioCapture, recognizer: (any Recognizing)?,
                        reference: ContinuousClock.Instant, level: @escaping (Float) -> Void) async -> TrialResult {
        var sink: AudioCapture.Sink?
        if let recognizer {
            sink = { buffer in recognizer.append(buffer) }
        }
        do {
            try audio.start(state: state, sink: sink)
        } catch {
            await recognizer?.cancel()
            return unavailable(settings, "engine_start")
        }
        activeAudio = audio
        let started = ContinuousClock.now
        let reason = await waitForEnd(settings: settings, state: state, started: started, level: level)
        audio.stop()
        activeAudio = nil
        let endpointAt = ContinuousClock.now
        let outcome = await classify(reason, state: state, recognizer: recognizer)
        let snapshot = state.snapshot()
        await recognizer?.cancel()
        return makeResult(settings, outcome: outcome, reason: reason, snapshot: snapshot,
                          reference: reference, started: started, endpointAt: endpointAt)
    }

    private func waitForEnd(settings: TrialSettings, state: TrialState, started: ContinuousClock.Instant,
                            level: (Float) -> Void) async -> EndReason {
        let pause = Duration.seconds(settings.pauseSeconds)
        while true {
            try? await Task.sleep(for: .milliseconds(30))
            let snapshot = state.snapshot()
            level(snapshot.levelDB)
            let now = ContinuousClock.now
            if interruption != nil { return .interrupted }
            if settings.path != .voiceOnly, snapshot.recognizerEnded, snapshot.errorCode != nil { return .recognizerFailed }
            if now - started >= .seconds(settings.maxSeconds) { return snapshot.keyword != nil ? .keyword : .timeout }
            if snapshot.voiceOnset == nil, now - started >= Self.preVoiceWait { return .noVoice }
            if let keyword = snapshot.keyword {
                // 命中後繼續聽到講完或最多 1.2 秒，才量得到「還在說就被鼓勵」
                let silent = snapshot.lastVoice.map { now - $0 >= pause } ?? true
                if silent || now - keyword >= Self.afterKeywordListen { return .keyword }
                continue
            }
            if let last = snapshot.lastVoice, snapshot.voiceOnset != nil, now - last >= pause { return .endpoint }
        }
    }

    /// 命中關鍵詞優先，其次是有出聲。辨識器失敗的那一次一律算不可用，不計入關鍵詞（對抗審 #3）。
    private func classify(_ reason: EndReason, state: TrialState, recognizer: (any Recognizing)?) async -> TrialOutcome {
        switch reason {
        case .interrupted: return .interrupted(interruption ?? "unknown")
        case .recognizerFailed: return .unavailable(state.snapshot().errorCode ?? "recognizer")
        case .keyword: return .keyword
        default: break
        }
        if let recognizer, state.snapshot().voiceOnset != nil {
            // 收尾不阻塞：最多等 recognizerGrace，逾時就不再等
            Task { await recognizer.finish() }
            let deadline = ContinuousClock.now + Self.recognizerGrace
            while ContinuousClock.now < deadline {
                let snapshot = state.snapshot()
                if snapshot.keyword != nil { return .keyword }
                if snapshot.recognizerEnded { break }
                try? await Task.sleep(for: .milliseconds(30))
            }
        }
        return state.snapshot().voiceOnset != nil ? .voiceOnly : .nothing
    }

    private func makeResult(_ settings: TrialSettings, outcome: TrialOutcome, reason: EndReason, snapshot: TrialState.Snapshot,
                            reference: ContinuousClock.Instant, started: ContinuousClock.Instant,
                            endpointAt: ContinuousClock.Instant) -> TrialResult {
        // 鼓勵出現的時間：命中關鍵詞當下，或（只靠出聲時）偵測到停頓當下
        let rewardAt: ContinuousClock.Instant? = switch outcome {
        case .keyword: snapshot.keyword
        case .voiceOnly: endpointAt
        default: nil
        }
        let noise = snapshot.noiseLevels
        return TrialResult(
            settings: settings, outcome: outcome, endReason: reason,
            matchedKeywordIndex: outcome == .keyword ? snapshot.keywordIndex : nil,
            captureDelayMs: snapshot.firstBuffer.map { Self.ms($0 - reference) },
            voiceOnsetMs: snapshot.voiceOnset.map { Self.ms($0 - started) },
            feedbackAfterSilenceMs: rewardAt.flatMap { reward in snapshot.lastVoice.map { Self.ms(reward - $0) } },
            noiseMedianDB: Percentile.value(noise, 0.5), noiseMaxDB: noise.max(),
            bufferMs: snapshot.bufferSeconds.map { Int(($0 * 1000).rounded()) },
            errorCode: snapshot.errorCode)
    }

    private func unavailable(_ settings: TrialSettings, _ reason: String) -> TrialResult {
        TrialResult(settings: settings, outcome: .unavailable(reason), endReason: .unavailable, matchedKeywordIndex: nil,
                    captureDelayMs: nil, voiceOnsetMs: nil, feedbackAfterSilenceMs: nil, noiseMedianDB: nil,
                    noiseMaxDB: nil, bufferMs: nil, errorCode: nil)
    }

    private func makeRecognizer(_ path: SpikePath) -> (any Recognizing)? {
        switch path {
        case .speechRecognizer: return PathARecognizer()
        case .speechAnalyzer:
            if #available(iOS 26, *) { return PathBRecognizer() }
            return nil
        case .voiceOnly: return nil
        }
    }

    private func permissionProblem(path: SpikePath) async -> String? {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: break
        case .denied: return "mic_denied"
        case .undetermined:
            guard await AVAudioApplication.requestRecordPermission() else { return "mic_denied" }
        @unknown default: return "mic_unknown"
        }
        guard path == .speechRecognizer else { return nil }
        var status = SFSpeechRecognizer.authorizationStatus()
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
            }
        }
        switch status {
        case .authorized: return nil
        case .restricted: return "speech_restricted"
        default: return "speech_denied"
        }
    }

    static func ms(_ duration: Duration) -> Int {
        let (seconds, attoseconds) = duration.components
        return Int(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
    }
}
