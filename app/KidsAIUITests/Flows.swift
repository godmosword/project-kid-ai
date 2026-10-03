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

/// 單元 2 沙盒兩張卡都玩完：選卡 → 反應 → 下一步 → 第二張卡反應 → 「我想要的」與兩張猜猜帽的圖並排比較（D37）。
final class FlowSandboxCompare: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 1, beat: 5)
        let card = Flow.element(app, "option.prompt_vague")
        Flow.waitHittable(card)
        Frames.begin()
        Frames.tap(card)
        let closer = Flow.element(app, "option.closer")
        let next = Flow.element(app, "unit.next")
        Frames.until("猜測念完、出現反應鈕") { Flow.hittable(closer) }
        Frames.tap(closer, until: "第一張卡反應完、出現下一步") { Flow.hittable(next) }
        Frames.tap(next, until: "換到第二張卡") { !next.exists }
        Frames.until("第二張卡：反應鈕出現") { Flow.hittable(closer) }
        let comparison = Flow.element(app, "sandbox.comparison")
        Frames.tap(closer, until: "出現三張圖的比較") { comparison.exists }
        Frames.until("揭曉句念完、出現下一步") { Flow.hittable(next) }
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

/// 單元 3 分組（點選放卡）：四張有聲音的長條卡依序放進「留下／要改正」→ 自動檢查 → 成功回饋與下一步。
final class FlowDragGroup: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 2, beat: 2)
        let first = Flow.element(app, "drag.card.fish")
        Flow.waitHittable(first)
        Frames.begin()
        for (card, group) in [("fish", "keep"), ("square_moon", "fix"), ("hot_ice", "fix"), ("bright_sun", "keep")] {
            placeInGroup(app, card: "drag.card.\(card)", group: "drag.target.\(group)")
        }
        let feedback = Flow.element(app, "feedback")
        let next = Flow.element(app, "unit.next")
        Frames.until("自動檢查後出現回饋與下一步") { feedback.exists && Flow.hittable(next) }
        Frames.end()
    }
}

/// 分組的組可以放很多張：放進去以後，那張卡會在組裡（組有卡時是容器）。
/// 點組上方的標題區，不點中心：中心可能是組裡已有的卡（沒選著卡時點到它會把它拿起來）。
@MainActor
private func placeInGroup(_ app: XCUIApplication, card id: String, group groupID: String) {
    let card = Flow.element(app, id)
    let group = Flow.element(app, groupID)
    Frames.tap(card, until: "選起 \(id)") { card.isSelected }
    Frames.tap(group, at: CGVector(dx: 0.5, dy: 0.08), until: "放進 \(groupID)") {
        group.descendants(matching: .any)[id].exists
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

/// 單元 1 第 1 關選擇題錯兩次：點「家人」→ 變淡；再點「電子玩具」→ 錯到上限，揭曉「AI」並打勾、出現下一步。
/// 第二次點錯的選項不會變淡（標成孩子選的），所以第二下等的是揭曉。
final class FlowChoiceReveal: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 1)
        let first = Flow.element(app, "option.family")
        let second = Flow.element(app, "option.toy")
        let answer = Flow.element(app, "option.ai")
        let feedback = Flow.element(app, "feedback")
        let next = Flow.element(app, "unit.next")
        Flow.waitHittable(first)
        Frames.begin()
        Frames.tap(first, until: "家人變淡") { first.exists && !first.isEnabled }
        Frames.tap(second, until: "揭曉 AI 並打勾") { answer.isSelected }
        Frames.until("點點說是 AI") { feedback.exists && feedback.label.contains("是 AI") }
        Frames.until("出現下一步") { Flow.hittable(next) }
        Frames.end()
    }
}

/// 單元 1 沙盒（沒有對錯）：猜猜帽猜完 → 點「好像對」→ 選起來、出現下一步。
final class FlowSandboxOpen: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 5)
        let reaction = Flow.element(app, "option.seem_right")
        let next = Flow.element(app, "unit.next")
        Flow.waitHittable(reaction)
        Frames.begin()
        Frames.tap(reaction, until: "選了好像對") { reaction.isSelected }
        Frames.until("出現下一步") { Flow.hittable(next) }
        Frames.end()
    }
}

