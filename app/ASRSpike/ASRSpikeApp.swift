import SwiftUI

/// 語音辨識 spike：只給大人在測試 iPhone 上用，不上架。見 docs/spikes/asr-spike-protocol.md。
@main
struct ASRSpikeApp: App {
    var body: some Scene {
        WindowGroup {
            SpikeView()
        }
    }
}
