import Foundation
import Testing
import UIKit
@testable import KidsAI

/// 只用來取得「測試 bundle」（Swift Testing 沒有 test case class 可以當錨點）。
private final class TestBundleMarker {}

private enum ArtTestBundle {
    /// 不存成 static let：Swift 6 的全域狀態檢查只接受 Sendable，改成每次算一次。
    static var bundle: Bundle { Bundle(for: TestBundleMarker.self) }

    /// 只放在測試 target 的工程用素材（`app/KidsAITests/TestAssets.xcassets`）。
    /// 它不是美術素材、不得進 App；用途是證明檢查真的在解圖，而不是因為清單是空的才通過。
    static let fixtureKey = "test_fixture_checker_8x8"
    static let fixturePixels = CGSize(width: 8, height: 8)
}

@Suite("正式美術資源清單")
struct ArtRegistryTests {
    @Test("已遷移＋待製作剛好等於 4 個單元與猜測庫用到的 key")
    func registryMatchesContent() throws {
        let content = try ContentImageKeys.all()
        let audit = ArtRegistryAudit(contentKeys: content)
        #expect(content.count == 35, "內容的 key 數量變了（原本 35）：\(content.count)")
        #expect(audit.missingFromRegistry.isEmpty, "內容用到、清單沒列：\(audit.missingFromRegistry)")
        #expect(audit.notInContent.isEmpty, "清單列了、內容沒用到（過期或拼錯）：\(audit.notInContent)")
    }

    @Test("已遷移與待製作不重疊，加起來不少不多")
    func migratedAndPendingDoNotOverlap() {
        let migrated = ArtResources.Content.migrated
        let pending = ArtResources.Content.pending
        #expect(migrated.isDisjoint(with: pending), "同一個 key 不能同時算已遷移和待製作：\(migrated.intersection(pending).sorted())")
        #expect(ArtResources.Content.all.count == migrated.count + pending.count)
    }

    @Test("每個單元的 key 數量和計畫的分批一致（14／8／6／7）", arguments: [
        ("unit_1_recognize", 14), ("unit_2_prompt", 8), ("unit_3_verify", 6), ("unit_4_create", 7),
    ])
    func perUnitKeyCount(id: String, expected: Int) throws {
        let content = try RepoContent.unit(id)
        let keys = ContentImageKeys.all(in: [content])
        #expect(keys.count == expected, "\(id) 的 key：\(keys.sorted())")
    }

    /// 清單漏列或把名字拼錯時，對照一定要指名；用真實內容 key 去跑對照本身，而不是重寫一次清單。
    @Test("漏列與拼錯的 key 會被對照抓出來")
    func registryAuditCatchesMissingAndTypo() throws {
        let content = try ContentImageKeys.all()
        let typo = "img_card_ia"
        let broken = content.subtracting(["img_card_ai"]).union([typo])
        let audit = ArtRegistryAudit(contentKeys: content, registryKeys: broken)
        #expect(!audit.isClean)
        #expect(audit.missingFromRegistry == ["img_card_ai"])
        #expect(audit.notInContent == [typo])
    }

    /// AI 卡的 AI 牌文字與無障礙語意是 App 畫的，所以它永遠交給共用角色渲染（`GuessHat`）。
    /// 這條擋的是 P2 把角色圖放進 `migrated` 之後，畫面變成一張沒有 AI 牌文字的原圖。
    @Test("AI 卡保留給共用角色渲染：列入已遷移也不走通用讀圖")
    func roleRenderedKeysNeverUseGenericImage() throws {
        let roleKeys = ArtResources.roleRenderedContentKeys
        #expect(!roleKeys.isEmpty)
        #expect(roleKeys.isSubset(of: ArtResources.Content.all), "角色渲染的 key 必須是內容真的用到的 key")
        for key in roleKeys {
            #expect(ArtResources.isRoleRendered(key))
            #expect(!ArtResources.usesGenericImage(key, migrated: ArtResources.Content.all), "\(key) 不該走通用讀圖")
            #expect(PlaceholderArt.has(key), "\(key) 仍要有角色暫代圖當退路")
        }
        // 對照組：一般內容 key 遷移後就走通用讀圖，沒遷移就不走
        let plain = try #require(ArtResources.Content.all.subtracting(roleKeys).sorted().first)
        #expect(ArtResources.usesGenericImage(plain, migrated: ArtResources.Content.all))
        #expect(!ArtResources.usesGenericImage(plain, migrated: []))
    }
}

/// 編譯後的 bundle 檢查。`@MainActor` 只是把 UIKit 的具名載入固定在主執行緒，iOS 17 可用。
@Suite("編譯後的素材可以解碼")
@MainActor
struct AssetCatalogTests {
    @Test("清單上該有的 key 在實際 App bundle 都解得出來")
    func defaultRegistryDecodesInAppBundle() {
        // 預設的 bundle 是宿主 App（unit tests 以 KidsAI.app 為 host），不是測試 bundle
        #expect(Bundle.main.url(forResource: "units", withExtension: nil) != nil, "Bundle.main 應該是宿主 App（裡面有打包的 units/）")
        #expect(Bundle.main.bundleURL != ArtTestBundle.bundle.bundleURL)
        let audit = ArtCatalogAudit()
        // P1 的 migrated／runtime 還是空的，這條是 P2／P3／D3 放進資源後的回歸守門；
        // 證明「檢查真的在解圖」的是下面注入測試素材的兩條。
        #expect(audit.missingKeys.isEmpty, "App bundle 解不出來：\(audit.missingKeys)")
        #expect(audit.decodableKeys.count == ArtResources.Content.migrated.union(ArtResources.runtime).count)
    }

    @Test("標成待製作的 key 不得已經在 App 裡解得出來")
    func pendingKeysAreNotInAppBundle() {
        let unexpected = ArtResources.Content.pending
            .filter { ArtResources.image(named: $0, in: .main) != nil }
            .sorted()
        #expect(unexpected.isEmpty, "這些 key 標成待製作，卻在 App bundle 解得出來（清單和實際資源不一致）：\(unexpected)")
    }

    @Test("工程用測試素材只在測試 bundle 解得出來，不會被打包進 App")
    func fixtureDecodesFromTestBundleOnly() throws {
        let image = try #require(ArtResources.image(named: ArtTestBundle.fixtureKey, in: ArtTestBundle.bundle),
                                 "測試素材應該在測試 bundle 解得出來")
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        #expect(pixels == ArtTestBundle.fixturePixels)
        #expect(ArtResources.image(named: ArtTestBundle.fixtureKey, in: .main) == nil,
                "測試素材不得出現在 App bundle")
    }

    @Test("缺圖與拼錯的 key 會被點名，解得出來的不會")
    func catalogAuditNamesMissingKeys() {
        let audit = ArtCatalogAudit(bundle: ArtTestBundle.bundle,
                                    migratedContentKeys: [ArtTestBundle.fixtureKey, "img_fixture_typo"],
                                    runtimeKeys: ["char_missing_runtime_art"])
        #expect(audit.missingKeys == ["char_missing_runtime_art", "img_fixture_typo"])
        #expect(audit.decodableKeys == [ArtTestBundle.fixtureKey])
    }
}
