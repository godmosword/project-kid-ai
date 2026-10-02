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

    /// identifier 以某個字首開頭的第一個元素（例如故事分歧 `story.choice.`）。
    static func first(_ app: XCUIApplication, prefix: String) -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
    }

    /// 等元素出現而且可以點（前置階段用，不截圖）。
    static func waitHittable(_ element: XCUIElement, timeout: TimeInterval = timeout,
                             file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: timeout), .completed, "等不到可以點：\(element)",
                       file: file, line: line)
    }

    static func hittable(_ element: XCUIElement) -> Bool { element.exists && element.isHittable }
}

/// 和 control-kidsai 的約定（只在 `record --flow` 時有；`drive --flow` 沒設定就全部跳過）：
/// 路徑由 `TEST_RUNNER_KIDSAI_HANDSHAKE` 傳入；測試把截圖（frame-NNN.png）、點擊位置（taps.json）寫進去，
/// 結束時寫 done（所有斷言都通過）或 failed。CLI 以這個旗標判斷通過：Xcode 27 的 xcodebuild 偶爾會卡在收尾，不能只看它的結束碼。
/// UI 測試執行期間不能錄影（會讓 xcodebuild 卡住），所以用截圖接成縮時影片。
enum Handshake {
    static var directory: URL? {
        ProcessInfo.processInfo.environment["KIDSAI_HANDSHAKE"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func finish(passed: Bool) {
        guard let directory else { return }
        let name = passed ? "done" : "failed"
        let temporary = directory.appendingPathComponent(".\(name).tmp")
        try? Data(name.utf8).write(to: temporary)
        try? FileManager.default.moveItem(at: temporary, to: directory.appendingPathComponent(name))
    }
}

/// 測試裡的截圖：影片的每一格。點擊前兩格會記下被點元素的位置，CLI 在那兩格畫框標出「點了這裡」。
@MainActor
enum Frames {
    /// 最多 80 格（4 fps＝20 秒）；最後 4 格保留給最終狀態。
    static let limit = 80
    private static var index = 0
    private static var taps: [[String: Int]] = []

    /// `drive --flow` 只要通過與否，不截圖（`TEST_RUNNER_KIDSAI_FRAMES=0`）。
    static var enabled: Bool { ProcessInfo.processInfo.environment["KIDSAI_FRAMES"] != "0" }

    @discardableResult
    static func snap(final: Bool = false) -> Int? {
        guard enabled, let directory = Handshake.directory, index < (final ? limit : limit - 4) else { return nil }
        index += 1
        let data = XCUIScreen.main.screenshot().pngRepresentation
        try? data.write(to: directory.appendingPathComponent(String(format: "frame-%03d.png", index)))
        return index
    }

    /// 前置狀態：先截兩格當開頭。
    static func begin() {
        snap()
        snap()
    }

    /// 真實點擊：點之前截兩格並記下位置（像素），再點。`at` 是元素裡的相對位置（0–1），沒給就點中心。
    static func tap(_ element: XCUIElement, at offset: CGVector? = nil, file: StaticString = #filePath, line: UInt = #line) {
        mark(element, file: file, line: line)
        if let offset {
            element.coordinate(withNormalizedOffset: offset).tap()
        } else {
            element.tap()
        }
    }

    /// 真實長按（例如長按 X 離開）：和點擊一樣先標出位置。
    static func press(_ element: XCUIElement, forDuration duration: TimeInterval,
                      file: StaticString = #filePath, line: UInt = #line) {
        mark(element, file: file, line: line)
        element.press(forDuration: duration)
    }

    /// 等元素可點，截兩格並記下它的位置（像素），CLI 在這兩格畫框。
    private static func mark(_ element: XCUIElement, file: StaticString, line: UInt) {
        Flow.waitHittable(element, file: file, line: line)
        let scale = XCUIScreen.main.screenshot().image.scale
        let frame = element.frame
        for _ in 0..<2 {
            guard let at = snap() else { break }
            taps.append(["frame": at, "x": Int(frame.minX * scale), "y": Int(frame.minY * scale),
                         "w": Int(frame.width * scale), "h": Int(frame.height * scale)])
        }
        saveTaps()
    }

    /// 點到有效果為止：畫面上看得到按鈕、但 App 還在念上一段（上鎖）時，點擊會被忽略（設計如此：外觀不變、只擋點擊）。
    /// 點完等最多 3 秒看效果；沒有就像孩子一樣再點一次，最多 8 次。
    static func tap(_ element: XCUIElement, at offset: CGVector? = nil, until what: String,
                    file: StaticString = #filePath, line: UInt = #line, _ effect: () -> Bool) {
        for _ in 0..<8 {
            tap(element, at: offset, file: file, line: line)
            let deadline = Date().addingTimeInterval(3)
            repeat {
                snap()
                if effect() { return }
                Thread.sleep(forTimeInterval: 0.3)
            } while Date() < deadline
        }
        XCTFail("點了沒有效果：\(what)", file: file, line: line)
    }

    /// 一邊截圖一邊等條件成立（約每 0.5 秒一格）；逾時算失敗。
    static func until(_ what: String, timeout: TimeInterval = Flow.timeout, file: StaticString = #filePath, line: UInt = #line,
                      _ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            snap()
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.3)
        } while Date() < deadline
        XCTFail("等不到：\(what)", file: file, line: line)
    }

    /// 最終狀態：再截 4 格。
    static func end() {
        for _ in 0..<4 { snap(final: true) }
    }

    private static func saveTaps() {
        guard let directory = Handshake.directory,
              let data = try? JSONSerialization.data(withJSONObject: taps) else { return }
        try? data.write(to: directory.appendingPathComponent("taps.json"))
    }
}

/// 每支流程一個類別、一個 `testFlow`，給 `-only-testing:KidsAIUITests/<類別>` 用。
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
