import Foundation

/// 一次嘗試的時間點與出聲偵測。音訊執行緒寫入、主執行緒讀取快照，所以用鎖保護。
/// 只記時間、音量（整數 dB）與分類，不記任何辨識文字或音訊。
final class TrialState: @unchecked Sendable {
    struct Snapshot: Sendable {
        let firstBuffer: ContinuousClock.Instant?
        let voiceOnset: ContinuousClock.Instant?
        let lastVoice: ContinuousClock.Instant?
        let keyword: ContinuousClock.Instant?
        let keywordIndex: Int?
        let recognizerEnded: Bool
        let errorCode: String?
        let levelDB: Float
        let noiseLevels: [Int]
        let bufferSeconds: Double?
    }

    static let voiceMinimum: Duration = .milliseconds(120)
    private static let maxNoiseSamples = 400

    private let thresholdDB: Float
    private let lock = NSLock()
    private var firstBuffer: ContinuousClock.Instant?
    private var voiceOnset: ContinuousClock.Instant?
    private var lastVoice: ContinuousClock.Instant?
    private var loudRun: Duration = .zero
    private var keyword: ContinuousClock.Instant?
    private var keywordIndex: Int?
    private var recognizerEnded = false
    private var errorCode: String?
    private var levelDB: Float = -160
    private var noiseLevels: [Int] = []
    private var bufferSeconds: Double?

    init(thresholdDB: Int) {
        self.thresholdDB = Float(thresholdDB)
    }

    func ingest(levelDB level: Float, seconds: Double) {
        let now = ContinuousClock.now
        lock.withLock {
            firstBuffer = firstBuffer ?? now
            bufferSeconds = bufferSeconds ?? seconds
            levelDB = level
            if voiceOnset == nil, noiseLevels.count < Self.maxNoiseSamples {
                noiseLevels.append(Int(level.rounded()))
            }
            guard level > thresholdDB else {
                loudRun = .zero
                return
            }
            loudRun += .seconds(seconds)
            lastVoice = now
            if voiceOnset == nil, loudRun >= Self.voiceMinimum {
                voiceOnset = now - loudRun
            }
        }
    }

    func markKeyword(index: Int) {
        let now = ContinuousClock.now
        lock.withLock {
            guard keyword == nil else { return }
            keyword = now
            keywordIndex = index
        }
    }

    func markRecognizerEnded(errorCode code: String?) {
        lock.withLock {
            recognizerEnded = true
            errorCode = errorCode ?? code
        }
    }

    func snapshot() -> Snapshot {
        lock.withLock {
            Snapshot(firstBuffer: firstBuffer, voiceOnset: voiceOnset, lastVoice: lastVoice, keyword: keyword,
                     keywordIndex: keywordIndex, recognizerEnded: recognizerEnded, errorCode: errorCode,
                     levelDB: levelDB, noiseLevels: noiseLevels, bufferSeconds: bufferSeconds)
        }
    }
}