/// 單元 1 故事走到結局：下一步 → 再猜一次 → 下一步 → 給它提示圖 → 床 → 「襪子找到了！」、出現下一步。
final class FlowStoryEnding: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 6)
        let next = Flow.element(app, "unit.next")
        Flow.waitHittable(next)
        Frames.begin()
        // 點了的效果要馬上看得到（按鈕或選項消失）；分歧要等旁白念完才出現，另外等
        let guessAgain = Flow.element(app, "story.choice.guess_again")
        Frames.tap(next, until: "往第一個分歧") { !next.exists }
        Frames.until("出現第一個分歧") { Flow.hittable(guessAgain) }
        Frames.tap(guessAgain, until: "往下一段") { !guessAgain.exists }
        let giveHint = Flow.element(app, "story.choice.give_hint")
        Frames.until("念完、出現下一步") { Flow.hittable(next) }
        Frames.tap(next, until: "往第二個分歧") { !next.exists }
        Frames.until("出現第二個分歧") { Flow.hittable(giveHint) }
        let bed = Flow.element(app, "story.choice.hint_bed")
        Frames.tap(giveHint, until: "往提示圖") { !giveHint.exists }
        Frames.until("出現提示圖") { Flow.hittable(bed) }
        let ending = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "襪子找到了")).firstMatch
        Frames.tap(bed, until: "走到結局") { ending.exists }
        Frames.until("結局念完、出現下一步") { Flow.hittable(next) }
        Frames.end()
    }
}

/// 單元 1 回顧題：先點錯「什麼都知道」→ 變淡；再點對「會猜的幫手」→ 打勾、出現下一步。
final class FlowReviewAnswer: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 7)
        let wrong = Flow.element(app, "option.know_all")
        let right = Flow.element(app, "option.helper")
        let next = Flow.element(app, "unit.next")
        Flow.waitHittable(wrong)
        Frames.begin()
        Frames.tap(wrong, until: "什麼都知道變淡") { wrong.exists && !wrong.isEnabled }
        Frames.tap(right, until: "會猜的幫手打勾") { right.isSelected }
        Frames.until("出現下一步") { Flow.hittable(next) }
        Frames.end()
    }
}

/// 單元 4 排序（點選放卡）：出門玩 → 1、下雨了 → 2、撐起傘 → 3 → 自動檢查 → 成功回饋與下一步。
final class FlowDragOrder: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 3, beat: 2)
        let first = Flow.element(app, "drag.card.go_out")
        Flow.waitHittable(first)
        Frames.begin()
        for (index, card) in ["go_out", "rain", "umbrella"].enumerated() {
            place(app, card: "drag.card.\(card)", target: "drag.target._order_slot_\(index + 1)")
        }
        let feedback = Flow.element(app, "feedback")
        let next = Flow.element(app, "unit.next")
        Frames.until("自動檢查後出現回饋與下一步") { feedback.exists && Flow.hittable(next) }
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

// MARK: - 單元 1 美術進入點（E1）

/// 依無障礙標籤找元素（圖片與說話框沒有 identifier）：`label == text`。
/// 沙盒主題圖與箱子的舞台圖有自己的標籤（內容 JSON 的 `a11y_label`），所以認得出是哪一張卡。
@MainActor
private func labeled(_ app: XCUIApplication, exactly text: String) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", text)).firstMatch
}

/// 依無障礙標籤找元素：`label CONTAINS text`（說話框是角色＋句子合成一個元素）。
@MainActor
private func labeled(_ app: XCUIApplication, containing text: String) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
}

