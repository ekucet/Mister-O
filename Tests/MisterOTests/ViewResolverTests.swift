#if canImport(UIKit)
import Testing
import UIKit
@testable import MisterO

@MainActor
struct ViewResolverTests {
    private let window: UIWindow = {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.isHidden = false
        return window
    }()

    private var resolver: ViewResolver {
        ViewResolver(windows: { [window] in [window] })
    }

    @discardableResult
    private func addLabel(_ text: String, frame: CGRect, to parent: UIView? = nil) -> UILabel {
        let label = UILabel(frame: frame)
        label.text = text
        (parent ?? window).addSubview(label)
        return label
    }

    @Test func identifierBeatsVisibleText() {
        let titled = UIButton(type: .system)
        titled.setTitle("Login", for: .normal)
        titled.frame = CGRect(x: 0, y: 100, width: 200, height: 44)
        let identified = UIButton(type: .system)
        identified.accessibilityIdentifier = "Login"
        identified.frame = CGRect(x: 0, y: 200, width: 200, height: 44)
        window.addSubview(titled)
        window.addSubview(identified)

        let matches = resolver.findAll("Login")
        #expect(matches.first?.match == .identifier)
        if case .view(let view) = matches.first?.backing { #expect(view === identified) }
        #expect(matches.contains { if case .view(let view) = $0.backing { view === titled } else { false } })
    }

    @Test func frontmostWinsForEqualMatches() {
        addLabel("Devam", frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        let front = addLabel("Devam", frame: CGRect(x: 0, y: 0, width: 100, height: 30))

        guard case .view(let view) = resolver.find("Devam")?.backing else {
            Issue.record("öğe bulunmalıydı")
            return
        }
        #expect(view === front)
    }

    @Test func ignoresHiddenTransparentAndClippedViews() {
        addLabel("gizli", frame: CGRect(x: 0, y: 0, width: 100, height: 30)).isHidden = true

        let faded = UIView(frame: window.bounds)
        faded.alpha = 0
        window.addSubview(faded)
        addLabel("saydam", frame: CGRect(x: 0, y: 0, width: 100, height: 30), to: faded)

        let scroll = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 300))
        scroll.contentSize = CGSize(width: 390, height: 3000)
        window.addSubview(scroll)
        addLabel("aşağıda", frame: CGRect(x: 0, y: 2000, width: 100, height: 30), to: scroll)
        addLabel("yukarıda", frame: CGRect(x: 0, y: 10, width: 100, height: 30), to: scroll)

        #expect(resolver.find("gizli") == nil)
        #expect(resolver.find("saydam") == nil)
        #expect(resolver.find("aşağıda") == nil)
        #expect(resolver.find("yukarıda") != nil)

        scroll.contentOffset = CGPoint(x: 0, y: 1900)
        #expect(resolver.find("aşağıda") != nil)
        #expect(resolver.find("yukarıda") == nil)
    }

    @Test func fallsBackToCaseInsensitiveText() {
        addLabel("Giriş Yap", frame: CGRect(x: 0, y: 0, width: 100, height: 30))
        #expect(resolver.find("giriş yap")?.match == .caseInsensitiveText)
        #expect(resolver.find("Giriş") == nil)
    }

    @Test func inspectListsControlsButNotTheirInnerLabels() {
        let button = UIButton(type: .system)
        button.setTitle("Kaydet", for: .normal)
        button.accessibilityIdentifier = "save_button"
        button.frame = CGRect(x: 0, y: 300, width: 200, height: 44)
        window.addSubview(button)
        button.layoutIfNeeded()
        addLabel("Başlık", frame: CGRect(x: 0, y: 50, width: 100, height: 30))

        let items = resolver.inspect()
        #expect(items.map(\.suggestedQuery) == ["Başlık", "save_button"])
    }

    @Test func tapFiresEveryKindOfButtonActionExactlyOnce() throws {
        var counts = (target: 0, primaryInit: 0, primaryAdded: 0, custom: 0)

        let initButton = UIButton(configuration: .filled(), primaryAction: UIAction(title: "Kaydet") { _ in counts.primaryInit += 1 })
        initButton.addAction(UIAction { _ in counts.target += 1 }, for: .touchUpInside)
        initButton.frame = CGRect(x: 0, y: 100, width: 200, height: 44)

        let addedButton = UIButton(type: .system)
        addedButton.setTitle("Ekle", for: .normal)
        addedButton.addAction(UIAction { _ in counts.primaryAdded += 1 }, for: .primaryActionTriggered)
        addedButton.frame = CGRect(x: 0, y: 200, width: 200, height: 44)

        let customControl = UIControl(frame: CGRect(x: 0, y: 300, width: 200, height: 44))
        customControl.accessibilityIdentifier = "custom"
        customControl.addAction(UIAction { _ in counts.custom += 1 }, for: .primaryActionTriggered)

        [initButton, addedButton, customControl].forEach(window.addSubview)

        for query in ["Kaydet", "Ekle", "custom"] {
            try ActionExecutor().tap(try #require(resolver.find(ElementSelector(query))))
        }

        #expect(counts.target == 1)
        #expect(counts.primaryInit == 1)
        #expect(counts.primaryAdded == 1)
        #expect(counts.custom == 1)
    }

    @Test func inspectReportsFieldKindsValuesAndState() {
        let email = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
        email.accessibilityIdentifier = "email"
        email.keyboardType = .emailAddress
        let password = UITextField(frame: CGRect(x: 0, y: 50, width: 200, height: 40))
        password.accessibilityIdentifier = "password"
        password.isSecureTextEntry = true
        password.text = "gizli123"
        let send = UIButton(type: .system)
        send.setTitle("Gönder", for: .normal)
        send.frame = CGRect(x: 0, y: 100, width: 200, height: 44)
        send.isEnabled = false
        [email, password, send].forEach(window.addSubview)

        let items = Dictionary(uniqueKeysWithValues: resolver.inspect().map { ($0.suggestedQuery, $0) })
        #expect(items["email"]?.inputKind == "email")
        #expect(items["email"]?.value == nil)
        #expect(items["password"]?.inputKind == "password")
        #expect(items["password"]?.value == "(gizli, dolu)")
        #expect(items["Gönder"]?.isEnabled == false)

        let driver = UIKitDriver(resolver: resolver)
        #expect(driver.isEnabled("Gönder") == false)
        #expect(driver.isEnabled("email") == true)
        #expect(driver.isEnabled("yok") == nil)
    }

    @Test func tapOnDisabledControlIsRetryable() throws {
        let button = UIButton(type: .system)
        button.setTitle("Gönder", for: .normal)
        button.isEnabled = false
        button.frame = CGRect(x: 0, y: 100, width: 200, height: 44)
        window.addSubview(button)

        let element = try #require(resolver.find("Gönder"))
        #expect(throws: DriverError.elementDisabled("Gönder")) { try ActionExecutor().tap(element) }
    }
}
#endif
