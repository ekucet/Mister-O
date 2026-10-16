import Foundation

/// Testçinin yazdığı akış metnini `TestStep` listesine çevirir.
///
///     # yorum satırı
///     tap: "login_button"
///     type: "email_field" -> "test@example.com"
///     wait: 1.5
///     assertVisible: "welcome_label"
///
/// - Boş satırlar ve `#` ile başlayan satırlar atlanır; satır sonu yorumu (` # ...`) desteklenir.
/// - YAML listesi gibi `- tap: ...` yazımı kabul edilir; komut adları büyük/küçük harf duyarsızdır.
/// - Değerler tırnaklı (`"..."`, `'...'`) ya da tırnaksız yazılabilir. `->` veya ` #` içeren
///   değerler tırnaklanmalıdır. iOS klavyesinin akıllı tırnakları (“ ” ‘ ’) da kabul edilir.
/// - Hatalı satırlar toplanır ve hepsi tek seferde `FlowParseError` olarak döner.
public struct FlowParser: Sendable {
    /// `wait` için izin verilen en uzun süre (saniye).
    public static let maxWaitSeconds: Double = 300

    public init() {}

    public func parse(_ script: String) throws(FlowParseError) -> [TestStep] {
        var steps: [TestStep] = []
        var issues: [FlowParseError.Issue] = []

        let lines = script.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        for (offset, rawLine) in lines.enumerated() {
            let lineNumber = offset + 1
            do {
                guard let command = try parseLine(rawLine) else { continue }
                let source = rawLine.trimmingCharacters(in: .whitespaces)
                steps.append(TestStep(id: steps.count, line: lineNumber, source: source, command: command))
            } catch {
                issues.append(FlowParseError.Issue(line: lineNumber, message: error.message))
            }
        }

        if issues.isEmpty, steps.isEmpty {
            issues.append(FlowParseError.Issue(line: nil, message: "Çalıştırılacak adım yok."))
        }
        guard issues.isEmpty else { throw FlowParseError(issues: issues) }
        return steps
    }

    /// Bir değeri parser'ın geri okuyabileceği tırnaklı biçime çevirir (panelde satır üretmek için).
    public static func quote(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\"\(escaped)\""
    }

    /// Değeri olabilecek en sade biçimde yazar: güvenliyse tırnaksız, değilse tek ya da çift tırnaklı.
    /// JSON katalogda `"tap: login_button"` gibi kaçışsız satırlar üretmek için.
    public static func literal(_ value: String) -> String {
        let quoteCharacters: Set<Character> = ["\"", "'", "“", "”", "„", "‘", "’"]
        let needsQuotes = value.isEmpty
            || value != value.trimmingCharacters(in: .whitespaces)
            || value.contains("->") || value.contains("→") || value.contains("#")
            || value.contains(where: \.isNewline)
            || value.first.map(quoteCharacters.contains) == true
        guard needsQuotes else { return value }
        if !value.contains("'"), !value.contains("\\"), !value.contains(where: \.isNewline) {
            return "'\(value)'"
        }
        return quote(value)
    }

    // MARK: - Satır

    private func parseLine(_ rawLine: Substring) throws(LineError) -> TestCommand? {
        var line = Substring(rawLine.trimmingCharacters(in: .whitespaces))
        guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
        if line.hasPrefix("- ") {
            line = line.dropFirst(2).drop(while: \.isWhitespace)
        }

        guard let colon = line.firstIndex(of: ":") else {
            throw LineError("':' eksik. Beklenen biçim → komut: değer")
        }
        let keyword = line[..<colon].trimmingCharacters(in: .whitespaces)
        var scanner = ArgumentScanner(line[line.index(after: colon)...])

        let command: TestCommand
        switch keyword.lowercased() {
        case "tap":
            command = .tap(ElementSelector(try scanner.value()))

        case "type":
            let target = try scanner.value(stopsAtArrow: true)
            guard scanner.consumeArrow() else {
                throw LineError("'type' komutunda '->' eksik. Örnek → type: \"email_field\" -> \"metin\"")
            }
            // Boş metin ("") alanı temizlemek için geçerlidir.
            command = .typeText(ElementSelector(target), text: try scanner.value(allowsEmpty: true))

        case "wait":
            let raw = try scanner.value()
            // Türkçe klavyede ondalık ayırıcı virgül olabilir: "wait: 1,5"
            guard let seconds = Double(raw.replacingOccurrences(of: ",", with: ".")),
                  seconds.isFinite, (0...Self.maxWaitSeconds).contains(seconds) else {
                throw LineError("Geçersiz süre '\(raw)'. 0–\(Int(Self.maxWaitSeconds)) arası saniye bekleniyor (ör. wait: 1.5)")
            }
            command = .wait(seconds: seconds)

        case "assertvisible":
            command = .assertVisible(ElementSelector(try scanner.value()))

        default:
            throw LineError("Bilinmeyen komut '\(keyword)'. Desteklenenler → tap, type, wait, assertVisible")
        }

        try scanner.expectEnd()
        return command
    }
}

