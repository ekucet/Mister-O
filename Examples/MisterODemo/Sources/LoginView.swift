import SwiftUI

struct LoginView: View {
    let onLogin: (String) -> Void

    @State private var email = ""
    @State private var password = ""

    var body: some View {
        Form {
            Section("Hesap") {
                TextField("E-posta", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("email_field")
                SecureField("Şifre", text: $password)
                    .accessibilityIdentifier("password_field")
            }

            Section {
                Button("Giriş Yap") { onLogin(email) }
                    .disabled(!email.contains("@") || password.count < 6)
                    .accessibilityIdentifier("login_button")
            }
        }
        .navigationTitle("Giriş")
    }
}

struct WelcomeView: View {
    let email: String

    var body: some View {
        List {
            Text("Hoş geldin, \(email)")
                .font(.title3)
                .accessibilityIdentifier("welcome_label")
            NavigationLink("UIKit Ekranı", value: Route.uikit)
            NavigationLink("Ayarlar", value: Route.settings)
        }
        .navigationTitle("Ana Sayfa")
    }
}
