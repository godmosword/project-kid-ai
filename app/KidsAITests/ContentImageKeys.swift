import Foundation
@testable import KidsAI

/// 內容 JSON 裡所有 `image` 引用，走過：beat（選項、題板、拖曳卡、回顧選項、貼紙）、
/// 故事節點的選項、沙盒的 slot 與 slot 選項，以及猜測庫的猜測圖。
///
/// 暫代圖與 Asset Catalog 兩邊的測試都用這一份，兩邊才不會各走一次而漏掉同一個欄位。
enum ContentImageKeys {
    static func all(in contents: [UnitContent]) -> Set<String> {
        var keys: Set<String> = []
        for content in contents {
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
        return keys
    }

    /// repo 裡 4 個單元與猜測庫用到的 key（和 App 打包的是同一份內容）。
    static func all() throws -> Set<String> { all(in: try RepoContent.all()) }
}
