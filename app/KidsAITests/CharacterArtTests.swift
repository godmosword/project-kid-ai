import CoreGraphics
import Testing
import UIKit
@testable import KidsAI

@Suite("角色圖（P2）")
struct CharacterArtTests {
    @Test("兩張角色圖在 App bundle 解得出來，也列在 runtime 清單")
    func characterImagesShipInTheApp() {
        for key in [CharacterArt.dianDian, CharacterArt.guessHat] {
            #expect(ArtResources.runtime.contains(key), "\(key) 要受 bundle 解碼檢查")
            #expect(ArtResources.image(named: key) != nil, "\(key) 在 App bundle 解不出來")
        }
    }

    @Test("直的圖放進正方形框：高貼滿、左右置中")
    func fittedRectCentersPortraitImage() {
        let rect = CharacterArt.fittedRect(imageSize: CGSize(width: 478, height: 600), box: 120)
        #expect(abs(rect.height - 120) < 0.001)
        #expect(abs(rect.width - 95.6) < 0.001)
        #expect(abs(rect.minX - (120 - 95.6) / 2) < 0.001)
        #expect(rect.minY == 0)
    }

    @Test("小牌子的位置跟著圖實際畫出的區域走，而且在圖裡面", arguments: [52.0, 96.0, 120.0, 140.0])
    func badgeFollowsFittedImage(box: Double) throws {
        let imageSize = CGSize(width: 578, height: 600)
        let fitted = CharacterArt.fittedRect(imageSize: imageSize, box: box)
        let badge = try #require(CharacterArt.badgeRect(imageSize: imageSize, box: box))
        #expect(fitted.contains(badge), "小牌子要在圖裡：\(badge) ⊄ \(fitted)")
        #expect(abs(badge.midX - (fitted.minX + fitted.width * CharacterArt.badgeCenter.x)) < 0.001)
        #expect(abs(badge.midY - (fitted.minY + fitted.height * CharacterArt.badgeCenter.y)) < 0.001)
        #expect(abs(badge.width - fitted.width * CharacterArt.badgeSize.width) < 0.001)
    }

    @Test("框小於 40pt 不疊 AI 字（28pt 的小帽子）")
    func noBadgeTextOnTinyHat() {
        let imageSize = CGSize(width: 578, height: 600)
        #expect(CharacterArt.badgeRect(imageSize: imageSize, box: 28) == nil)
        #expect(CharacterArt.badgeRect(imageSize: imageSize, box: 39.9) == nil)
        #expect(CharacterArt.badgeRect(imageSize: imageSize, box: 40) != nil)
    }

    @Test("AI 字怎麼疊：28pt 不疊、52／44pt 白底膠囊至少 9pt、120／140pt 直接寫在牌面", arguments: [
        (28.0, CharacterArt.BadgeStyle.none), (44.0, .capsule), (52.0, .capsule), (99.0, .capsule), (120.0, .onBadge), (140.0, .onBadge),
    ])
    func badgeStyleBySize(box: Double, expected: CharacterArt.BadgeStyle) throws {
        #expect(CharacterArt.badgeStyle(box: box) == expected)
        guard expected != .none else { return }
        let badge = try #require(CharacterArt.badgeRect(imageSize: CGSize(width: 578, height: 600), box: box))
        let font = CharacterArt.badgeFontSize(badge: badge, style: expected)
        if expected == .capsule { #expect(font >= CharacterArt.capsuleMinFont, "\(box)pt 的字太小：\(font)") }
        else { #expect(font >= 8, "\(box)pt 牌面上的字太小：\(font)") }
    }

    @Test("圖的尺寸是 0 時不會除以 0，退回整個框")
    func degenerateImageSize() {
        #expect(CharacterArt.fittedRect(imageSize: .zero, box: 52) == CGRect(x: 0, y: 0, width: 52, height: 52))
    }

    @Test("讀不到的角色圖回傳 nil，畫面交給自繪暫代圖")
    func missingCharacterImageFallsBack() {
        let testBundle = Bundle(for: CharacterArtBundleMarker.self)
        #expect(ArtResources.image(named: CharacterArt.dianDian, in: testBundle) == nil)
        #expect(ArtResources.image(named: CharacterArt.guessHat, in: testBundle) == nil)
    }
}

private final class CharacterArtBundleMarker {}
