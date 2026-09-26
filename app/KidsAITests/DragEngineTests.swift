import Testing
@testable import KidsAI

@Suite("拖曳（配對、分組、排序）")
struct DragEngineTests {
    private func engine(_ unitID: String, at beatID: String) throws -> UnitEngine {
        let content = try RepoContent.unit(unitID)
        var e = UnitEngine(content: content)
        _ = e.jump(to: try #require(content.unit.beats.firstIndex { $0.id == beatID }))
        return e
    }

    private func state(_ e: UnitEngine) throws -> DragState {
        guard case .drag(let d) = e.phase else { throw DragTestError.notDrag }
        return d
    }

    private enum DragTestError: Error { case notDrag }
    private static let slot = UnitEngine.orderSlotPrefix

    @Test("題目念完，依序播有聲音的卡，再念各目標")
    func promptReadsSoundsThenTargets() throws {
        let e = try engine("unit_3_verify", at: "u3_gate2_sort")
        let highlights = e.dragPrompt().compactMap(\.highlight)
        #expect(highlights == ["fish", "square_moon", "hot_ice", "bright_sun", "keep", "fix"])
    }

    @Test("配對全對就成功；沒放完不能檢查也不能前進")
    func matchSuccess() throws {
        var e = try engine("unit_2_prompt", at: "u2_gate2_blanks")
        _ = e.send(.dragPlace(item: "cup_star", target: "blank_what"))
        #expect(e.send(.dragCheck).isEmpty)
        #expect(!e.canProceed)
        _ = e.send(.dragPlace(item: "place_table", target: "blank_where"))
        let lines = e.send(.dragCheck)
        #expect(lines.map(\.text) == ["說清楚了！杯子放桌上。"])
        #expect(try state(e).outcome == .success && e.canProceed)
    }

    @Test("放到已經有卡的格子會交換，原本那張回到新卡的來處")
    func swapReturnsOccupantToOrigin() throws {
        var e = try engine("unit_2_prompt", at: "u2_gate2_blanks")
        _ = e.send(.dragPlace(item: "cup_star", target: "blank_what"))
        _ = e.send(.dragPlace(item: "place_table", target: "blank_what"))
        #expect(try state(e).placements == ["place_table": "blank_what"], "杯子從卡片區來，就回卡片區")
        _ = e.send(.dragPlace(item: "cup_star", target: "blank_where"))
        _ = e.send(.dragPlace(item: "cup_star", target: "blank_what"))
        #expect(try state(e).placements == ["cup_star": "blank_what", "place_table": "blank_where"], "兩格互換")
    }

    @Test("點卡片＝選起來並播放；再點目標＝放上去；沒選卡點目標＝念標籤")
    func tapToPlace() throws {
        var e = try engine("unit_3_verify", at: "u3_gate2_sort")
        let label = e.send(.dragTapTarget("fix"))
        #expect(label.map(\.text) == ["要改正"])
        let sound = e.send(.dragSelect("square_moon"))
        #expect(sound.map(\.text) == ["月亮是方的。"])
        #expect(try state(e).selected == "square_moon")
        _ = e.send(.dragTapTarget("fix"))
        #expect(try state(e).placements == ["square_moon": "fix"])
        #expect(try state(e).selected == nil)
        _ = e.send(.dragSelect("square_moon"))
        #expect(try state(e).placements["square_moon"] == "fix", "點已放好的卡不會退回")
        _ = e.send(.dragReturn("square_moon"))
        #expect(try state(e).placements.isEmpty)
    }

    @Test("部分答錯：放對的固定、放錯的回卡片區，接著重播退回的卡")
    func partialWrongReturnsOnlyWrong() throws {
        var e = try engine("unit_3_verify", at: "u3_gate2_sort")
        for (item, group) in [("fish", "keep"), ("square_moon", "keep"), ("hot_ice", "fix"), ("bright_sun", "keep")] {
            _ = e.send(.dragPlace(item: item, target: group))
        }
        let lines = e.send(.dragCheck)
        #expect(lines.map(\.text) == ["再聽一次，說得通嗎？", "月亮是方的。"])
        let d = try state(e)
        #expect(d.attempts == 1 && d.outcome == nil)
        #expect(d.fixed == ["fish", "hot_ice", "bright_sun"])
        #expect(d.returned == ["square_moon"] && d.placements["square_moon"] == nil)
        #expect(e.send(.dragPlace(item: "fish", target: "fix")).isEmpty, "固定的卡不能移動")
    }

    @Test("達上限自動排好並揭曉，可以前進")
    func revealAfterMaxAttempts() throws {
        var e = try engine("unit_3_verify", at: "u3_gate2_sort")
        for _ in 0..<2 {
            let d = try state(e)
            for item in ["fish", "square_moon", "hot_ice", "bright_sun"] where d.placements[item] == nil {
                _ = e.send(.dragPlace(item: item, target: item == "fish" ? "keep" : "keep"))
            }
            _ = e.send(.dragCheck)
        }
        let d = try state(e)
        #expect(d.outcome == .revealed && e.canProceed)
        #expect(d.placements == ["fish": "keep", "square_moon": "fix", "hot_ice": "fix", "bright_sun": "keep"])
    }

    @Test("排序：另一個合法順序也算對")
    func alternativeOrderAccepted() throws {
        var e = try engine("unit_4_create", at: "u4_gate2_order")
        for (index, item) in ["rain", "umbrella", "go_out"].enumerated() {
            _ = e.send(.dragPlace(item: item, target: Self.slot + "\(index + 1)"))
        }
        _ = e.send(.dragCheck)
        #expect(try state(e).outcome == .success)
    }

    @Test("排序部分答錯平手時，以 correct_order 判斷哪張放對")
    func orderTieUsesCorrectOrder() throws {
        var e = try engine("unit_4_create", at: "u4_gate2_order")
        for (index, item) in ["rain", "go_out", "umbrella"].enumerated() {
            _ = e.send(.dragPlace(item: item, target: Self.slot + "\(index + 1)"))
        }
        _ = e.send(.dragCheck)
        let d = try state(e)
        #expect(d.fixed == ["umbrella"])
        #expect(d.returned == ["rain", "go_out"])
    }

    @Test("揭曉時排序一律用 correct_order")
    func revealUsesCorrectOrder() throws {
        var e = try engine("unit_4_create", at: "u4_gate2_order")
        for _ in 0..<2 {
            let d = try state(e)
            let loose = ["go_out", "rain", "umbrella"].filter { d.placements[$0] == nil }
            let free = (1...3).map { Self.slot + "\($0)" }.filter { slot in !d.placements.values.contains(slot) }
            // 反著放，一定錯
            for (item, slot) in zip(loose, free.reversed()) { _ = e.send(.dragPlace(item: item, target: slot)) }
            _ = e.send(.dragCheck)
        }
        #expect(try state(e).placements == ["go_out": Self.slot + "1", "rain": Self.slot + "2", "umbrella": Self.slot + "3"])
    }

    @Test("有選起的卡時不檢查；放下選取後才可以檢查")
    func selectionBlocksCheck() throws {
        var e = try engine("unit_2_prompt", at: "u2_gate2_blanks")
        _ = e.send(.dragPlace(item: "cup_star", target: "blank_what"))
        _ = e.send(.dragPlace(item: "place_table", target: "blank_where"))
        _ = e.send(.dragSelect("cup_star"))
        #expect(!e.dragReadyToCheck(try state(e)))
        #expect(e.send(.dragCheck).isEmpty)
        _ = e.send(.dragDeselect)
        #expect(e.dragReadyToCheck(try state(e)))
    }

    @Test("選起卡後點另一張放好的卡＝放到那裡（交換）")
    func tapPlacedCardWhileSelectedSwaps() throws {
        var e = try engine("unit_4_create", at: "u4_gate2_order")
        _ = e.send(.dragPlace(item: "go_out", target: Self.slot + "1"))
        _ = e.send(.dragSelect("rain"))
        let lines = e.send(.dragSelect("go_out"))
        #expect(lines.isEmpty, "不是改選、也不念另一張卡")
        #expect(try state(e).placements == ["rain": Self.slot + "1"], "出門玩回到下雨了的來處（卡片區）")
        #expect(try state(e).selected == nil)
    }

    @Test("重念不改變次數")
    func replayDoesNotCount() throws {
        var e = try engine("unit_2_prompt", at: "u2_gate2_blanks")
        _ = e.send(.dragPlace(item: "cup_star", target: "blank_where"))
        _ = e.send(.dragPlace(item: "place_table", target: "blank_what"))
        _ = e.send(.dragCheck)
        _ = e.replayLines()
        #expect(e.send(.dragCheck).isEmpty, "放錯的已退回，還沒放完不能再檢查")
        #expect(try state(e).attempts == 1)
    }
}
