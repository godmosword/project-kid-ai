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

/// 單元 1 第 1 關選擇題：先點錯「家人」→ 變淡、點點說再聽一次；再點對「AI」→ 打勾、出現下一步。
final class FlowChoiceAnswer: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 1)
        let wrong = Flow.element(app, "option.family")
        let right = Flow.element(app, "option.ai")
        let feedback = Flow.element(app, "feedback")
        let next = Flow.element(app, "unit.next")
        Flow.waitHittable(wrong)
        Frames.begin()
        Frames.tap(wrong, until: "家人變淡") { wrong.exists && !wrong.isEnabled }
        Frames.until("點點說再聽一次、還沒有下一步") { feedback.exists && feedback.label.contains("再聽一次") && !next.exists }
        Frames.tap(right, until: "AI 打勾") { right.isSelected }
        Frames.until("出現下一步") { Flow.hittable(next) }
        Frames.end()
    }
}

/// 單元 3 有對錯的沙盒：AI 說「小狗有三隻腳」（說錯）→ 點「同意」變淡、還不能下一步 → 點「抓到了」→ 出現下一步。
final class FlowSandboxGraded: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 2, beat: 5)
        let agree = Flow.element(app, "option.agree")
        let caught = Flow.element(app, "option.catch")
        let feedback = Flow.element(app, "feedback")
        let next = Flow.element(app, "unit.next")
        Flow.waitHittable(agree)
        Frames.begin()
        Frames.tap(agree, until: "同意變淡") { agree.exists && !agree.isEnabled }
        Frames.until("點點說再看看圖、還沒有下一步") { feedback.exists && feedback.label.contains("再看看圖") && !next.exists }
        Frames.tap(caught, until: "選了抓到了") { caught.isSelected }
        Frames.until("出現下一步") { Flow.hittable(next) }
        Frames.end()
    }
}

/// 長按左上 X（App 要 1.5 秒）→ 回地圖。
final class FlowHoldToExit: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 0)
        let exit = Flow.element(app, "unit.exit")
        Flow.waitHittable(exit)
        Frames.begin()
        Frames.press(exit, forDuration: 2)
        let island = Flow.element(app, "map.island.0")
        Frames.until("回到地圖") { Flow.hittable(island) && !exit.exists }
        Frames.end()
    }
}

/// 單元 1 一起說：按 Home 進背景 → 回到 App → 還在同一關（「一起說」還在）。
final class FlowBackgroundResume: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 3)
        let button = Flow.element(app, "say.button")
        Flow.waitHittable(button)
        Frames.begin()
        XCUIDevice.shared.press(.home)
        // iOS 27 模擬器上 app.state 按 Home 後仍回報前景，改看 App 的按鈕點不點得到
        Frames.until("App 進背景、看到主畫面") { !Flow.hittable(button) }
        Frames.snap()
        Frames.snap()
        app.activate()
        Frames.until("回到同一關") { Flow.hittable(button) }
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
