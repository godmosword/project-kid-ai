import Testing
@testable import KidsAI

@Suite("暫代圖")
struct PlaceholderArtTests {
    /// 內容用到的每個圖片 key 都要有暫代圖，找不到的會變成中性色塊，所以要在測試擋下。
    @Test("4 個單元用到的圖片 key 都有暫代圖")
    func everyImageKeyHasPlaceholder() throws {
        var keys: Set<String> = []
        for content in try RepoContent.all() {
            for beat in content.unit.beats {
                switch beat.kind {
                case .choice(let c):
                    keys.formUnion(c.options.compactMap(\.image))
                    if let stage = c.stage { keys.insert(stage.image) }
                case .drag(let d): keys.formUnion(d.items.compactMap(\.image))
                case .review(let qs): keys.formUnion(qs.flatMap { $0.options.compactMap(\.image) })
                case .sticker(let s, _): keys.insert(s.image)
                default: break
                }
            }
            for story in content.unit.stories {
                for node in story.nodes {
                    if case .choices(let choices) = node.exit { keys.formUnion(choices.compactMap(\.image)) }
                }
            }
            for sandbox in content.unit.sandboxes {
                keys.formUnion(sandbox.slots.compactMap(\.image))
                keys.formUnion(sandbox.slots.flatMap { $0.choices.compactMap(\.image) })
            }
            keys.formUnion(content.banks.values.flatMap { $0.guesses.compactMap(\.image) })
        }
        let missing = keys.filter { !PlaceholderArt.has($0) }.sorted()
        #expect(missing.isEmpty, "缺少暫代圖：\(missing)")
    }

    @Test("沙盒卡的暫代圖不能直接畫出猜測（單元 1）")
    func sandboxCardsDoNotGiveAwayGuesses() {
        #expect(PlaceholderArt.table["img_slot_weather"] != .emoji("☀️"))
        #expect(PlaceholderArt.table["img_slot_animal"] == .blurredSilhouette("hare.fill"), "動物卡看不出是哪一種")
        #expect(PlaceholderArt.table["img_slot_breakfast"] == .corner("🍽️"), "早餐卡只露一角")
        #expect(PlaceholderArt.table["img_card_ai"] == .guessHat, "AI 卡和猜猜帽一致")
    }
}
