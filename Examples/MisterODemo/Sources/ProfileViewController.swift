import SwiftUI
import UIKit

/// SDK'nın UIKit yolunu (UITextField + UIButton primaryAction + UILabel) göstermek için.
final class ProfileViewController: UIViewController {
    private let nicknameField = UITextField()
    private let resultLabel = UILabel()
    private var saveCount = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        nicknameField.placeholder = "Takma ad"
        nicknameField.borderStyle = .roundedRect
        nicknameField.accessibilityIdentifier = "nickname_field"

        let saveButton = UIButton(configuration: .filled(), primaryAction: UIAction(title: "Kaydet") { [weak self] _ in
            self?.save()
        })

        resultLabel.accessibilityIdentifier = "save_result"
        resultLabel.textColor = .secondaryLabel

        let stack = UIStackView(arrangedSubviews: [nicknameField, saveButton, resultLabel])
        stack.axis = .vertical
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])
    }

    private func save() {
        saveCount += 1
        // Sayaç, programatik dokunuşun tam bir kez tetiklendiğini doğrulamak için.
        resultLabel.text = "Kaydedildi: \(nicknameField.text ?? "") (\(saveCount))"
    }
}

struct ProfileScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ProfileViewController { ProfileViewController() }
    func updateUIViewController(_ controller: ProfileViewController, context: Context) {}
}
