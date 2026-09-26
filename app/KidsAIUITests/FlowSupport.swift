import XCTest

/// 流程測試的共用工具：只用啟動參數準備前置狀態，要證明的動作一定是真的點擊。
/// 一律等「元素可點」，不用固定秒數；旁白時間不固定，上限 30 秒（沒有中文語音時會立刻出現）。
@MainActor
enum Flow {
    static let timeout: TimeInterval = 30

    /// 啟動 App；`unit`／`beat` 對應 Debug 的 `-openUnit`／`-beat`（0 起算）。
    static func launch(unit: Int? = nil, beat: Int? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments: [String] = []
        if let unit { arguments += ["-openUnit", "\(unit)"] }
        if let beat { arguments += ["-beat", "\(beat)"] }
        app.launchArguments = arguments
        app.launch()
        return app
    }

    /// 依 identifier 找元素，不假設元素型別。
    static func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    /// 等元素出現而且可以點。
    static func waitHittable(_ element: XCUIElement, timeout: TimeInterval = timeout,
                             file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, "等不到可以點：\(element)", file: file, line: line)
    }

    /// 等元素消失。
    static func waitGone(_ element: XCUIElement, timeout: TimeInterval = timeout,
                         file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "一直沒有消失：\(element)", file: file, line: line)
    }

    /// 等到可以點再點（真實點擊）。
    static func tap(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        waitHittable(element, file: file, line: line)
        element.tap()
    }
}

/// 和 control-kidsai 的錄影握手（只在 `record --flow` 時啟用；`drive --flow` 沒有設定就跳過）。
/// 路徑由 `TEST_RUNNER_KIDSAI_HANDSHAKE` 傳入；順序：ready → 等 go → 點擊 → done／failed → 等 end。
/// 等 end：CLI 停好錄影才讓測試結束（錄影還在跑時結束測試，xcodebuild 會卡在收尾）。
/// 只讀寫檔案，不碰 UI，所以不綁 main actor（tearDown 也能呼叫）。
enum Handshake {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["KIDSAI_HANDSHAKE"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// 前置狀態就緒：通知 CLI 開始錄影，等 CLI 回 go（最多 30 秒）。
    static func ready(file: StaticString = #filePath, line: UInt = #line) {
        guard directory != nil else { return }
        signal("ready")
        if !wait(for: "go", seconds: 30) {
            XCTFail("等不到錄影開始（go）", file: file, line: line)
        }
    }

    /// 結束訊號：寫 done 或 failed，再等 CLI 停好錄影（end，最多 30 秒）。
    static func finish(passed: Bool) {
        guard directory != nil else { return }
        signal(passed ? "done" : "failed")
        _ = wait(for: "end", seconds: 30)
    }

    private static func wait(for name: String, seconds: TimeInterval) -> Bool {
        guard let directory else { return true }
        let path = directory.appendingPathComponent(name).path
        let deadline = Date().addingTimeInterval(seconds)
        while !FileManager.default.fileExists(atPath: path) {
            if Date() > deadline { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return true
    }

    /// 原子寫入：先寫暫存檔再改名，CLI 不會讀到寫一半的檔。
    private static func signal(_ name: String) {
        guard let directory else { return }
        let temporary = directory.appendingPathComponent(".\(name).tmp")
        try? Data(name.utf8).write(to: temporary)
        try? FileManager.default.moveItem(at: temporary, to: directory.appendingPathComponent(name))
    }
}

/// 每支流程一個類別、一個 `testFlow`，給 `-only-testing:KidsAIUITests/<類別>` 用。
/// 失敗（任何斷言失敗）時寫 failed，讓 CLI 丟棄這段錄影。
class FlowTestCase: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        let failures = (testRun?.failureCount ?? 0) + (testRun?.unexpectedExceptionCount ?? 0)
        Handshake.finish(passed: failures == 0)
        super.tearDown()
    }
}

/// 原型：測試裡每 0.25 秒截一張圖（只在有握手資料夾時），給 CLI 接成影片。
@MainActor
enum Frames {
    private static var index = 0

    static func snap() {
        guard let directory = Handshake.directory else { return }
        index += 1
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: directory.appendingPathComponent(String(format: "frame-%03d.png", index)))
    }

    /// 一邊截圖一邊等條件成立（取代固定等待）。
    static func record(until condition: () -> Bool, timeout: TimeInterval = 30) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            snap()
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.2)
        } while Date() < deadline
        return false
    }
}
