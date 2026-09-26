import SwiftUI

@main
struct KidsAIApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                // 進背景時遮住畫面：多工切換的縮圖不留下孩子的選擇與家長卡
                .overlay { if scenePhase != .active { PrivacyCover() } }
        }
    }
}

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        if let error = model.loadError {
            ContentUnavailableView("內容載入失敗（請大人處理）", systemImage: "exclamationmark.triangle", description: Text(error))
        } else if let store = model.active {
            UnitView(store: store, onFinish: model.finishActive, onExit: { model.active = nil })
                .id(ObjectIdentifier(store))
        } else {
            MapView(model: model)
        }
    }
}

private struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            DianDian(size: 96)
        }
    }
}
