import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("libraryFolder") private var libraryFolder = ""
    @AppStorage("inboxFolder") private var inboxFolder = ""
    @AppStorage("monitorDownloads") private var monitorDownloads = true
    @AppStorage("scanInterval") private var scanInterval = 10
    @State private var message: String?

    var body: some View {
        Form {
            Section("Biblioteca de proyectos") {
                folderRow("Biblioteca", path: libraryFolder) { selectFolder(for: "library") }
            }
            Section("Carpeta de observación") {
                folderRow("_Inbox", path: inboxFolder) { selectFolder(for: "inbox") }
                Text("Selecciona _Inbox expresamente para conservar el permiso de acceso.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Monitorización") {
                Toggle("Activar monitorización", isOn: $monitorDownloads)
                Picker("Comprobar cada", selection: $scanInterval) {
                    Text("5 segundos").tag(5)
                    Text("10 segundos").tag(10)
                    Text("30 segundos").tag(30)
                    Text("60 segundos").tag(60)
                }.disabled(!monitorDownloads)
            }
            if let message { Text(message).foregroundStyle(.orange) }
        }
        .formStyle(.grouped)
        .frame(width: 620, height: 420)
    }

    private func folderRow(_ title: String, path: String, action: @escaping () -> Void) -> some View {
        HStack {
            Text(title)
            Text(path.isEmpty ? "Sin configurar" : path)
                .foregroundStyle(.secondary)
                .lineLimit(1).truncationMode(.middle).help(path)
            Spacer()
            Button("Seleccionar…", action: action)
        }
    }

    private func selectFolder(for kind: String) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            if kind == "library" {
                try FolderAccess.saveBookmark(for: url, key: "libraryBookmark")
                libraryFolder = url.path
            } else {
                try FolderAccess.saveBookmark(for: url, key: "inboxBookmark")
                inboxFolder = url.path
            }
            message = nil
        } catch { message = "No se pudo guardar el permiso: \(error.localizedDescription)" }
    }
}
