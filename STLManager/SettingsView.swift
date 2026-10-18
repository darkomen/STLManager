import SwiftUI
import AppKit

struct SettingsView: View {
    @AppStorage("libraryFolder") private var libraryFolder = ""
    @AppStorage("inboxFolder") private var inboxFolder = ""
    @AppStorage("monitorDownloads") private var monitorDownloads = true
    @AppStorage("scanInterval") private var scanInterval = 10
    @AppStorage("autoImportEnabled") private var autoImportEnabled = false
    @AppStorage("autoImportNotifySuccess") private var autoImportNotifySuccess = true
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
            Section("Importación automática") {
                Toggle("Importar automáticamente los elementos estables de _Inbox", isOn: $autoImportEnabled)
                    .disabled(!monitorDownloads)
                Text("La importación automática espera al menos el doble del intervalo de monitorización con el elemento estable. Ejemplo: 10 s de vigilancia → 20 s antes de importar. Puedes importarlo manualmente durante ese tiempo.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Notificar cuando termine una importación", isOn: $autoImportNotifySuccess)
                    .disabled(!autoImportEnabled || !monitorDownloads)
                Text("Desactivada por defecto. Los archivos se copian, verifican y después se envían a la Papelera, igual que en la importación manual. Si el nombre ya existe o hay un error, el elemento permanece en _Inbox para gestionarlo manualmente.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message { Text(message).foregroundStyle(.orange) }
        }
        .formStyle(.grouped)
        .frame(width: 670, height: 550)
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
