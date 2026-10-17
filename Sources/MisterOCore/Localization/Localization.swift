import Foundation

/// Panelin, raporların, hata kayıtlarının ve asistanın dili.
///
/// `MisterO.install` (ya da `.misterOTestPanel`) verilmezse cihazın dilini seçer; kurulum olmadan
/// (örn. birim testlerinde) dil İngilizcedir. Yeni bir dil `Resources/<kod>.lproj/Localizable.strings`
/// ve buradaki bir `case` ile eklenir.
public enum MisterOLanguage: String, CaseIterable, Sendable {
    case english = "en"
    case turkish = "tr"

    /// Cihazın tercih ettiği dillerden Mister-O'nun desteklediği ilki; hiçbiri değilse İngilizce.
    public static var device: MisterOLanguage {
        for identifier in Locale.preferredLanguages {
            let code = Locale(identifier: identifier).language.languageCode?.identifier
            if let language = allCases.first(where: { $0.rawValue == code }) { return language }
        }
        return .english
    }

    /// Şu an kullanılan dil.
    public static var current: MisterOLanguage {
        get { LanguageSetting.shared.value }
        set { LanguageSetting.shared.value = newValue }
    }

    /// Sayı, tarih ve büyük harf için ("ilerlemeli" → "İlerlemeli").
    public var locale: Locale {
        switch self {
        case .english: Locale(identifier: "en_US")
        case .turkish: Locale(identifier: "tr_TR")
        }
    }

    /// Modele "… in Turkish" diye söylenen ad.
    var promptName: String {
        switch self {
        case .english: "English"
        case .turkish: "Turkish"
        }
    }
}

private final class LanguageSetting: @unchecked Sendable {
    static let shared = LanguageSetting()

    private let lock = NSLock()
    private var stored = MisterOLanguage.english

    var value: MisterOLanguage {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

enum Localization {
    /// Dillerin `Localizable.strings` tabloları; İngilizce anahtarların kendisidir.
    private static let tables: [MisterOLanguage: [String: String]] = Dictionary(uniqueKeysWithValues:
        MisterOLanguage.allCases.map { ($0, loadTable($0)) })

    static func table(_ language: MisterOLanguage) -> [String: String] {
        tables[language] ?? [:]
    }

    static func string(_ key: String, language: MisterOLanguage, arguments: [any CVarArg]) -> String {
        let format = table(language)[key] ?? key
        return arguments.isEmpty ? format : String(format: format, locale: language.locale, arguments: arguments)
    }

    private static func loadTable(_ language: MisterOLanguage) -> [String: String] {
        guard let url = Bundle.module.url(forResource: "Localizable", withExtension: "strings", subdirectory: nil,
                                          localization: language.rawValue),
              let data = try? Data(contentsOf: url),
              let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String]
        else { return [:] }
        return table
    }
}

/// Arayüz metni. Anahtar metnin İngilizcesidir; seçili dilde karşılığı yoksa İngilizce kalır.
/// Biçim belirteçleri `String(format:)` gibidir: `L("Line %ld: %@", line, message)`.
package func L(_ key: String, _ arguments: any CVarArg...) -> String {
    Localization.string(key, language: MisterOLanguage.current, arguments: arguments)
}

/// Sayıya göre tekil/çoğul: `L(count, one: "%ld check", other: "%ld checks")`.
package func L(_ count: Int, one: String, other: String) -> String {
    L(count == 1 ? one : other, count)
}
