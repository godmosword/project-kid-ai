import SwiftUI

extension View {
    /// 觀察員工具：只編進 Debug build；Release 完全沒有入口、選單與關卡資訊。
    func observerSupport(store: UnitStore) -> some View {
        #if DEBUG
        modifier(ObserverSupport(store: store))
        #else
        self
        #endif
    }
}

#if DEBUG
/// 入口在進度點上方：兩指長按 3 秒（孩子單指按住離開鍵不會誤開）。
private struct ObserverSupport: ViewModifier {
    let store: UnitStore
    @State private var showMenu = false
    @State private var showDebug = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                VStack(spacing: 4) {
                    TwoFingerHold(duration: 3) { showMenu = true }
                        .frame(width: 180, height: Theme.touch)
                        .padding(.top, 8)
                        .accessibilityHidden(true)
                    if showDebug {
                        Text("\(store.engine.beat.id)｜嘗試 \(store.engine.attemptsUsed)｜\(TrialClock.seconds(since: store.startedAt)) 秒")
                            .font(.caption.monospaced())
                            .foregroundStyle(Theme.inkSecondary)
                            .allowsHitTesting(false)
                    }
                }
            }
            .sheet(isPresented: $showMenu) { ObserverMenu(store: store, showDebug: $showDebug) }
    }
}

/// SwiftUI 沒有多指長按，用 UIKit 的手勢；單指觸碰不會觸發。
private struct TwoFingerHold: UIViewRepresentable {
    let duration: TimeInterval
    let action: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let gesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.fire(_:)))
        gesture.numberOfTouchesRequired = 2
        gesture.minimumPressDuration = duration
        view.addGestureRecognizer(gesture)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    @MainActor
    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }

        @objc func fire(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began { action() }
        }
    }
}

/// 觀察員選單：試玩時給大人用，不保存任何資料。
struct ObserverMenu: View {
    let store: UnitStore
    @Binding var showDebug: Bool
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Toggle("顯示關卡資訊（beat、嘗試次數、秒數）", isOn: $showDebug)
                Section("跳到") {
                    ForEach(Array(store.engine.content.unit.beats.enumerated()), id: \.offset) { index, beat in
                        Button("\(index + 1). \(beat.id)") {
                            store.jump(to: index)
                            dismiss()
                        }
                    }
                }
                Section {
                    Button("重玩本單元") {
                        store.jump(to: 0)
                        dismiss()
                    }
                }
                Section {
                    Text("換下一位孩子：把 App 滑掉重開，進度就會歸零。").font(.footnote)
                }
            }
            .navigationTitle("觀察員")
            .toolbar { Button("關閉") { dismiss() } }
        }
    }
}
#endif
