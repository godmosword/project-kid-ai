import AVFAudio

/// 路徑 A、B 共用的量測介面。實作各自獨立，只在這裡對齊。
protocol Recognizing: AnyObject, Sendable {
    /// 回傳 nil 表示已開始；否則回傳不可用的原因代碼（呼叫端改走「一起說」，不重試）。
    func start(inputFormat: AVAudioFormat, accept: [String], state: TrialState) async -> String?
    func append(_ buffer: AVAudioPCMBuffer)
    func finish() async
    func cancel() async
}

extension PathARecognizer: Recognizing {}

@available(iOS 26, *)
extension PathBRecognizer: Recognizing {}
