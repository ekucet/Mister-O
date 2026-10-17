import Foundation
import Testing
@testable import MisterOCore

/// Kaynaklardaki `L("…")` anahtarları ve dil tabloları.
struct LocalizationTests {
    private static let sources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources")

    /// Simülatörde kaynak klasörü okunamazsa tarama testleri atlanır; macOS'ta `swift test` koşar.
    private static var hasSources: Bool { FileManager.default.fileExists(atPath: sources.path) }

    @Test(.enabled(if: hasSources)) func everyKeyIsTranslated() throws {
        let keys = try Self.keysInSources()
        #expect(keys.count > 100)
        for language in MisterOLanguage.allCases where language != .english {
            let table = Localization.table(language)
            let missing = keys.subtracting(table.keys).sorted()
            let unused = Set(table.keys).subtracting(keys).sorted()
            #expect(missing.isEmpty, "\(language.rawValue) çevirisi eksik: \(missing)")
            #expect(unused.isEmpty, "\(language.rawValue) tablosunda kullanılmayan anahtar: \(unused)")
        }
    }

    @Test func translationsKeepTheFormatSpecifiers() {
        for language in MisterOLanguage.allCases {
            for (key, value) in Localization.table(language) {
                #expect(Self.specifiers(in: value) == Self.specifiers(in: key), "\(language.rawValue): \(key) → \(value)")
            }
        }
    }

    @Test func looksUpTheChosenLanguage() {
        #expect(Localization.string("Stop", language: .turkish, arguments: []) == "Durdur")
        #expect(Localization.string("Stop", language: .english, arguments: []) == "Stop")
        // Konumlu belirteçler sırayı korur; Türkçede ondalık ayırıcı virgül.
        #expect(Localization.string("Testing · %ld/%ld", language: .turkish, arguments: [2, 3]) == "Test ediliyor · 2/3")
        #expect(Localization.string("%.2f s", language: .turkish, arguments: [1.25]) == "1,25 sn")
        #expect(Localization.string("%.2f s", language: .english, arguments: [1.25]) == "1.25 s")
        // Tabloda olmayan anahtar İngilizce kalır.
        #expect(Localization.string("Not translated %@", language: .turkish, arguments: ["x"]) == "Not translated x")
    }

    @Test func picksSingularOrPlural() {
        #expect(L(1, one: "%ld check", other: "%ld checks") == "1 check")
        #expect(L(3, one: "%ld check", other: "%ld checks") == "3 checks")
    }

    @Test func capitalizesTheExpectationInTheTestersLanguage() {
        #expect(HeuristicPlanner.check(for: "fill the fields, tap Save; it should open the next screen").expectation
                == "It should open the next screen.")
        #expect(HeuristicPlanner.check(for: "alanları doldur, Kaydet'e bas; ilerlemeli").expectation == "İlerlemeli.")
    }

    // MARK: - Yardımcılar

    /// `%ld`, `%@`, `%.2f`… sırasıyla; `%2$@` gibi konumlu olanlar konumlarına göre.
    static func specifiers(in format: String) -> [String] {
        let regex = /%(?:(\d+)\$)?(\.\d+)?(l{0,2}[dufx@])/
        var positional: [(Int, String)] = []
        var plain: [String] = []
        for match in format.matches(of: regex) {
            let type = String((match.2 ?? "") + match.3)
            if let position = match.1.flatMap({ Int($0) }) {
                positional.append((position, type))
            } else {
                plain.append(type)
            }
        }
        return plain + positional.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// `L(` çağrılarının içindeki string literal'leri (yorum satırları hariç).
    static func keysInSources() throws -> Set<String> {
        var keys = Set<String>()
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" } ?? []
        for file in files {
            let code = try String(contentsOf: file, encoding: .utf8)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            keys.formUnion(literalsInCalls(code))
        }
        return keys
    }

    private static func literalsInCalls(_ code: String) -> [String] {
        let characters = Array(code)
        var keys: [String] = []
        var index = 0
        while index < characters.count - 1 {
            let isCall = characters[index] == "L" && characters[index + 1] == "("
                && (index == 0 || !(characters[index - 1].isLetter || characters[index - 1].isNumber
                                    || characters[index - 1] == "_"))
            guard isCall else { index += 1; continue }
            var depth = 1
            var position = index + 2
            while position < characters.count, depth > 0 {
                switch characters[position] {
                case "(": depth += 1
                case ")": depth -= 1
                case "\"":
                    // Interpolation'lı literal anahtar değil argümandır: L("Not on screen: %@", "\(selector)").
                    var literal = ""
                    var isInterpolated = false
                    position += 1
                    while position < characters.count, characters[position] != "\"" {
                        if characters[position] == "\\", position + 1 < characters.count {
                            position += 1
                            switch characters[position] {
                            case "n": literal.append("\n")
                            case "t": literal.append("\t")
                            case "(":
                                isInterpolated = true
                                var nested = 1
                                while nested > 0, position + 1 < characters.count {
                                    position += 1
                                    if characters[position] == "(" { nested += 1 }
                                    if characters[position] == ")" { nested -= 1 }
                                }
                            default: literal.append(characters[position])
                            }
                        } else {
                            literal.append(characters[position])
                        }
                        position += 1
                    }
                    if !isInterpolated { keys.append(literal) }
                default: break
                }
                position += 1
            }
            index = position
        }
        return keys
    }
}
