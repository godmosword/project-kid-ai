import SwiftUI
import UIKit

/// 一個單元：頂列（長按離開、進度、🔊）＋本關內容＋下方主按鈕。
struct UnitView: View {
    @State var store: UnitStore
    let onFinish: () -> Void
    let onExit: () -> Void
    @State private var shownScreen = ""
    @AccessibilityFocusState private var headingFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let topID = "top"
    private static let bottomID = "bottom"

    var body: some View {
        VStack(spacing: 0) {
            topBar
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: 1).id(Self.topID)
                        content
                            .id(store.engine.beatIndex)
                            .transition(.opacity)
                        Color.clear.frame(height: 1).id(Self.bottomID)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .frame(maxWidth: 700)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: store.phase) { follow(proxy) }
                .onChange(of: store.hintShown) { _, shown in
                    if shown { scroll(proxy, to: Self.bottomID) }
                }
                .onChange(of: store.isNarrating) { _, narrating in
                    // 沙盒的反應鈕在猜測念完才出現：捲到看得到的地方
                    if !narrating, case .sandbox = store.phase { scroll(proxy, to: Self.bottomID) }
                }
            }
            bottomBar
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: store.engine.beatIndex)
        .background(Theme.bg.ignoresSafeArea())
        .observerSupport(store: store)
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            store.start()
            shownScreen = store.screenKey
            focusHeading()
        }
        .onDisappear {
            store.pause()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.resume() } else { store.pause() }
        }
    }

    @ViewBuilder private var content: some View {
        switch store.phase {
        case .question: QuestionView(store: store, focus: $headingFocused)
        case .sayTogether: SayTogetherView(store: store, focus: $headingFocused)
        case .sandbox: SandboxView(store: store, focus: $headingFocused)
        case .story: StoryView(store: store, focus: $headingFocused)
        case .sticker, .finished: StickerView(store: store, focus: $headingFocused)
        case .lines: LinesView(store: store, focus: $headingFocused)
        }
    }

    /// 換了畫面：回到最上面、VoiceOver 焦點移到題目；同一畫面多了回饋：捲到下面。
    private func follow(_ proxy: ScrollViewProxy) {
        if store.screenKey != shownScreen {
            shownScreen = store.screenKey
            scroll(proxy, to: Self.topID)
            focusHeading()
        } else {
            scroll(proxy, to: Self.bottomID)
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to id: String) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: id == Self.topID ? .top : .bottom) }
    }

    private func focusHeading() {
        headingFocused = false
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            headingFocused = true
        }
    }

    private var topBar: some View {
        HStack {
            HoldToExitButton(action: onExit)
            Spacer()
            ProgressDots(current: store.engine.beatIndex, total: store.engine.content.unit.beats.count)
            Spacer()
            IconButton(systemImage: "speaker.wave.2.fill", label: "再念一次", action: store.replay)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    @ViewBuilder private var bottomBar: some View {
        VStack(spacing: 8) {
            if store.phase == .sticker || store.phase == .finished {
                if !store.coolingDown {
                    PrimaryButton(title: "回地圖", systemImage: "map.fill") {
                        store.send(.next)
                        onFinish()
                    }
                }
            } else {
                if case .sayTogether(let done) = store.phase, !store.inputLocked {
                    PrimaryButton(title: done ? "再說一次" : "一起說", systemImage: "mouth.fill", secondary: done) {
                        store.send(.sayTogether)
                    }
                }
                if store.canShowNext {
                    PrimaryButton(title: "下一步", systemImage: "arrow.right") { store.send(.next) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .frame(minHeight: Theme.touch + 24)
    }
}

enum TrialClock {
    static func seconds(since start: ContinuousClock.Instant) -> Int {
        Int((ContinuousClock.now - start).components.seconds)
    }
}

/// 進度點：目前在第幾關。
struct ProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule().fill(index <= current ? Theme.ink : Theme.neutralRetry).frame(width: 18, height: 8)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("第 \(current + 1) 關，共 \(total) 關")
    }
}

/// 離開要長按 1.5 秒（有一圈進度），避免孩子誤觸而整個單元重來。
/// 手指可以滑動一些（80pt）；輕點或太早放開時提示「按住不放」。
struct HoldToExitButton: View {
    let action: () -> Void
    @State private var holding = false
    @State private var showHint = false
    @State private var hintToken = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().fill(Theme.surface)
            Circle().stroke(Theme.cardStroke, lineWidth: 2)
            Circle()
                .trim(from: 0, to: holding ? 1 : 0)
                .stroke(Theme.ink, lineWidth: 4)
                .rotationEffect(.degrees(-90))
                .animation(holding ? .linear(duration: 1.5) : (reduceMotion ? nil : .easeOut(duration: 0.2)), value: holding)
            Image(systemName: "xmark").font(.title2.bold()).foregroundStyle(Theme.ink)
        }
        .frame(width: Theme.touch, height: Theme.touch)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: 1.5, maximumDistance: 80, perform: action) { pressing in
            holding = pressing
            if !pressing { flashHint() }
        }
        .overlay(alignment: .topLeading) {
            if showHint {
                Text("按住不放")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.ink, in: Capsule())
                    .fixedSize()
                    .offset(y: Theme.touch + 6)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("回地圖（長按）")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "回地圖", action)
    }

    private func flashHint() {
        hintToken += 1
        let token = hintToken
        showHint = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            if token == hintToken { showHint = false }
        }
    }
}
