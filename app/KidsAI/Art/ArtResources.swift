import UIKit

/// 正式美術資源的中央清單與唯一載入點（Asset Catalog）。
///
/// 分批遷移（docs/art/next-stage-plan.md 的 D3／D5）：
/// - `Content.migrated`：已核准、已放進 `app/KidsAI/Assets.xcassets` 的內容 key；只有這些 key 會去讀正式圖。
/// - `Content.pending`：還沒定稿、畫面上仍是 `PlaceholderArt` 暫代圖的內容 key。
///
/// 兩份加起來必須剛好等於 `content/units/` 用到的 `image` key（`AssetCatalogTests.swift` 會比對），
/// 所以沒列進來的 key 和拼錯的名字都不會自動放行；已遷移但 bundle 裡解不出來的 key 會讓測試失敗。
///
/// 例外：`roleRenderedContentKeys`（AI 卡）由共用角色渲染畫，不經 `ArtView` 的通用讀圖。
///
/// 單元 1 的 13 個內容 key 已遷移（P4）；其他 22 個仍待製作。角色圖（P2，D1 核准的點點、猜猜帽正面）在 `runtime`。
enum ArtResources {
    /// 內容 JSON（`image` 欄位）用到的 key。
    enum Content {
        /// 已核准並遷移到 Asset Catalog 的 key。
        ///
        /// 遷移某個 key 時要一起檢查 `PlaceholderArt.widthScale`：正式圖若把「相對大小」畫在共用畫布裡
        /// （單元 2 的三張貓、單元 3 的兩顆蘋果），該 key 的倍率要改成 1，否則會再乘一次。
        static let migrated: Set<String> = [
            // 單元 1 認識島（13；img_card_ai 由 GuessHat 渲染，留在 pending）— D3，Michael 2026-10-03 核准
            "img_card_family", "img_card_toy",
            "img_box_peek_cat_ear",
            "img_box_reveal_cat", "img_box_reveal_car", "img_box_reveal_banana",
            "img_slot_weather", "img_slot_breakfast", "img_slot_animal",
            "img_hint_bed", "img_hint_bag", "img_hint_bath",
            "img_sticker_can_guess",
        ]

        /// 還沒定稿、暫時用暫代圖的 key。D5 收尾後這份要清空。
        static let pending: Set<String> = [
            // 單元 1 認識島：AI 卡由共用角色渲染（GuessHat），沒有獨立圖檔
            "img_card_ai",
            // 單元 2 提問島（8）
            "img_u2_bear", "img_u2_rabbit", "img_u2_cup_star", "img_u2_place_table",
            "img_u2_wish_cat", "img_u2_guess_cat_clear", "img_u2_guess_cat_vague",
            "img_sticker_say_clear",
            // 單元 3 檢查島（6）
            "img_u3_apple_plain", "img_u3_apple_glasses",
            "img_u3_card_dog", "img_u3_card_night", "img_u3_card_car",
            "img_sticker_detective",
            // 單元 4 創作島（7）
            "img_u4_car_go_out", "img_u4_rain", "img_u4_car_umbrella",
            "img_u4_world_cars", "img_u4_world_animals", "img_u4_world_picnic",
            "img_sticker_director",
        ]

        /// 內容用到的全部 key（已遷移＋待製作）。
        static let all: Set<String> = migrated.union(pending)
    }

    /// 不在內容 JSON 裡、執行期才會用到的圖：角色（P2）、地圖（P3）。
    /// 列進來的 key 和 `Content.migrated` 受同一套 bundle 解碼檢查。設定圖與表情 sheet 是製作參考，不放進這份清單。
    static let runtime: Set<String> = [CharacterArt.dianDian, CharacterArt.guessHat]

    /// 由共用角色渲染負責的內容 key，不走 `ArtView` 的通用讀圖路徑。
    ///
    /// `img_card_ai` 畫的是猜猜帽：帽上的「AI」牌文字與無障礙標籤（「猜猜帽，AI」）是 App 畫上去的（`GuessHat`），
    /// 正式圖只是角色來源。如果讓它走通用讀圖，P2 一放進角色圖，畫面就變成一張沒有 AI 牌文字的原圖。
    /// 所以這些 key 即使進了 `Content.migrated`（為了受 bundle 解碼檢查），畫面仍然交給角色渲染；
    /// P2 要改的是 `Characters.swift` 的共用角色渲染，不是這個分支。
    static let roleRenderedContentKeys: Set<String> = ["img_card_ai"]

    static func isRoleRendered(_ key: String) -> Bool { roleRenderedContentKeys.contains(key) }

    /// 這個內容 key 是否由 `ArtView` 直接讀正式圖：已遷移、而且不是角色渲染的 key。
    /// `migrated` 可注入，測試才能證明「就算 AI 卡被遷移，也不會走通用讀圖」。
    static func usesGenericImage(_ key: String, migrated: Set<String> = Content.migrated) -> Bool {
        migrated.contains(key) && !isRoleRendered(key)
    }

    /// 從 Asset Catalog 取圖；查不到就是 `nil`，由呼叫端決定退路（不顯示空白、也不顯示 key）。
    static func image(named key: String, in bundle: Bundle = .main) -> UIImage? {
        UIImage(named: key, in: bundle, compatibleWith: nil)
    }
}

/// 編譯後的 bundle 素材完整性檢查：清單上「應該存在」的 key 是不是真的解得出來。
/// bundle 與清單都可注入，測試才能驗缺圖會被點名（正式資源還沒有時，注入清單是唯一能證明檢查有效的方式）。
struct ArtCatalogAudit {
    let bundle: Bundle
    let migratedContentKeys: Set<String>
    let runtimeKeys: Set<String>

    init(bundle: Bundle = .main,
         migratedContentKeys: Set<String> = ArtResources.Content.migrated,
         runtimeKeys: Set<String> = ArtResources.runtime) {
        self.bundle = bundle
        self.migratedContentKeys = migratedContentKeys
        self.runtimeKeys = runtimeKeys
    }

    /// 清單上解不出來的 key，排序後回傳（失敗訊息要點得出缺哪一張）。
    var missingKeys: [String] {
        migratedContentKeys.union(runtimeKeys)
            .filter { ArtResources.image(named: $0, in: bundle) == nil }
            .sorted()
    }

    /// 清單上解得出來的 key（正面確認檢查真的在解圖，不是因為清單空的才通過）。
    var decodableKeys: [String] {
        migratedContentKeys.union(runtimeKeys)
            .filter { ArtResources.image(named: $0, in: bundle) != nil }
            .sorted()
    }
}

/// 清單與內容 JSON 的對照：`migrated` ＋ `pending` 要剛好等於內容用到的 `image` key。
/// 兩邊都可注入，測試才能同時驗「現在是乾淨的」和「漏列或拼錯真的會被抓出來」。
struct ArtRegistryAudit {
    /// 內容用到、清單沒列（新 key，或清單把名字拼錯）。
    let missingFromRegistry: [String]
    /// 清單列了、內容沒用到（過期的 key，或清單把名字拼錯）。
    let notInContent: [String]

    init(contentKeys: Set<String>, registryKeys: Set<String> = ArtResources.Content.all) {
        missingFromRegistry = contentKeys.subtracting(registryKeys).sorted()
        notInContent = registryKeys.subtracting(contentKeys).sorted()
    }

    var isClean: Bool { missingFromRegistry.isEmpty && notInContent.isEmpty }
}