/// Parser'ın topladığı satır hataları.
public struct FlowParseError: Error, Equatable, Sendable, CustomStringConvertible {
    public struct Issue: Equatable, Sendable, CustomStringConvertible {
        /// 1 tabanlı satır; akışın genelini ilgilendiren hatalarda `nil`.
        public let line: Int?
        public let message: String

        public init(line: Int?, message: String) {
            self.line = line
            self.message = message
        }

        public var description: String {
            line.map { "Satır \($0): \(message)" } ?? message
        }
    }

    public let issues: [Issue]

    public var description: String {
        issues.map(\.description).joined(separator: "\n")
    }
}

// MARK: - Argüman tarayıcı

struct LineError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

/// Komut adından sonraki argüman kısmını karakter karakter okuyan küçük tarayıcı.
struct ArgumentScanner {
    private static let doubleQuotes: Set<Character> = ["\"", "“", "”", "„"]
    private static let singleQuotes: Set<Character> = ["'", "‘", "’"]

    private let characters: [Character]
    private var position = 0

    init(_ text: Substring) {
        characters = Array(text)
    }

    /// Tırnaklı ya da tırnaksız tek bir değer okur.
    mutating func value(stopsAtArrow: Bool = false, allowsEmpty: Bool = false) throws(LineError) -> String {
        skipWhitespace()
        guard let first = peek(), !isCommentStart(at: position) else {
            throw LineError("Değer eksik.")
        }

        let value: String
        if Self.doubleQuotes.contains(first) {
            value = try quoted(closers: Self.doubleQuotes)
        } else if Self.singleQuotes.contains(first) {
            value = try quoted(closers: Self.singleQuotes)
        } else {
            value = bare(stopsAtArrow: stopsAtArrow)
        }

        guard allowsEmpty || !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw LineError("Değer boş olamaz.")
        }
        return value
    }

    /// `->` (veya `→`) ayırıcısını tüketir.
    mutating func consumeArrow() -> Bool {
        skipWhitespace()
        if peek() == "→" {
            position += 1
            return true
        }
        guard peek() == "-", peek(offset: 1) == ">" else { return false }
        position += 2
        return true
    }

    /// Satırda değerden sonra yalnızca boşluk ya da yorum kalmasını şart koşar.
    mutating func expectEnd() throws(LineError) {
        skipWhitespace()
        guard position < characters.count, !isCommentStart(at: position) else { return }
        throw LineError("Beklenmeyen içerik: '\(String(characters[position...]))'")
    }

    // MARK: Yardımcılar

    private mutating func quoted(closers: Set<Character>) throws(LineError) -> String {
        position += 1 // açılış tırnağı
        var result = ""
        while let character = peek() {
            position += 1
            if closers.contains(character) {
                return result
            }
            if character == "\\", let escaped = peek() {
                position += 1
                switch escaped {
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: result.append(escaped) // \" \' \\
                }
            } else {
                result.append(character)
            }
        }
        throw LineError("Kapanmamış tırnak.")
    }

    private mutating func bare(stopsAtArrow: Bool) -> String {
        let start = position
        while position < characters.count {
            if isCommentStart(at: position) { break }
            if stopsAtArrow, characters[position] == "→" { break }
            if stopsAtArrow, characters[position] == "-", peek(offset: 1) == ">" { break }
            position += 1
        }
        return String(characters[start..<position]).trimmingCharacters(in: .whitespaces)
    }

    /// YAML'daki gibi: `#` ancak satır başında ya da bir boşluktan sonra yorum başlatır.
    private func isCommentStart(at index: Int) -> Bool {
        guard index < characters.count, characters[index] == "#" else { return false }
        return index == 0 || characters[index - 1].isWhitespace
    }

    private mutating func skipWhitespace() {
        while let character = peek(), character.isWhitespace {
            position += 1
        }
    }

    private func peek(offset: Int = 0) -> Character? {
        let index = position + offset
        return index < characters.count ? characters[index] : nil
    }
}