/// 前置狀態的真實點擊：和 `Frames.tap(_:until:)` 一樣點到有效果為止，但**不截圖**。
/// `Frames` 的 tap／until 一呼叫就寫一格（連 `Frames.begin()` 之前也算），所以要證明的動作之前的準備走這裡，
/// 影片裡才只有要證明的那一段；準備也是真的點擊，不用 `-events` 跳過。
@MainActor
private func prepareTap(_ element: XCUIElement, until what: String,
                        file: StaticString = #filePath, line: UInt = #line, _ effect: () -> Bool) {
    for _ in 0..<8 {
        Flow.waitHittable(element, file: file, line: line)
        element.tap()
        let deadline = Date().addingTimeInterval(3)
        repeat {
            if effect() { return }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
    }
    XCTFail("前置點了沒有效果：\(what)", file: file, line: line)
}

/// 前置狀態：等畫面上看得到的條件成立（不截圖；旁白時間不固定，不用固定秒數當前提）。
@MainActor
private func prepareUntil(_ what: String, file: StaticString = #filePath, line: UInt = #line, _ condition: () -> Bool) {
    let deadline = Date().addingTimeInterval(Flow.timeout)
    repeat {
        if condition() { return }
        Thread.sleep(forTimeInterval: 0.3)
    } while Date() < deadline
    XCTFail("前置等不到：\(what)", file: file, line: line)
}

/// 單元 1 第 2 關箱子猜猜看（沒有對錯）：舞台圖只露出耳朵，三個選項（貓咪／小車／香蕉）。
/// 點「貓咪」→ 它標成「你選的」、另外兩個**不會變淡**（這關沒有正解），點點念揭曉句、出現下一步。
final class FlowChoiceBox: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 2)
        let box = labeled(app, exactly: "箱子只露出一小角，看得到尖尖的耳朵")
        let cat = Flow.element(app, "option.cat")
        let car = Flow.element(app, "option.car")
        let banana = Flow.element(app, "option.banana")
        let feedback = Flow.element(app, "feedback")
        let next = Flow.element(app, "unit.next")
        Flow.waitHittable(cat)
        XCTAssertTrue(box.exists, "第 2 關要有箱子的舞台圖")
        XCTAssertTrue(Flow.hittable(car) && Flow.hittable(banana), "三個選項都要能點")
        Frames.begin()
        Frames.tap(cat, until: "貓咪標成你選的") { cat.isSelected }
        Frames.until("點點念揭曉句、出現下一步") {
            feedback.exists && feedback.label.contains("你和 AI 都會猜，有時對有時錯。") && Flow.hittable(next)
        }
        // 沒有對錯：只有孩子選的那個有標記，另外兩個仍可點、沒有打勾
        XCTAssertFalse(car.isSelected || banana.isSelected, "這關沒有正解，不應該有第二個標記")
        XCTAssertTrue(car.isEnabled && banana.isEnabled, "這關答錯不變淡")
        Frames.end()
    }
}

/// 單元 1 第 5 關儀式 → 沙盒第一個主題：儀式頁是猜猜帽大圖＋「猜猜帽時間」，
/// 按「下一步」→ 天氣主題（天氣卡、猜測「我猜今天會出太陽」＋「我不確定」、三個反應鈕）。
final class FlowSandboxRitual: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 4)
        let next = Flow.element(app, "unit.next")
        let hat = labeled(app, exactly: "猜猜帽，AI")
        let ritualLine = labeled(app, containing: "猜猜帽時間")
        let weatherCard = labeled(app, exactly: "天氣卡")
        let weatherGuess = labeled(app, containing: "我猜今天會出太陽")
        let unsureTag = labeled(app, exactly: "我不確定")
        let seemRight = Flow.element(app, "option.seem_right")
        let seemWrong = Flow.element(app, "option.seem_wrong")
        let dontKnow = Flow.element(app, "option.unsure")
        Flow.waitHittable(next)
        XCTAssertTrue(hat.exists, "儀式頁要有猜猜帽的大圖")
        XCTAssertTrue(ritualLine.exists, "儀式頁要有「猜猜帽時間」")
        Frames.begin()
        Frames.tap(next, until: "離開儀式頁") { !next.exists }
        Frames.until("進到天氣主題：天氣卡、猜測與三個反應鈕") {
            weatherCard.exists && weatherGuess.exists && unsureTag.exists && !ritualLine.exists
                && Flow.hittable(seemRight) && Flow.hittable(seemWrong) && Flow.hittable(dontKnow)
        }
        Frames.end()
    }
}

