import Foundation

/// Reutiliza el planificador y el importador manual. Nunca reemplaza proyectos existentes.
nonisolated enum AutomaticInboxImporter {
    nonisolated static func importItem(_ item: InboxItem) throws -> String {
        guard let inbox = try FolderAccess.resolveBookmark(key: "inboxBookmark"),
              let library = try FolderAccess.resolveBookmark(key: "libraryBookmark") else {
            throw ImportError.missingBookmark
        }
        guard inbox.startAccessingSecurityScopedResource() else { throw ImportError.securityAccess }
        defer { inbox.stopAccessingSecurityScopedResource() }
        guard library.startAccessingSecurityScopedResource() else { throw ImportError.securityAccess }
        defer { library.stopAccessingSecurityScopedResource() }

        // No utilizar nunca nombres deducidos alternativos para resolver conflictos.
        // Un nombre repetido se deja pendiente para intervención manual.
        let name = item.name
        let fm = FileManager.default
        guard fm.fileExists(atPath: item.url.path) else { throw ImportError.emptyProject }
        var staging: URL?
        defer { if let staging { try? fm.removeItem(at: staging) } }
        if item.type == .archive {
            staging = try ZipExtractor.unpack(item.url)
        }
        let plan = try ImportPlanner.prepare(
            item: item, name: name, sourceURL: "", library: library, staging: staging
        )
        return try ProjectImporter.execute(plan)
    }
}
