import XCTest

// 每支流程：啟動參數只準備前置狀態 → Frames.begin() → 真實點擊（Frames.tap）→ 等最終狀態（Frames.until）→ Frames.end()。

/// 地圖 → 點認識島 → 進入單元 1。
final class FlowMapToUnit1: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch()
        let island = Flow.element(app, "map.island.0")
        Flow.waitHittable(island)
        Frames.begin()
        Frames.tap(island)
        let exit = Flow.element(app, "unit.exit")
        Frames.until("進入單元 1") { Flow.hittable(exit) && !island.exists }
        Frames.end()
    }
}

/// 單元 1 一起說：按「一起說」→ 念完變成「再說一次」，也可以下一步。
final class FlowSayTogether: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 3)
        let button = Flow.element(app, "say.button")
        Flow.waitHittable(button)
        Frames.begin()
        Frames.tap(button)
        let next = Flow.element(app, "unit.next")
        Frames.until("按鈕變成再說一次、出現下一步") { Flow.hittable(button) && button.label.contains("再說一次") && Flow.hittable(next) }
        Frames.end()
    }
}

/// 單元 2 沙盒：選「貓」→ 猜猜帽猜 → 反應「比較像」→ 下一步 → 第二張卡自動選好、等孩子反應。
final class FlowSandboxPickAndReact: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 1, beat: 5)
        let card = Flow.element(app, "option.prompt_vague")
        Flow.waitHittable(card)
        Frames.begin()
        Frames.tap(card)
        let closer = Flow.element(app, "option.closer")
        Frames.until("猜測念完、出現反應鈕") { Flow.hittable(closer) }
        let next = Flow.element(app, "unit.next")
        Frames.tap(closer, until: "選了比較像") { closer.isSelected || Flow.hittable(next) }
        Frames.until("反應完、出現下一步") { Flow.hittable(next) }
        Frames.tap(next, until: "換到第二張卡") { !next.exists }
        Frames.until("第二張卡：反應鈕出現、還不能下一步") { Flow.hittable(closer) && !next.exists }
        Frames.end()
    }
}

/// 單元 2 拖曳（點選放卡）：點卡 → 點空格，兩張都放好 → 自動檢查 → 成功回饋與下一步。
final class FlowDragTapToPlace: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 1, beat: 2)
        let cup = Flow.element(app, "drag.card.cup_star")
        Flow.waitHittable(cup)
        Frames.begin()
        place(app, card: "drag.card.cup_star", target: "drag.target.blank_what")
        place(app, card: "drag.card.place_table", target: "drag.target.blank_where")
        let feedback = Flow.element(app, "feedback")
        let next = Flow.element(app, "unit.next")
        Frames.until("自動檢查後出現回饋與下一步") { feedback.exists && Flow.hittable(next) }
        Frames.end()
    }
}

/// 點選放卡：點卡（選起來）→ 點空格（放進去）。空格放了卡以後就不再是「還沒有卡片」。
@MainActor
private func place(_ app: XCUIApplication, card id: String, target targetID: String) {
    let card = Flow.element(app, id)
    let target = Flow.element(app, targetID)
    Frames.tap(card, until: "選起 \(id)") { card.isSelected }
    Frames.tap(target, until: "放進 \(targetID)") { (target.value as? String) != "還沒有卡片" }
}

/// 單元 1 故事：念完第一段 → 下一步 → 出現分歧 → 點第一個選項 → 故事往下走。
final class FlowStoryBranch: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 6)
        let next = Flow.element(app, "unit.next")
        Flow.waitHittable(next)
        Frames.begin()
        Frames.tap(next)
        let choice = Flow.first(app, prefix: "story.choice.")
        Frames.until("出現故事分歧") { Flow.hittable(choice) }
        let id = choice.identifier
        let chosen = Flow.element(app, id)
        Frames.tap(chosen, until: "故事往下一個節點") { !chosen.exists }
        Frames.end()
    }
}

/// 單元 1 貼紙頁：回地圖 → 認識島完成、提問島解鎖。
final class FlowSticker: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 8)
        let back = Flow.element(app, "unit.backToMap")
        Flow.waitHittable(back)
        Frames.begin()
        let island = Flow.element(app, "map.island.1")
        Frames.tap(back, until: "回到地圖") { island.exists }
        Frames.until("回到地圖、提問島可以點") { Flow.hittable(island) }
        Frames.end()
    }
}

/// `control-kidsai snapshot`：把目前畫面的無障礙元素樹寫到握手資料夾（tree.txt）。
/// 前置狀態由 `TEST_RUNNER_KIDSAI_LAUNCH` 傳入（例如 "-openUnit 1 -beat 5"）。
final class SnapshotTree: FlowTestCase {
    @MainActor
    func testSnapshot() {
        let arguments = (ProcessInfo.processInfo.environment["KIDSAI_LAUNCH"] ?? "").split(separator: " ").map(String.init)
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        Flow.waitHittable(Flow.element(app, arguments.isEmpty ? "map.island.0" : "unit.exit"))
        guard let directory = Handshake.directory else { return }
        try? app.debugDescription.write(to: directory.appendingPathComponent("tree.txt"), atomically: true, encoding: .utf8)
    }
}
