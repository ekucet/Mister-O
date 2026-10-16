import Foundation

/// Bir akış koşusunun genel durumu.
public enum RunState: Equatable, Sendable {
    case idle
    case running
    case passed
    case failed
    case cancelled
    case invalidScript

    public var isFinished: Bool {
        switch self {
        case .passed, .failed, .cancelled: true
        case .idle, .running, .invalidScript: false
        }
    }

    public var title: String {
        switch self {
        case .idle: "Hazır"
        case .running: "Çalışıyor"
        case .passed: "Başarılı"
        case .failed: "Başarısız"
        case .cancelled: "Durduruldu"
        case .invalidScript: "Akış hatalı"
        }
    }
}

/// Tek bir adımın sonucu; panelin log penceresi bu listeyi gösterir.
public struct StepResult: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case pending
        case running
        case passed
        case failed(String)
        case skipped

        public var symbol: String {
            switch self {
            case .pending: "·"
            case .running: "…"
            case .passed: "✓"
            case .failed: "✗"
            case .skipped: "–"
            }
        }
    }

    public let step: TestStep
    public internal(set) var status: Status = .pending
    public internal(set) var duration: Duration?

    public var id: Int { step.id }

    init(step: TestStep) {
        self.step = step
    }
}

extension Duration {
    /// "1.25 sn" biçiminde kısa gösterim.
    public var secondsText: String {
        let parts = components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        return String(format: "%.2f sn", seconds)
    }

    /// Bir dakikanın altında "4.73 sn", üstünde "2 dk 14 sn".
    public var compactText: String {
        let parts = components
        let seconds = Double(parts.seconds) + Double(parts.attoseconds) / 1e18
        guard seconds >= 60 else { return secondsText }
        let total = Int(seconds.rounded())
        return "\(total / 60) dk \(total % 60) sn"
    }
}
