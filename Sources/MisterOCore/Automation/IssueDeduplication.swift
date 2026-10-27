import Foundation

/// Takip aracında bir parmak iziyle açık kaydı arayabilen kayıt açıcı (ör. `JiraIssueReporter`).
/// Böylece farklı cihazlar ve CI koşuları aynı hata için tek kayıtta buluşur.
public protocol IssueSearching: Sendable {
    /// Aynı parmak izli, kapanmamış kayıt; yoksa `nil`.
    func existingIssue(fingerprint: String) async throws -> IssueReceipt?
}

/// Bu cihazda hangi hata için hangi kaydın açıldığını hatırlar; arama yapamayan takip araçlarında aynı
/// hatanın her koşuda yeniden kayıt açmasını önler.
public protocol IssueLedger: Sendable {
    func receipt(for fingerprint: String) -> IssueReceipt?
    func record(_ receipt: IssueReceipt, for fingerprint: String)
}

/// `UserDefaults`'ta tutulan defter. Kayıtlar `lifetime` kadar hatırlanır (varsayılan 7 gün): kapanmış bir
/// kaydın hatası yeniden çıkarsa bir hafta sonra yeni kayıt açılır.
public final class UserDefaultsIssueLedger: IssueLedger, @unchecked Sendable {
    private struct Entry: Codable {
        let key: String?
        let url: URL?
        let date: Date
    }

    private let defaults: UserDefaults
    private let lifetime: TimeInterval
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private static let storageKey = "MisterO.issueLedger"

    public init(defaults: UserDefaults = .standard, lifetime: TimeInterval = 7 * 24 * 3600,
                now: @escaping @Sendable () -> Date = Date.init) {
        self.defaults = defaults
        self.lifetime = lifetime
        self.now = now
    }

    public func receipt(for fingerprint: String) -> IssueReceipt? {
        lock.withLock {
            guard let entry = entries()[fingerprint], now().timeIntervalSince(entry.date) < lifetime else { return nil }
            return IssueReceipt(key: entry.key, url: entry.url, isExisting: true)
        }
    }

    public func record(_ receipt: IssueReceipt, for fingerprint: String) {
        lock.withLock {
            var all = entries().filter { now().timeIntervalSince($0.value.date) < lifetime }
            all[fingerprint] = Entry(key: receipt.key, url: receipt.url, date: now())
            if let data = try? JSONEncoder().encode(all) {
                defaults.set(data, forKey: Self.storageKey)
            }
        }
    }

    private func entries() -> [String: Entry] {
        guard let data = defaults.data(forKey: Self.storageKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }
}

/// Parmak izli kayıtları tekilleştiren sarmalayıcı. Kurulumda verilen `issueReporter` bununla sarılır;
/// panelden, asistandan ve autorun'dan açılan kayıtların hepsi buradan geçer.
///
/// 1. Takip aracı arama yapabiliyorsa (`IssueSearching`) açık kaydı orada arar; bulursa onu döner.
/// 2. Arama yoksa ya da başarısız olursa bu cihazın defterine bakar.
/// 3. İkisi de yoksa yeni kayıt açar ve deftere yazar.
public struct DeduplicatingIssueReporter: IssueReporter {
    public let base: any IssueReporter
    public let ledger: any IssueLedger

    public init(_ base: any IssueReporter, ledger: any IssueLedger = UserDefaultsIssueLedger()) {
        self.base = base
        self.ledger = ledger
    }

    public var name: String { base.name }

    public func open(_ report: BugReport) async throws -> IssueReceipt {
        guard let fingerprint = report.fingerprint else { return try await base.open(report) }

        // Arama cevap verdiyse o geçerlidir: kayıt kapandıysa defter ne derse desin yenisi açılır.
        // `nil`: arama yok ya da başarısız; `.some(nil)`: arandı, açık kayıt yok.
        var search: IssueReceipt?? = nil
        if let searching = base as? any IssueSearching {
            do {
                search = .some(try await searching.existingIssue(fingerprint: fingerprint))
            } catch {
                search = nil
            }
        }
        switch search {
        case .some(.some(let found)):
            let existing = IssueReceipt(key: found.key, url: found.url, isExisting: true)
            ledger.record(existing, for: fingerprint)
            return existing
        case .some(.none):
            break
        case .none:
            if let known = ledger.receipt(for: fingerprint) {
                return known
            }
        }
        let receipt = try await base.open(report)
        ledger.record(receipt, for: fingerprint)
        return receipt
    }
}
