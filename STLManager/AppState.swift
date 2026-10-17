import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var inboxItems: [InboxItem] = []
    var monitoringError: String?

    private var timer: DispatchSourceTimer?
    // Al arrancar, los elementos preexistentes son conocidos, no "nuevos".
    private var initializedInbox = false
    private var knownPaths: Set<String> = []
    private var stability: [String: (signature: String, firstSeen: Date)] = [:]
    private var notified: Set<String> = []
    private var autoAttempted: [String: String] = [:]
    private var autoInProgress = false
    var autoImportStatus: String?

    private var autoImportEnabled: Bool {
        isEnabled && UserDefaults.standard.bool(forKey: "autoImportEnabled")
    }
    private var notifyAutoSuccess: Bool {
        UserDefaults.standard.object(forKey: "autoImportNotifySuccess") as? Bool ?? true
    }

    private let validExtensions: Set<String> = [
        "stl", "step", "stp", "3mf", "zip", "scad", "f3d", "obj"
    ]

    var pendingCount: Int { inboxItems.count }

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "monitorDownloads") as? Bool ?? true
    }

    private var interval: TimeInterval {
        let value = UserDefaults.standard.integer(forKey: "scanInterval")
        return TimeInterval([5, 10, 30, 60].contains(value) ? value : 10)
    }

    func startMonitoring() {
        stopMonitoring()

        guard isEnabled else {
            inboxItems = []
            monitoringError = nil
            return
        }

        InboxNotificationRouter.shared.configure()
        scanDownloads()

        // DispatchSourceTimer no depende del modo activo del RunLoop de AppKit.
        // Sigue escaneando cuando la ventana pierde foco, está minimizada
        // o macOS está procesando menús/eventos de la interfaz.
        let source = DispatchSource.makeTimerSource(queue: .main)
        source.schedule(deadline: .now() + interval, repeating: interval)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scanDownloads()
            }
        }
        timer = source
        source.resume()
    }

    // Conservamos el nombre para no romper llamadas de ContentView/STLManagerApp.
    // En una futura limpieza lo renombraremos a scanInbox().
    func scanDownloads() {
        guard isEnabled else {
            inboxItems = []
            monitoringError = nil
            return
        }

        let folder: URL
        do {
            guard let resolved = try FolderAccess.resolveBookmark(key: "inboxBookmark") else {
                inboxItems = []
                monitoringError = "Selecciona _Inbox en Preferencias para autorizar su acceso."
                return
            }
            folder = resolved
        } catch {
            inboxItems = []
            monitoringError = "No se pudo recuperar el permiso: \(error.localizedDescription)"
            return
        }

        guard folder.startAccessingSecurityScopedResource() else {
            inboxItems = []
            monitoringError = "No se pudo activar el acceso a _Inbox."
            return
        }
        defer { folder.stopAccessingSecurityScopedResource() }

        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey,
            .contentModificationDateKey
        ]

        do {
            let entries = try FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles]
            )

            let candidates = entries.compactMap { url -> InboxItem? in
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isSymbolicLink != true else { return nil }

                if values.isDirectory == true {
                    // Una carpeta de primer nivel es un solo proyecto.
                    let files = modelFiles(in: url)
                    guard !files.isEmpty else { return nil }
                    return InboxItem(url: url, type: .folder, files: files)
                }

                guard values.isRegularFile == true,
                      validExtensions.contains(url.pathExtension.lowercased()) else {
                    return nil
                }

                // Evita listar un archivo recién creado; no garantiza por sí solo
                // que una descarga esté completa (se comprobará antes de importar).
                if let modified = values.contentModificationDate,
                   Date().timeIntervalSince(modified) < 15 {
                    return nil
                }

                let kind: InboxItemType = url.pathExtension.lowercased() == "zip"
                    ? .archive : .singleFile
                return InboxItem(url: url, type: kind, files: [url])
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            let current = Set(candidates.map { $0.url.standardizedFileURL.path })
            if !initializedInbox {
                initializedInbox = true
                knownPaths = current
                notified = current
                // También se comprobarán los elementos preexistentes cuando el modo automático esté activo.
                if autoImportEnabled {
                    for item in candidates {
                        stability[item.url.standardizedFileURL.path] =
                            (signature: signature(for: item), firstSeen: Date())
                    }
                }
            }
            // Para avisar, exigimos dos observaciones con la misma huella, separadas
            // en el tiempo. Esto reduce avisos por copias sin finalizar.
            let now = Date()
            for item in candidates {
                let path = item.url.standardizedFileURL.path
                if !knownPaths.contains(path) {
                    knownPaths.insert(path)
                    stability[path] = (signature: signature(for: item), firstSeen: now)
                } else {
                    let fresh = signature(for: item)
                    if stability[path]?.signature != fresh {
                        stability[path] = (signature: fresh, firstSeen: now)
                    } else if let old = stability[path],
                              now.timeIntervalSince(old.firstSeen) >= 15,
                              !notified.contains(path) {
                        notified.insert(path)
                        if !autoImportEnabled { InboxNotificationRouter.shared.notify(item: item) }
                    }
                }
            }
            knownPaths.formIntersection(current)
            notified.formIntersection(current)
            stability = stability.filter { current.contains($0.key) }
            autoAttempted = autoAttempted.filter { current.contains($0.key) }
            inboxItems = candidates
            monitoringError = nil
            startNextAutomaticImportIfNeeded()
        } catch {
            inboxItems = []
            monitoringError = error.localizedDescription
            print("Error leyendo \(folder.path): \(error)")
        }
    }

    // Una sola importación en vuelo, sin alterar el asistente manual.
    // Los fallos se registran por huella para no repetir una importación defectuosa sin fin.
    private func startNextAutomaticImportIfNeeded() {
        guard autoImportEnabled, !autoInProgress else { return }
        let now = Date()
        guard let item = inboxItems.first(where: { item in
            let path = item.url.standardizedFileURL.path
            guard let observed = stability[path],
                  observed.signature == signature(for: item),
                  now.timeIntervalSince(observed.firstSeen) >= 15 else { return false }
            return autoAttempted[path] != observed.signature
        }) else { return }

        let path = item.url.standardizedFileURL.path
        let fingerprint = signature(for: item)
        autoAttempted[path] = fingerprint
        autoInProgress = true
        autoImportStatus = "Importando automáticamente: \(item.displayName)"
        let showSuccess = notifyAutoSuccess
        Task.detached(priority: .utility) { [item, path, fingerprint, showSuccess] in
            let succeeded: Bool
            let message: String
            do {
                message = try AutomaticInboxImporter.importItem(item)
                succeeded = true
            } catch {
                message = error.localizedDescription
                succeeded = false
            }
            await MainActor.run {
                self.autoInProgress = false
                if succeeded {
                    self.autoImportStatus = "\(item.displayName): \(message)"
                    if showSuccess {
                        InboxNotificationRouter.shared.notifyAutoImportSuccess(
                            name: item.displayName, detail: message
                        )
                    }
                } else {
                    self.autoImportStatus = "Importación manual necesaria para \(item.displayName): \(message)"
                    // No cambiar el estado del archivo ni reintentar mientras sea idéntico.
                    InboxNotificationRouter.shared.notifyAutoImportFailure(
                        name: item.displayName, detail: message
                    )
                }
                // Evitar que una huella obsoleta vuelva a intentarse cuando la fuente cambió.
                self.autoAttempted[path] = fingerprint
                self.scanDownloads()
            }
        }
    }

    // Atributos ligeros: no cargamos STL, ZIP ni 3MF en memoria.
    private func signature(for item: InboxItem) -> String {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey]
        let members = item.type == .folder ? item.files : [item.url]
        return members.map { url in
            let props = try? url.resourceValues(forKeys: keys)
            return "\(url.path):\(props?.fileSize ?? -1):\(props?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
        }.joined(separator: "|")
    }

    private func modelFiles(in directory: URL) -> [URL] {
        let manager = FileManager.default
        guard let enumerator = manager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var result: [URL] = []
        for case let url as URL in enumerator {
            guard validExtensions.contains(url.pathExtension.lowercased()),
                  let values = try? url.resourceValues(
                    forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
                  ),
                  values.isRegularFile == true,
                  values.isSymbolicLink != true else { continue }
            result.append(url)
        }
        return result.sorted { $0.path < $1.path }
    }

    func stopMonitoring() {
        timer?.cancel()
        timer = nil
    }
}
