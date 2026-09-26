import XCTest

/// 地圖 → 點認識島 → 進入單元 1。
final class FlowMapToUnit1: FlowTestCase {
    @MainActor
    func testFlow() {
        let app = Flow.launch()
        let island = Flow.element(app, "map.island.0")
        Flow.waitHittable(island)
        Handshake.ready()
        Frames.snap()
        island.tap()
        let exit = Flow.element(app, "unit.exit")
        XCTAssertTrue(Frames.record(until: { exit.exists && exit.isHittable && !island.exists }))
        for _ in 0..<4 { Frames.snap() }
    }
}
