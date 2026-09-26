import Foundation

/// 拖曳的規則（配對、分組、排序）：只回傳新狀態與要念的話，由 `UnitEngine` 寫回。
/// 點和拖用同一組事件；全部放好才檢查（D39），檢查一次算一次作答。
extension UnitEngine {
    /// 排序的格子不在內容裡，用引擎自己的 id（不會和內容 id 衝突）。
    static let orderSlotPrefix = "_order_slot_"

    var dragBeat: DragBeat? {
        if case .drag(let d) = beat.kind { return d }
        return nil
    }

    var dragTargets: [DragTarget] {
        guard let drag = dragBeat else { return [] }
        switch drag.mode {
        case .match(let targets, _):
            return targets.map { DragTarget(id: $0.id, label: $0.label, image: $0.image, position: nil, holdsOne: true) }
        case .group(let groups, _):
            return groups.map { DragTarget(id: $0.id, label: $0.label, image: $0.image, position: nil, holdsOne: false) }
        case .order(let correct, _):
            return correct.indices.map { DragTarget(id: Self.orderSlotPrefix + "\($0 + 1)", label: nil, image: nil, position: $0 + 1, holdsOne: true) }
        }
    }

    /// 題目 → 有聲音的卡依序播放 → 依序念出各目標（🔊 重念也用這個）。
    func dragPrompt() -> [SpeechLine] {
        guard let drag = dragBeat else { return [] }
        let labels = dragTargets.compactMap { target in target.label.map { (id: target.id, text: $0) } }
        return say([drag.prompt]) + soundLines(drag.items) + labelLines(labels)
    }

    /// 全部放好、沒有選起的卡、還沒結算，才可以檢查。
    func dragReadyToCheck(_ d: DragState) -> Bool {
        guard let drag = dragBeat, d.outcome == nil, d.selected == nil else { return false }
        return drag.items.allSatisfy { d.placements[$0.id] != nil }
    }

    func dragStep(_ d: DragState, _ event: EngineEvent) -> (DragState, [SpeechLine])? {
        guard let drag = dragBeat else { return nil }
        switch event {
        case .dragSelect(let id):
            guard let item = drag.items.first(where: { $0.id == id }) else { return nil }
            // 已選起一張卡、又點到另一張放好的卡：等於「放到那張卡所在的位置」（交換或放進同一組）
            if let selected = d.selected, selected != id, d.outcome == nil, let target = d.placements[id] {
                return place(d, selected, target)
            }
            var n = d
            // 點＝選起來＋播放；固定的卡或已結算時只播放
            n.selected = d.fixed.contains(id) || d.outcome != nil || d.selected == id ? nil : id
            return (n, itemLines(item))
        case .dragTapTarget(let targetID):
            guard let target = dragTargets.first(where: { $0.id == targetID }) else { return nil }
            if let selected = d.selected, d.outcome == nil { return place(d, selected, targetID) }
            return (d, target.label.map { labelLines([(targetID, $0)]) } ?? [])
        case .dragPlace(let item, let targetID):
            guard d.outcome == nil else { return nil }
            return place(d, item, targetID)
        case .dragReturn(let item):
            guard d.outcome == nil, !d.fixed.contains(item), d.placements[item] != nil || d.selected == item else { return nil }
            var n = d
            n.placements[item] = nil
            n.selected = nil
            n.returned.remove(item)
            return (n, [])
        case .dragCheck:
            guard dragReadyToCheck(d) else { return nil }
            return check(d, drag)
        case .dragDeselect:
            guard d.selected != nil else { return nil }
            var n = d
            n.selected = nil
            return (n, [])
        default:
            return nil
        }
    }

    /// 點卡片時念的話：有聲音念聲音裡的句子，沒有就念卡名。
    private func itemLines(_ item: Option) -> [SpeechLine] {
        if let script = item.soundScript {
            return [SpeechLine(text: script, role: .sound(key: item.sound ?? ""), highlight: item.id)]
        }
        return labelLines([(item.id, item.label)])
    }

    /// 放上去。一格只放一張的目標已經有卡時交換：原本那張回到新卡的來處。
    private func place(_ d: DragState, _ item: String, _ targetID: String) -> (DragState, [SpeechLine])? {
        guard let drag = dragBeat, drag.items.contains(where: { $0.id == item }), !d.fixed.contains(item),
              let target = dragTargets.first(where: { $0.id == targetID }) else { return nil }
        var n = d
        let origin = n.placements[item]
        n.selected = nil
        guard origin != targetID else { return (n, []) }
        if target.holdsOne, let occupant = n.placements.first(where: { $0.value == targetID })?.key {
            guard !n.fixed.contains(occupant) else { return nil }
            n.placements[occupant] = origin
            n.returned.remove(occupant)
        }
        n.placements[item] = targetID
        n.returned.remove(item)
        return (n, [])
    }

    private func check(_ d: DragState, _ drag: DragBeat) -> (DragState, [SpeechLine]) {
        var n = d
        n.selected = nil
        n.returned = []
        let allItems = Set(drag.items.map(\.id))
        if accepted(d.placements, drag) {
            n.outcome = .success
            n.fixed = allItems
            return (n, say([drag.feedback.success].compactMap { $0 }))
        }
        n.attempts += 1
        if n.attempts >= drag.attempts.max {
            n.placements = canonicalPlacements(drag)
            n.fixed = allItems
            n.outcome = .revealed
            return (n, say([drag.feedback.reveal].compactMap { $0 }))
        }
        // 放對的固定住、放錯的回卡片區，接著重播退回的有聲卡
        let expected = closestAnswer(d.placements, drag)
        let wrong = allItems.filter { d.placements[$0] != expected[$0] }
        n.fixed.formUnion(allItems.subtracting(wrong))
        for item in wrong { n.placements[item] = nil }
        n.returned = wrong
        let replay = soundLines(drag.items.filter { wrong.contains($0.id) })
        return (n, say([drag.feedback.notYet].compactMap { $0 }) + replay)
    }

    private func accepted(_ placements: [String: String], _ drag: DragBeat) -> Bool {
        switch drag.mode {
        case .match(_, let pairs): return placements == pairs
        case .group(_, let assignments): return placements == assignments
        case .order(let correct, let alternatives):
            return ([correct] + alternatives).contains { placements == orderPlacements($0) }
        }
    }

    /// 部分答錯時拿來比對的答案：排序取「位置對得最多」的順序，平手取 correct_order（和揭曉句一致）。
    private func closestAnswer(_ placements: [String: String], _ drag: DragBeat) -> [String: String] {
        guard case .order(let correct, let alternatives) = drag.mode else { return canonicalPlacements(drag) }
        let candidates = ([correct] + alternatives).map(orderPlacements)
        let score = { (answer: [String: String]) in answer.filter { placements[$0.key] == $0.value }.count }
        return candidates.dropFirst().reduce(candidates[0]) { best, next in score(next) > score(best) ? next : best }
    }

    /// 揭曉時的擺法：配對、分組照答案；排序一律用 correct_order。
    func canonicalPlacements(_ drag: DragBeat) -> [String: String] {
        switch drag.mode {
        case .match(_, let pairs): pairs
        case .group(_, let assignments): assignments
        case .order(let correct, _): orderPlacements(correct)
        }
    }

    private func orderPlacements(_ order: [String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, Self.orderSlotPrefix + "\($0.offset + 1)") })
    }
}