/// 單元 1 沙盒第二個主題（早餐）：天氣那張卡先真的玩完（前置，不錄），
/// 錄「按下一步 → 換成早餐卡」和「對早餐的猜測做反應 → 出現下一步」。
/// 早餐卡用它自己的標籤和猜測句認（反應鈕三個主題共用，不能只看鈕）。
final class FlowSandboxBreakfast: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 5)
        let next = Flow.element(app, "unit.next")
        let seemRight = Flow.element(app, "option.seem_right")
        let weatherCard = labeled(app, exactly: "天氣卡")
        let breakfastCard = labeled(app, exactly: "早餐卡")
        let breakfastGuess = labeled(app, containing: "我猜是麵包配牛奶")
        let unsureTag = labeled(app, exactly: "我不確定")
        let feedback = Flow.element(app, "feedback")
        // 前置：天氣那張卡真的反應一次（不錄），才有「換到下一個主題」可按
        prepareUntil("天氣卡的反應鈕出現") { weatherCard.exists && Flow.hittable(seemRight) }
        prepareTap(seemRight, until: "天氣卡選了好像對") { seemRight.isSelected }
        prepareUntil("天氣卡做完、出現下一步") { Flow.hittable(next) }
        Frames.begin()
        Frames.tap(next, until: "離開天氣卡") { !next.exists }
        Frames.until("換成早餐卡：早餐的猜測念完、反應鈕出現、還不能下一步") {
            breakfastCard.exists && !weatherCard.exists && breakfastGuess.exists && unsureTag.exists
                && Flow.hittable(seemRight) && !seemRight.isSelected && !next.exists
        }
        Frames.tap(seemRight, until: "早餐卡選了好像對") { seemRight.isSelected }
        Frames.until("揭曉句念完、出現下一步") {
            feedback.exists && feedback.label.contains("AI 會猜，有時猜對，有時猜錯。") && Flow.hittable(next)
        }
        Frames.end()
    }
}

/// 單元 1 沙盒第三個主題（動物影子）：天氣、早餐兩張卡先真的玩完（前置，不錄），
/// 錄「按下一步 → 換成動物影子卡」和「點『好像錯』→ 出現下一步」。
final class FlowSandboxAnimal: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 5)
        let next = Flow.element(app, "unit.next")
        let seemRight = Flow.element(app, "option.seem_right")
        let seemWrong = Flow.element(app, "option.seem_wrong")
        let weatherCard = labeled(app, exactly: "天氣卡")
        let breakfastCard = labeled(app, exactly: "早餐卡")
        let animalCard = labeled(app, exactly: "動物影子卡")
        let animalGuess = labeled(app, containing: "我猜是一隻狐狸")
        let unsureTag = labeled(app, exactly: "我不確定")
        let feedback = Flow.element(app, "feedback")
        // 前置：天氣、早餐兩張卡都真的反應過（不錄）
        prepareUntil("天氣卡的反應鈕出現") { weatherCard.exists && Flow.hittable(seemRight) }
        prepareTap(seemRight, until: "天氣卡選了好像對") { seemRight.isSelected }
        prepareUntil("天氣卡做完、出現下一步") { Flow.hittable(next) }
        prepareTap(next, until: "離開天氣卡") { !next.exists }
        prepareUntil("換成早餐卡、反應鈕出現") {
            breakfastCard.exists && !weatherCard.exists && Flow.hittable(seemRight) && !seemRight.isSelected
        }
        prepareTap(seemRight, until: "早餐卡選了好像對") { seemRight.isSelected }
        prepareUntil("早餐卡做完、出現下一步") { Flow.hittable(next) }
        Frames.begin()
        Frames.tap(next, until: "離開早餐卡") { !next.exists }
        Frames.until("換成動物影子卡：猜測念完、反應鈕出現、還不能下一步") {
            animalCard.exists && !breakfastCard.exists && animalGuess.exists && unsureTag.exists
                && Flow.hittable(seemWrong) && !seemWrong.isSelected && !next.exists
        }
        Frames.tap(seemWrong, until: "動物影子卡選了好像錯") { seemWrong.isSelected }
        Frames.until("揭曉句念完、出現下一步") {
            feedback.exists && feedback.label.contains("AI 會猜，有時猜對，有時猜錯。") && Flow.hittable(next)
        }
        Frames.end()
    }
}

