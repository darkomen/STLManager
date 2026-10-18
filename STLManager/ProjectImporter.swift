import Foundation
import CryptoKit

nonisolated struct ProjectImporter {
    nonisolated static func digest(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let data = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Copiamos, verificamos, publicamos y solo entonces enviamos el origen a la Papelera.
    /// Si la Papelera falla, el proyecto sigue importado y conservamos el original.
    nonisolated static func execute(_ plan: ImportPlan) throws -> String {
        let fm = FileManager.default
        let working = plan.libraryURL.appendingPathComponent(".stlmanager-work-\(UUID().uuidString)", isDirectory: true)
        let dest = plan.destination
        guard !fm.fileExists(atPath: dest.path) else { throw ImportError.destinationExists }
        try fm.createDirectory(at: working, withIntermediateDirectories: false)
        var published = false
        defer { if !published { try? fm.removeItem(at: working) } }
        for folder in ["models", "sources", "images"] {
            try fm.createDirectory(at: working.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        var hashes: [[String: String]] = []
        for file in plan.files {
            let target = working.appendingPathComponent(file.relativePath)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let before = try digest(file.source)
            try fm.copyItem(at: file.source, to: target)
            guard try digest(target) == before, try digest(file.source) == before else { throw ImportError.sourceChanged }
            hashes.append(["path": file.relativePath, "sha256": before])
        }
        let date = ISO8601DateFormatter().string(from: Date())
        let readme = """
        # \(plan.name)

        ## Información
        - URL de origen: \(plan.sourceURL.isEmpty ? "Pendiente de indicar" : plan.sourceURL)
        - Fecha de importación: \(date)

        ## Archivos
        \(plan.files.map { "- `\($0.relativePath)`" }.joined(separator: "\n"))

        ## Notas personales

        """
        try readme.write(to: working.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        let metadata: [String: Any] = [
            "schema_version": 1,
            "id": UUID().uuidString,
            "title": plan.name,
            "source_url": plan.sourceURL,
            "categories": plan.categories,
            "import_date": date,
            "files": hashes
        ]
        let json = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: working.appendingPathComponent(".stlmanager.json"), options: .atomic)
        guard !fm.fileExists(atPath: dest.path) else { throw ImportError.destinationExists }
        try fm.moveItem(at: working, to: dest)
        published = true
        do {
            var trashed: NSURL?
            try fm.trashItem(at: plan.item.url, resultingItemURL: &trashed)
            return "Proyecto importado. Original enviado a Papelera."
        } catch {
            return "Proyecto importado, pero no se pudo enviar el original a Papelera: \(error.localizedDescription)"
        }
    }
}
