import SwiftUI
import UIKit

/// 拖曳畫面：上面是目標（空格、組、1／2／3 號位），下面是卡片區。
/// 點卡片＝選起來＋聽；再點目標（或目標裡的卡）＝放上去；也可以直接拖。
/// 最大字級只用點選（不和捲動搶手勢）；VoiceOver 用「放到〇〇」動作。
struct DragView: View {
    let store: UnitStore
    let focus: HeadingFocus
    @State private var frames: [String: CGRect] = [:]
    @State private var dragging: String?
    @State private var dragGeneration: Int?
    @State private var hovered: String?
    @State private var returnedVisible = false
    @GestureState private var dragOffset: CGSize = .zero
    @GestureState private var gestureActive = false
    @AccessibilityFocusState private var feedbackFocused: Bool
    @Namespace private var cardSpace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.contentWidth) private var contentWidth

    static let targetsID = "dragTargets"

    var body: some View {
        if let drag = store.engine.dragBeat, case .drag(let d) = store.phase {
            VStack(spacing: 16) {
                Text(drag.prompt.zhHant)
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused(focus)
                targets(drag, d)
                    .id(Self.targetsID)
                    .zIndex(dragging.map { d.placements[$0] != nil } == true ? 1 : 0)
                tray(drag, d)
                    .zIndex(dragging.map { d.placements[$0] == nil } == true ? 1 : 0)
                NarratorLine(store: store, item: feedback(drag, d))
                    .accessibilityFocused($feedbackFocused)
            }
            .coordinateSpace(name: DragArea.name)
            .onPreferenceChange(DragFrameKey.self) { value in
                MainActor.assumeIsolated { frames = value }
            }
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .easeOut(duration: 0.35), value: d)
            .sensoryFeedback(.impact(weight: .light), trigger: d.placements.count) { old, new in new > old }
            .onChange(of: store.isDragging) { _, isDragging in
                if !isDragging { clearDrag() }
            }
            .onChange(of: gestureActive) { _, active in
                // 手勢被系統取消（沒有 onEnded）：結束這次拖曳，卡片回原位
                if !active, let generation = dragGeneration {
                    clearDrag()
                    store.endDrag(generation)
                }
            }
            .onChange(of: d.attempts) { _, _ in flashReturned() }
            .onChange(of: d.outcome) { _, _ in focusFeedback() }
            .onChange(of: d.placements) { old, new in announcePlacements(old, new, drag) }
        }
    }

    // MARK: - 目標

    @ViewBuilder private func targets(_ drag: DragBeat, _ d: DragState) -> some View {
        let targets = store.engine.dragTargets
        switch drag.mode {
        case .order:
            VStack(spacing: 8) { ForEach(targets, id: \.id) { orderSlot($0, drag, d) } }
        case .match, .group:
            if typeSize.isAccessibilitySize {
                VStack(spacing: 12) { ForEach(targets, id: \.id) { box($0, drag, d) } }
            } else {
                HStack(alignment: .top, spacing: 12) { ForEach(targets, id: \.id) { box($0, drag, d) } }
            }
        }
    }

    /// 配對的空格、分組的組：上面是標籤（分組另有圖示），下面放卡。
    private func box(_ target: DragTarget, _ drag: DragBeat, _ d: DragState) -> some View {
        let placed = items(in: target, drag, d)
        let tile = usesTiles(drag) && target.holdsOne
        return VStack(spacing: 8) {
            HStack(spacing: 6) {
                if let icon = DragArt.groupIcons[target.id] { Image(systemName: icon).accessibilityHidden(true) }
                if let label = target.label { Text(label.zhHant) }
            }
            .font(.title3.bold())
            .foregroundStyle(Theme.ink)
            VStack(spacing: 8) {
                ForEach(placed, id: \.id) { card($0, drag, d, style: tile ? .tile(width: tileWidth(drag)) : .strip(showsPlay: false)) }
            }
            .frame(maxWidth: .infinity, minHeight: tile ? tileWidth(drag) : 60)
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .modifier(TargetChrome(isHovered: hovered == target.id, isEmpty: placed.isEmpty,
                               isSpeaking: store.speakingHighlight == target.id) { store.send(.dragTapTarget(target.id)) })
        .reportFrame(target.id)
        .zIndex(dragging.map { d.placements[$0] == target.id } == true ? 1 : 0)
        .accessibilityElement(children: placed.isEmpty ? .ignore : .contain)
        .accessibilityLabel(target.label?.zhHant ?? "")
        .accessibilityValue(placed.isEmpty ? DragA11y.empty : "")
    }

    /// 排序的第幾格：左邊大號數字，右邊放卡。
    private func orderSlot(_ target: DragTarget, _ drag: DragBeat, _ d: DragState) -> some View {
        let placed = items(in: target, drag, d)
        return HStack(spacing: 12) {
            Text("\(target.position ?? 0)")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(Theme.ink, in: Circle())
                .accessibilityHidden(true)
            ZStack {
                ForEach(placed, id: \.id) { card($0, drag, d, style: .row) }
            }
            .frame(maxWidth: .infinity, minHeight: 64)
        }
        .padding(8)
        .modifier(TargetChrome(isHovered: hovered == target.id, isEmpty: placed.isEmpty, isSpeaking: false) {
            store.send(.dragTapTarget(target.id))
        })
        .reportFrame(target.id)
        .zIndex(dragging.map { d.placements[$0] == target.id } == true ? 1 : 0)
        .accessibilityElement(children: placed.isEmpty ? .ignore : .contain)
        .accessibilityLabel(DragA11y.slot(target.position ?? 0))
        .accessibilityValue(placed.isEmpty ? DragA11y.empty : "")
    }

    // MARK: - 卡片區

    private func tray(_ drag: DragBeat, _ d: DragState) -> some View {
        let loose = drag.items.filter { d.placements[$0.id] == nil }
        return Group {
            if usesTiles(drag) {
                HStack(spacing: 12) { ForEach(loose, id: \.id) { card($0, drag, d, style: .tile(width: tileWidth(drag))) } }
            } else {
                VStack(spacing: 8) { ForEach(loose, id: \.id) { card($0, drag, d, style: .strip(showsPlay: true)) } }
            }
        }
        .frame(maxWidth: .infinity, minHeight: loose.isEmpty ? 44 : 64)
        .padding(8)
        .background {
            // 點卡片區的空白處＝把選起的卡放回來（點卡片本身不會觸發）
            RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.neutralRetry.opacity(0.45))
                .onTapGesture { if let selected = d.selected { store.send(.dragReturn(selected)) } }
        }
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius)
            .stroke(hovered == DragArea.tray ? Theme.action : .clear, style: StrokeStyle(lineWidth: 4, dash: [10, 6]))
            .allowsHitTesting(false))
        .reportFrame(DragArea.tray)
        .accessibilityElement(children: .contain)
    }

    /// 圖卡的寬度：最多 140；iPhone SE 縮到一排放得下全部卡（最小 88，D44）。依畫面寬度計算。
    private func tileWidth(_ drag: DragBeat) -> CGFloat {
        let count = CGFloat(max(drag.items.count, 1))
        return min(Theme.optionCard, max(88, ((contentWidth - 16 - 12 * (count - 1)) / count).rounded(.down)))
    }

    /// 有圖的卡用圖卡；最大字級改成「左圖右字」的長條。
    private func usesTiles(_ drag: DragBeat) -> Bool {
        drag.items.contains { $0.image != nil } && !typeSize.isAccessibilitySize
    }

    // MARK: - 卡片

    private func card(_ item: Option, _ drag: DragBeat, _ d: DragState, style: DragCard.Style) -> some View {
        let movable = d.outcome == nil && !d.fixed.contains(item.id) && !store.inputLocked
        let isDragged = dragging == item.id
        return DragCard(item: item, style: style,
                        isSelected: d.selected == item.id, isFixed: d.fixed.contains(item.id),
                        isReturned: returnedVisible && d.returned.contains(item.id), heard: store.hasHeard(item.id),
                        isSpeaking: store.speakingHighlight == item.id,
                        actions: movable ? accessibilityActions(item, d) : [],
                        onTap: { store.send(.dragSelect(item.id)) },
                        onPlay: { store.playSound(of: item) })
            .reportFrame(item.id)
            .matchedGeometryEffect(id: item.id, in: cardSpace, isSource: !reduceMotion)
            .offset(isDragged ? dragOffset : .zero)
            .scaleEffect(isDragged && !reduceMotion ? 1.06 : 1)
            .zIndex(isDragged ? 2 : 0)
            // 最大字級只用點選：拖曳會和捲動搶同一根手指
            .highPriorityGesture(dragGesture(item.id, d), including: movable && !typeSize.isAccessibilitySize ? .all : .subviews)
    }

    private func dragGesture(_ item: String, _ d: DragState) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .named(DragArea.name))
            .updating($dragOffset) { value, offset, _ in
                if dragging == nil || dragging == item { offset = value.translation }
            }
            .updating($gestureActive) { _, active, _ in active = true }
            .onChanged { value in
                // 同一時間只拖一張：第二根手指的拖曳直接忽略
                if dragging == nil {
                    dragging = item
                    dragGeneration = store.beginDrag()
                }
                guard dragging == item else { return }
                hovered = dropTarget(item, value.translation, d)
            }
            .onEnded { value in
                guard dragging == item, let generation = dragGeneration else { return }
                let target = dropTarget(item, value.translation, d)
                clearDrag()
                // 進背景或跳關後，這次拖曳已作廢：不放卡、不檢查（CRITICAL-12）
                if store.isCurrentDrag(generation) { drop(item, on: target, d) }
                store.endDrag(generation)
            }
    }

    /// 放開時落到哪裡：目標外擴 24pt 後，和卡片重疊最多的那一個；
    /// 卡片原本所在的位置不算，拖一小段就能放進隔壁格。都沒碰到就回原位。
    private func dropTarget(_ item: String, _ translation: CGSize, _ d: DragState) -> String? {
        guard let origin = frames[item] else { return nil }
        let moved = origin.offsetBy(dx: translation.width, dy: translation.height)
        let home = d.placements[item] ?? DragArea.tray
        let ids = (store.engine.dragTargets.map(\.id) + [DragArea.tray]).filter { $0 != home }
        return ids.compactMap { id -> (String, CGFloat)? in
            guard let frame = frames[id] else { return nil }
            let overlap = frame.insetBy(dx: -24, dy: -24).intersection(moved)
            return overlap.isNull || overlap.isEmpty ? nil : (id, overlap.width * overlap.height)
        }
        .max { $0.1 < $1.1 }?.0
    }

    private func drop(_ item: String, on target: String?, _ d: DragState) {
        switch target {
        case nil: break
        case DragArea.tray?: if d.placements[item] != nil { store.send(.dragReturn(item)) }
        case let id?: store.send(.dragPlace(item: item, target: id))
        }
    }

    private func clearDrag() {
        dragging = nil
        dragGeneration = nil
        hovered = nil
    }

    // MARK: - VoiceOver

    private func accessibilityActions(_ item: Option, _ d: DragState) -> [DragCard.Action] {
        var actions = store.engine.dragTargets.map { target in
            let name = target.label?.zhHant ?? DragA11y.slot(target.position ?? 0)
            return DragCard.Action(name: DragA11y.placeOn(name)) {
                store.send(.dragPlace(item: item.id, target: target.id))
                if case .drag(let after) = store.phase, after.placements[item.id] != target.id {
                    UIAccessibility.post(notification: .announcement, argument: DragA11y.occupied)
                }
            }
        }
        if d.placements[item.id] != nil {
            actions.append(DragCard.Action(name: DragA11y.backToTray) { store.send(.dragReturn(item.id)) })
        }
        return actions
    }

    /// 每次真的放上去（點、拖、無障礙動作都一樣）才公告「〇〇，放到〇〇」。
    private func announcePlacements(_ old: [String: String], _ new: [String: String], _ drag: DragBeat) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let targets = store.engine.dragTargets
        for item in drag.items {
            guard let targetID = new[item.id], old[item.id] != targetID,
                  let target = targets.first(where: { $0.id == targetID }) else { continue }
            let name = target.label?.zhHant ?? DragA11y.slot(target.position ?? 0)
            UIAccessibility.post(notification: .announcement, argument: DragA11y.placed(item.label.zhHant, name))
        }
    }

    /// 檢查後 VoiceOver 焦點移到回饋。
    private func focusFeedback() {
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            feedbackFocused = true
        }
    }

    /// 退回的卡短暫標示「再試一次」，約 1 秒後恢復（不要讓孩子以為它不能用了）。
    private func flashReturned() {
        returnedVisible = true
        focusFeedback()
        Task {
            try? await Task.sleep(for: .seconds(1))
            returnedVisible = false
        }
    }

    // MARK: - 小工具

    private func items(in target: DragTarget, _ drag: DragBeat, _ d: DragState) -> [Option] {
        drag.items.filter { d.placements[$0.id] == target.id }
    }

    private func feedback(_ drag: DragBeat, _ d: DragState) -> TextItem? {
        switch d.outcome {
        case .success?: drag.feedback.success
        case .revealed?: drag.feedback.reveal
        case nil: d.attempts > 0 ? drag.feedback.notYet : (store.hintShown ? drag.hint : nil)
        }
    }
}
