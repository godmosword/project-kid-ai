import Observation
import SwiftUI

/// App 狀態：載入內容、哪些島已完成。只在記憶體（D30），關掉 App 就重來。
@MainActor
@Observable
final class AppModel {
    private(set) var units: [UnitContent] = []
    private(set) var loadError: String?
    private(set) var completed: Set<String> = []
    var active: UnitStore?
    let narrator = Narrator()

    init() {
        do {
            units = try ContentLoader.bundled()
        } catch {
            loadError = "\(error)"
        }
        #if DEBUG
        openFromLaunchArguments()
        #endif
    }

    #if DEBUG
    /// 截圖驗證用：`-openUnit 0 -beat 5` 直接打開單元 1 的第 6 關（只在 Debug build）。
    private func openFromLaunchArguments() {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ name: String) -> Int? {
            arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? Int(arguments[$0 + 1]) : nil }
        }
        guard let unit = value("-openUnit"), units.indices.contains(unit) else { return }
        open(unit)
        active?.startBeat = value("-beat")
    }
    #endif

    func isPlayable(_ index: Int) -> Bool {
        guard units.indices.contains(index), UnitEngine.unsupported(units[index]).isEmpty else { return false }
        return index == 0 || completed.contains(units[index - 1].unit.id)
    }

    func open(_ index: Int) {
        active = UnitStore(content: units[index], speaker: narrator)
    }

    func finishActive() {
        if let id = active?.engine.content.unit.id { completed.insert(id) }
        active = nil
    }
}

/// 地圖首頁：四個島，每個島都有顏色＋圖示＋文字三種線索。
struct MapView: View {
    let model: AppModel

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 8)
            ForEach(Array(model.units.enumerated()), id: \.offset) { index, content in
                island(index, content)
                    .frame(maxWidth: .infinity, alignment: index.isMultiple(of: 2) ? .leading : .trailing)
            }
            Spacer(minLength: 8)
            SpeechBubble(text: Self.question, isAI: false)
        }
        .padding(24)
        .frame(maxWidth: 700)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg.ignoresSafeArea())
        // 不識字的孩子也知道要做什麼：一進地圖就念出問句
        .task { await model.narrator.speak([SpeechLine(text: Self.question, role: .narrator)], userInitiated: false) { _ in } }
    }

    static let question = "我們去哪個島？"

    private func island(_ index: Int, _ content: UnitContent) -> some View {
        let playable = model.isPlayable(index)
        let done = model.completed.contains(content.unit.id)
        let name = Theme.islandNames[index % Theme.islandNames.count]
        return Button { model.open(index) } label: {
            HStack(spacing: 10) {
                Image(systemName: playable ? Theme.islandIcons[index % Theme.islandIcons.count] : "lock.fill")
                Text(name)
                if done { Image(systemName: "star.fill") }
            }
            .font(.title2.bold())
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 24)
            .frame(minHeight: 72)
            .background(Theme.islands[index % Theme.islands.count], in: Capsule())
            .opacity(playable ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .disabled(!playable)
        .accessibilityLabel(playable ? name : "\(name)，還沒開放")
    }
}
