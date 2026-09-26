import Foundation

/// 用字串當 key 的解碼器：先檢查欄位都在允許清單內，再逐一取值。
/// 內容格式是封閉的（見 content/schema），App 端遇到未定義的欄位一律失敗，不靜默忽略。
struct AnyKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

typealias StrictContainer = KeyedDecodingContainer<AnyKey>

extension Decoder {
    /// 取得物件容器，並確認只出現 `allowed` 裡的欄位。
    func strict(_ allowed: Set<String>) throws -> StrictContainer {
        let container = try container(keyedBy: AnyKey.self)
        let extra = container.allKeys.map(\.stringValue).filter { !allowed.contains($0) }
        guard extra.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "未定義的欄位：\(extra.sorted().joined(separator: "、"))"))
        }
        return container
    }
}

extension KeyedDecodingContainer where K == AnyKey {
    func required<T: Decodable>(_ key: String) throws -> T {
        try decode(T.self, forKey: AnyKey(key))
    }

    func optional<T: Decodable>(_ key: String) throws -> T? {
        try decodeIfPresent(T.self, forKey: AnyKey(key))
    }

    /// 某些 case 不允許出現的欄位。
    func forbid(_ keys: [String]) throws {
        let present = keys.filter { contains(AnyKey($0)) }
        guard present.isEmpty else {
            throw DecodingError.dataCorrupted(.init(codingPath: codingPath, debugDescription: "此情況不得出現：\(present.joined(separator: "、"))"))
        }
    }

    func fail(_ message: String) -> DecodingError {
        .dataCorrupted(.init(codingPath: codingPath, debugDescription: message))
    }
}
