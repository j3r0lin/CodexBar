import AppKit
import CodexBarCore
import SwiftUI
import UniformTypeIdentifiers

struct PreferencesTransferSection: View {
    @Bindable var settings: SettingsStore
    @State private var failure: String?

    var body: some View {
        Section {
            HStack {
                Button(L("Export Preferences…")) { self.transfer(importing: false) }
                Button(L("Import Preferences…")) { self.transfer(importing: true) }
            }
        } header: {
            Text(L("Portable preferences"))
        } footer: {
            Text(
                L(
                    "Save display and notification preferences for your dotfiles. "
                        + "Accounts, credentials, login, local paths and consent stay on this Mac."))
        }
        .alert(L("Preferences could not be transferred"), isPresented: Binding(
            get: { self.failure != nil }, set: { if !$0 { self.failure = nil } }))
        {
            Button(L("OK")) { self.failure = nil }
        } message: {
            Text(self.failure ?? "")
        }
    }

    private func transfer(importing: Bool) {
        let panel: NSSavePanel = importing ? NSOpenPanel() : NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "preferences.json"
        if let open = panel as? NSOpenPanel { open.allowsMultipleSelection = false }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if importing {
                try self.settings.importPreferences(PreferencesDocument(data: Data(contentsOf: url)))
            } else {
                try self.settings.exportPreferences().encoded().write(to: url, options: .atomic)
            }
        } catch {
            self.failure = error.localizedDescription
        }
    }
}
