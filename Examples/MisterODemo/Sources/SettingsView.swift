import SwiftUI

/// Kaydırma, uyarı, onay penceresi, sheet ve geri gitme komutlarını denemek için uzun bir ayarlar ekranı.
struct SettingsView: View {
    @State private var notifications = true
    @State private var confirmsDelete = false
    @State private var confirmsSignOut = false
    @State private var showsHelp = false
    @State private var status = "Hesap aktif"

    var body: some View {
        List {
            Section {
                Toggle("Bildirimler", isOn: $notifications)
                    .accessibilityIdentifier("notifications_toggle")
                Button("Yardım") { showsHelp = true }
                    .accessibilityIdentifier("help_button")
                Text(status)
                    .accessibilityIdentifier("account_status")
            }
            Section("Tercihler") {
                ForEach(1...30, id: \.self) { index in
                    Text("Tercih \(index)")
                }
            }
            Section {
                Button("Çıkış yap") { confirmsSignOut = true }
                    .accessibilityIdentifier("sign_out_button")
                Button("Hesabı sil", role: .destructive) { confirmsDelete = true }
                    .accessibilityIdentifier("delete_account_button")
            }
        }
        .navigationTitle("Ayarlar")
        .alert("Hesap silinsin mi?", isPresented: $confirmsDelete) {
            Button("Vazgeç", role: .cancel) {}
            Button("Sil", role: .destructive) { status = "Hesap silindi" }
        } message: {
            Text("Bu işlem geri alınamaz.")
        }
        .confirmationDialog("Çıkış yapılsın mı?", isPresented: $confirmsSignOut, titleVisibility: .visible) {
            Button("Çıkış yap", role: .destructive) { status = "Çıkış yapıldı" }
        }
        .sheet(isPresented: $showsHelp) {
            NavigationStack {
                Text("Mister-O demo yardımı")
                    .accessibilityIdentifier("help_text")
                    .navigationTitle("Yardım")
            }
        }
    }
}