/// 單元 1 故事：真的走到提示圖那一頁（下一步 → 再猜一次 → 下一步 → 給它提示圖，前置不錄），
/// 錄「三張提示圖都在 → 點『書包』→ 結局」。`story-ending` 走的是「床」。
final class FlowStoryHintBag: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 6)
        let next = Flow.element(app, "unit.next")
        let guessAgain = Flow.element(app, "story.choice.guess_again")
        let giveHint = Flow.element(app, "story.choice.give_hint")
        let bed = Flow.element(app, "story.choice.hint_bed")
        let bag = Flow.element(app, "story.choice.hint_bag")
        let bath = Flow.element(app, "story.choice.hint_bath")
        let ending = labeled(app, containing: "襪子找到了")
        prepareTap(next, until: "往第一個分歧") { !next.exists }
        prepareUntil("出現第一個分歧") { Flow.hittable(guessAgain) }
        prepareTap(guessAgain, until: "選了再猜一次") { !guessAgain.exists }
        prepareUntil("念完、出現下一步") { Flow.hittable(next) }
        prepareTap(next, until: "往第二個分歧") { !next.exists }
        prepareUntil("出現第二個分歧") { Flow.hittable(giveHint) }
        prepareTap(giveHint, until: "往提示圖") { !giveHint.exists }
        prepareUntil("三張提示圖都出現") { Flow.hittable(bed) && Flow.hittable(bag) && Flow.hittable(bath) }
        Frames.begin()
        Frames.tap(bag, until: "選了書包、選項消失") { !bag.exists && !bed.exists && !bath.exists }
        Frames.until("走到結局、念完出現下一步") { ending.exists && Flow.hittable(next) }
        Frames.end()
    }
}

/// 單元 1 故事：另一條路（下一步 → 自己找 → 下一步 → 給它提示圖，前置不錄），
/// 錄「三張提示圖都在 → 點『浴室』→ 結局」。
final class FlowStoryHintBath: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch(unit: 0, beat: 6)
        let next = Flow.element(app, "unit.next")
        let findMyself = Flow.element(app, "story.choice.find_myself")
        let giveHint = Flow.element(app, "story.choice.give_hint")
        let bed = Flow.element(app, "story.choice.hint_bed")
        let bag = Flow.element(app, "story.choice.hint_bag")
        let bath = Flow.element(app, "story.choice.hint_bath")
        let ending = labeled(app, containing: "襪子找到了")
        prepareTap(next, until: "往第一個分歧") { !next.exists }
        prepareUntil("出現第一個分歧") { Flow.hittable(findMyself) }
        prepareTap(findMyself, until: "選了自己找") { !findMyself.exists }
        prepareUntil("念完、出現下一步") { Flow.hittable(next) }
        prepareTap(next, until: "往第二個分歧") { !next.exists }
        prepareUntil("出現第二個分歧") { Flow.hittable(giveHint) }
        prepareTap(giveHint, until: "往提示圖") { !giveHint.exists }
        prepareUntil("三張提示圖都出現") { Flow.hittable(bed) && Flow.hittable(bag) && Flow.hittable(bath) }
        Frames.begin()
        Frames.tap(bath, until: "選了浴室、選項消失") { !bath.exists && !bed.exists && !bag.exists }
        Frames.until("走到結局、念完出現下一步") { ending.exists && Flow.hittable(next) }
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
