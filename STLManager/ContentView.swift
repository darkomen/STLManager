import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedItem: InboxItem?

    @AppStorage("scanInterval") private var scanInterval = 10
    @AppStorage("monitorDownloads") private var monitorDownloads = true
    @AppStorage("autoImportEnabled") private var autoImportEnabled = false
    @AppStorage("inboxFolder") private var inboxFolder = ""
    @AppStorage("libraryFolder") private var libraryFolder = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 62, height: 62)
                    .background(.blue.gradient, in: RoundedRectangle(cornerRadius: 16))

                VStack(alignment: .leading, spacing: 4) {
                    Text("STL Manager")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                    Text("Tu estación de entrada para modelos 3D")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label(monitorDownloads ? "Vigilando _Inbox" : "Monitorización pausada",
                      systemImage: monitorDownloads ? "checkmark.circle.fill" : "pause.circle")
                    .font(.caption)
                    .foregroundStyle(monitorDownloads ? Color.green : Color.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.quaternary.opacity(0.45), in: Capsule())

                // Reutiliza la escena Settings { SettingsView() } de STLManagerApp.
                // El mismo panel sigue accesible desde el menú de estado de macOS.
                SettingsLink {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("Ajustes de STL Manager")
                .accessibilityLabel("Ajustes de STL Manager")
            }
            .padding(.bottom, 26)

            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("PENDIENTES DE IMPORTAR")
                        .font(.caption2.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text("\(appState.pendingCount)")
                            .font(.system(size: 38, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(appState.pendingCount == 1 ? "elemento" : "elementos")
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button { appState.scanDownloads() } label: {
                    Label("Actualizar", systemImage: "arrow.clockwise")
                }
                .controlSize(.large)
                Button { showNormalizer = true } label: {
                    Label("Normalizar biblioteca", systemImage: "square.stack.3d.up")
                }
                .controlSize(.large)
            }
            .padding(20)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 16))

            if let error = appState.monitoringError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .padding(.top, 16)
            }

            if let status = appState.autoImportStatus {
                Label(status, systemImage: "shippingbox.and.arrow.backward")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.top, 10)
            }

            HStack {
                Text("Bandeja de entrada")
                    .font(.headline)
                Spacer()
                Text("STL · 3MF · STEP · ZIP · Carpetas")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 25)
            .padding(.bottom, 12)

            if appState.inboxItems.isEmpty {
                VStack(spacing: 11) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(.blue.opacity(0.65))
                        .padding(.bottom, 3)
                    Text("Todo al día")
                        .font(.title2.weight(.semibold))
                    Text("Arrastra tus archivos 3D o carpetas a _Inbox.\nLos detectaremos automáticamente y te avisaremos.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button { openInboxInFinder() } label: {
                        Label("Abrir _Inbox en Finder", systemImage: "folder")
                    }
                    .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.quaternary.opacity(0.14), in: RoundedRectangle(cornerRadius: 16))
            } else {
                List(appState.inboxItems) { item in
                    Button { selectedItem = item } label: {
                        HStack(spacing: 14) {
                            Image(systemName: item.symbolName)
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .frame(width: 38, height: 38)
                                .background(.blue.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.displayName).fontWeight(.medium).foregroundStyle(.primary)
                                Text(item.kindDescription).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.inset)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            HStack {
                Image(systemName: "bell.badge")
                Text("Las notificaciones se envían cuando se detectan elementos nuevos y estables.")
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.top, 16)
        }
        .padding(26)
        .frame(minWidth: 780, minHeight: 550)
        .task {
            appState.startMonitoring()
            openPendingNotificationItem()
        }
        .onAppear { openPendingNotificationItem() }
        .sheet(item: $selectedItem) { item in ImportView(initialItem: item) }
        .alert("No se pudo abrir _Inbox", isPresented: Binding(
            get: { finderError != nil },
            set: { if !$0 { finderError = nil } }
        )) {
            Button("Aceptar", role: .cancel) { }
        } message: {
            Text(finderError ?? "")
        }
        .sheet(isPresented: $showNormalizer) { NormalizationView() }
        .onChange(of: scanInterval) { appState.startMonitoring() }
        .onChange(of: monitorDownloads) { appState.startMonitoring() }
        .onChange(of: autoImportEnabled) { appState.startMonitoring() }
        .onChange(of: inboxFolder) { appState.startMonitoring() }
        .onChange(of: libraryFolder) { appState.startMonitoring() }
        .onReceive(NotificationCenter.default.publisher(for: InboxNotificationRouter.openItem)) { _ in
            openPendingNotificationItem()
        }
        .onChange(of: appState.inboxItems.map(\.id)) {
            openPendingNotificationItem()
        }
    }

    @State private var showNormalizer = false

    @MainActor
    private func openPendingNotificationItem() {
        let router = InboxNotificationRouter.shared
        guard let path = router.pendingInboxPath else { return }

        // Si la app estaba cerrada o inactiva, la lista puede no estar aún cargada.
        // Volvemos a probar cuando se actualice inboxItems, sin perder el enlace.
        guard let item = appState.inboxItems.first(where: {
            $0.url.standardizedFileURL.path == path
        }) else { return }

        // Si hay otro asistente abierto, cerrarlo antes de abrir el seleccionado.
        // El clic en la notificación debe dirigir inequívocamente al archivo indicado.
        if selectedItem?.id != item.id {
            selectedItem = item
        }
        router.markOpened(path: path)
    }

    @State private var finderError: String?

    private func openInboxInFinder() {
        do {
            // Usar el MISMO bookmark que ya funciona en el monitor de _Inbox.
            guard let folder = try FolderAccess.resolveBookmark(key: "inboxBookmark") else {
                finderError = "Selecciona de nuevo la carpeta _Inbox en Preferencias para conceder acceso."
                return
            }
            guard folder.startAccessingSecurityScopedResource() else {
                finderError = "No se pudo activar el permiso de _Inbox. Selecciona de nuevo la carpeta en Preferencias."
                return
            }
            defer { folder.stopAccessingSecurityScopedResource() }

            let values = try folder.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                finderError = "La ubicación configurada como _Inbox ya no es una carpeta válida."
                return
            }
            // Solicitar a Finder que revele la carpeta; no intentar abrirla como
            // documento, lo que podía lanzar el cuadro «sin permiso».
            NSWorkspace.shared.activateFileViewerSelecting([folder])
            finderError = nil
        } catch {
            finderError = "No se pudo abrir _Inbox en Finder: \(error.localizedDescription)"
        }
    }
}

#Preview { ContentView().environment(AppState()) }
