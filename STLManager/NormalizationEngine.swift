import Foundation
import CryptoKit

struct NormalizationFile: Identifiable, Sendable {
    let source: String
    let target: String
    var id: String { source }
}

struct NormalizationProposal: Identifiable, Sendable {
    let projectURL: URL
    let moves: [NormalizationFile]
    let needsReadme: Bool
    let needsMetadata: Bool
    let warnings: [String]
    var id: URL { projectURL }
    nonisolated var name: String { projectURL.lastPathComponent }
    nonisolated var needsChanges: Bool { !moves.isEmpty || needsReadme || needsMetadata }
}

enum NormalizationFailure: LocalizedError {
    case invalidLibrary, unsafeFile(String), nameConflict(String), changedProject, documentationTooLarge(String)
    var errorDescription: String? {
        switch self {
        case .invalidLibrary: return "Selecciona una biblioteca válida en Preferencias."
        case .unsafeFile(let f): return "Archivo no seguro o enlace simbólico: \(f)"
        case .nameConflict(let f): return "Colisión de nombres: \(f)"
        case .changedProject: return "El proyecto cambió desde el análisis. Repite el análisis antes de continuar."
        case .documentationTooLarge(let f): return "Documento demasiado grande para normalizar automáticamente: \(f)"
        }
    }
}

struct NormalizationEngine {
    private nonisolated static var fm: FileManager { FileManager.default }
    nonisolated static let reserved: Set<String> = ["_inbox", ".stlmanager", ".stlmanager-backups", ".stlmanager-work"]

    nonisolated static func listProjects(in library: URL) throws -> [URL] {
        guard (try? library.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { throw NormalizationFailure.invalidLibrary }
        return try fm.contentsOfDirectory(at: library, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            .filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return values?.isDirectory == true && values?.isSymbolicLink != true && !reserved.contains(url.lastPathComponent.lowercased()) && !url.lastPathComponent.hasPrefix(".stlmanager-")
            }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // Nombres canónicos de las carpetas para proyectos nuevos y existentes.
    private nonisolated static let canonical = ["models", "sources", "images", "others"]
    // Reconocer también carpetas históricas en castellano, con y sin tildes.
    private nonisolated static let alias: [String: String] = [
        "binarios": "models", "files": "models", "models": "models", "stl": "models",
        "fuentes": "sources", "sources": "sources", "source": "sources",
        "imágenes": "images", "imagenes": "images", "images": "images", "pictures": "images",
        "otros": "others", "other": "others", "others": "others", "docs": "others"
    ]

    nonisolated static func proposedTarget(for relative: String) -> String {
        let parts = relative.split(separator: "/").map(String.init)
        guard let filename = parts.last else { return relative }
        let lower = filename.lowercased()
        if parts.count == 1 && (lower == "readme.md" || lower == ".stlmanager.json") { return relative }
        let ext = URL(fileURLWithPath: filename).pathExtension.lowercased()
        let category: String
        if ["stl", "3mf", "step", "stp", "obj", "amf", "ply"].contains(ext) { category = "models" }
        else if ["f3d", "scad", "fcstd", "blend", "ipt", "sldprt", "sldasm"].contains(ext) { category = "sources" }
        else if ["png", "jpg", "jpeg", "webp", "gif", "heic"].contains(ext) { category = "images" }
        else { category = "others" }
        var sub = Array(parts.dropLast())
        if let first = sub.first, first.lowercased() == category.lowercased() || alias[first.lowercased()] == category {
            sub.removeFirst()
        }
        return ([category] + sub + [filename]).joined(separator: "/")
    }

    nonisolated static func scan(_ project: URL) throws -> NormalizationProposal {
        // A protected folder is NEVER enumerated, hashed or rewritten.
        let mode = try FolderRules.backgroundMode(for: project, in: project.deletingLastPathComponent())
        if mode != .managed {
            return NormalizationProposal(projectURL: project, moves: [], needsReadme: false,
                needsMetadata: false, warnings: [mode == .excluded
                    ? "Carpeta excluida por configuración"
                    : "Colección protegida: solo lectura"])
        }
        let files = try enumerate(project)
        let paths = Set(files.map(\.relative))
        let hasReadme = paths.contains("README.md")
        let hasJSON = paths.contains(".stlmanager.json")
        var used = Set<String>()
        var moves: [NormalizationFile] = []
        var warnings: [String] = []
        // Unclassified large collections must be explicitly reviewed before writes.
        // Only reads file attributes; no content is loaded or hashed during scan.
        var totalBytes: Int64 = 0
        for file in files {
            let size = try file.url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            totalBytes += Int64(size)
            if totalBytes > 2_000_000_000 {
                warnings.append("Carpeta superior a 2 GB: revísala y márcala como colección protegida si corresponde")
                break
            }
        }
        for file in files {
            let target = proposedTarget(for: file.relative)
            if !used.insert(target.lowercased()).inserted { warnings.append("Colisión: \(target)") }
            if target != file.relative { moves.append(NormalizationFile(source: file.relative, target: target)) }
        }
        // Regenerar solo cuando faltan metadatos o es preciso cambiar la organización.
        return NormalizationProposal(projectURL: project, moves: moves, needsReadme: !hasReadme || !moves.isEmpty || !hasJSON,
                                     needsMetadata: !hasJSON || !moves.isEmpty, warnings: warnings)
    }

    private struct Found { let url: URL; let relative: String }
    private nonisolated static func enumerate(_ root: URL) throws -> [Found] {
        // NO usar .skipsHiddenFiles: necesitamos localizar .stlmanager.json.
        // Se ignoran otros ficheros ocultos y directorios de herramientas.
        guard let en = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else { throw NormalizationFailure.invalidLibrary }
        var found: [Found] = []
        let prefix = root.standardizedFileURL.path + "/"
        for case let url as URL in en {
            let props = try url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
            let relative = String(url.standardizedFileURL.path.dropFirst(prefix.count))
            if props.isSymbolicLink == true { throw NormalizationFailure.unsafeFile(relative) }
            let name = url.lastPathComponent
            if name.hasPrefix(".") && name != ".stlmanager.json" {
                if props.isDirectory == true { en.skipDescendants() }
                continue
            }
            if props.isRegularFile == true { found.append(Found(url: url, relative: relative)) }
            // Evitar una explosión de objetos ante un proyecto patológico.
            if found.count > 100_000 { throw NormalizationFailure.documentationTooLarge("Más de 100 000 archivos en un proyecto") }
        }
        return found.sorted { $0.relative < $1.relative }
    }

    // Normalización EN EL MISMO DIRECTORIO. No clona, copia ni respalda el proyecto.
    // Los movimientos completados se revierten si una operación posterior falla.
    nonisolated static func normalize(_ proposal: NormalizationProposal, in library: URL, onStep: @Sendable (String) -> Void = { _ in }) throws -> String {
        // Recheck at execution time: a rule can change after the preview was built.
        guard try FolderRules.backgroundMode(for: proposal.projectURL, in: library) == .managed else {
            throw NormalizationFailure.invalidLibrary
        }
        let fresh = try scan(proposal.projectURL)
        guard fresh.moves.map(\.source) == proposal.moves.map(\.source),
              fresh.moves.map(\.target) == proposal.moves.map(\.target),
              fresh.needsReadme == proposal.needsReadme,
              fresh.needsMetadata == proposal.needsMetadata else {
            throw NormalizationFailure.changedProject
        }
        guard fresh.warnings.isEmpty else {
            throw NormalizationFailure.nameConflict(fresh.warnings.joined(separator: ", "))
        }
        guard fresh.needsChanges else { return "Sin cambios: \(fresh.name)" }

        let root = fresh.projectURL
        let libraryPath = library.standardizedFileURL.path
        guard root.deletingLastPathComponent().standardizedFileURL.path == libraryPath,
              !reserved.contains(root.lastPathComponent.lowercased()) else {
            throw NormalizationFailure.invalidLibrary
        }

        onStep("Inventariando archivos")
        let existingFiles = try enumerate(root)
        let currentReadmeURL = root.appendingPathComponent("README.md")
        let currentMetadataURL = root.appendingPathComponent(".stlmanager.json")
        let previousReadme = try readTextIfSmall(currentReadmeURL, maxBytes: 2 * 1024 * 1024)
        var metadata: [String: Any] = [:]
        if let data = try readDataIfSmall(currentMetadataURL, maxBytes: 8 * 1024 * 1024),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            metadata = dict
        }

        // Detectar destinos ocupados ANTES de mover un solo byte.
        for move in fresh.moves {
            let destination = root.appendingPathComponent(move.target)
            if fm.fileExists(atPath: destination.path) {
                throw NormalizationFailure.nameConflict(move.target)
            }
        }

        // Calcular la información y los hashes a partir de los originales, antes de mover.
        // Esto permite detectar problemas de lectura antes de modificar el proyecto.
        let targetsBySource = Dictionary(uniqueKeysWithValues: fresh.moves.map { ($0.source, $0.target) })
        let finalFiles: [(path: String, url: URL)] = existingFiles.compactMap { file in
            if file.relative == "README.md" || file.relative == ".stlmanager.json" { return nil }
            return (targetsBySource[file.relative] ?? file.relative, file.url)
        }.sorted { $0.path < $1.path }

        let existingURL = (metadata["source_url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let candidates = extractURLs((previousReadme ?? "") + "\n" + (existingURL ?? ""))
        let sourceURL = existingURL ?? candidates.first

        var inventory: [[String: String]] = []
        inventory.reserveCapacity(finalFiles.count)
        for (index, file) in finalFiles.enumerated() {
            if index % 20 == 0 || index + 1 == finalFiles.count {
                onStep("SHA-256 · \(index + 1)/\(finalFiles.count) · \(file.path)")
            }
            inventory.append(["path": file.path, "sha256": try ProjectImporter.digest(file.url)])
        }
        let readmeText: String? = fresh.needsReadme ? {
            let listing = finalFiles.map { "- `\($0.path)`" }.joined(separator: "\n")
            var result = "# \(fresh.name)\n\n## Origen\n- URL: \(sourceURL ?? "No disponible")\n\n## Archivos\n\(listing)\n\n## Notas personales\n\n"
            // Evita incluir un README normalizado dentro de sí mismo en cada ejecución.
            let legacyMarker = "## Documentación anterior (conservada íntegramente)"
            if let previousReadme, !previousReadme.isEmpty {
                if let range = previousReadme.range(of: legacyMarker) {
                    result += String(previousReadme[range.lowerBound...]) + "\n"
                } else {
                    result += legacyMarker + "\n\n---\n\n" + previousReadme + "\n"
                }
            }
            return result
        }() : nil

        let metadataData: Data? = try {
            guard fresh.needsMetadata else { return nil }
            metadata["schema_version"] = 1
            metadata["id"] = (metadata["id"] as? String) ?? UUID().uuidString
            metadata["title"] = (metadata["title"] as? String) ?? fresh.name
            metadata["source_url"] = sourceURL.map { $0 as Any } ?? NSNull()
            metadata["categories"] = metadata["categories"] ?? [String]()
            metadata["files"] = inventory
            return try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
        }()

        // No hay copia del proyecto. Si falla un movimiento, intentamos revertir
        // los realizados. No prometemos una transacción perfecta ante cortes de luz.
        var completed: [NormalizationFile] = []
        do {
            for move in fresh.moves {
                onStep("Moviendo · \(move.source) → \(move.target)")
                let from = root.appendingPathComponent(move.source)
                let to = root.appendingPathComponent(move.target)
                try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fm.moveItem(at: from, to: to)
                completed.append(move)
            }
            for name in ["models", "sources", "images"] {
                try fm.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
            }
            if let readmeText {
                onStep("Actualizando README.md")
                try readmeText.write(to: currentReadmeURL, atomically: true, encoding: .utf8)
            }
            if let metadataData {
                onStep("Actualizando .stlmanager.json")
                try metadataData.write(to: currentMetadataURL, options: .atomic)
            }
            // Limpiar exclusivamente directorios vacíos, de abajo arriba.
            // No se elimina nada que aún contenga archivos o subcarpetas.
            do {
                onStep("Limpiando carpetas vacías")
                let removed = try removeEmptyDirectories(in: root)
                return "Normalizado: \(fresh.name) · \(fresh.moves.count) archivo(s) movido(s) · \(removed) carpeta(s) vacía(s) eliminada(s)"
            } catch {
                return "Normalizado: \(fresh.name) · Limpieza parcial de carpetas: \(error.localizedDescription)"
            }
        } catch {
            for move in completed.reversed() {
                let from = root.appendingPathComponent(move.target)
                let to = root.appendingPathComponent(move.source)
                if fm.fileExists(atPath: from.path) && !fm.fileExists(atPath: to.path) {
                    try? fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try? fm.moveItem(at: from, to: to)
                }
            }
            throw error
        }
    }

    // Recorre carpetas de más profundidad a menos profundidad.
    // Importante: nunca elimina la raíz del proyecto ni archivos.
    // Si una carpeta no está vacía, se conserva sin modificar.
    private nonisolated static func removeEmptyDirectories(in root: URL) throws -> Int {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys,
                                             options: [.skipsHiddenFiles]) else {
            return 0
        }
        var folders: [URL] = []
        for case let candidate as URL in enumerator {
            let values = try candidate.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true && values.isSymbolicLink != true {
                folders.append(candidate)
            }
        }
        folders.sort { $0.pathComponents.count > $1.pathComponents.count }
        var removed = 0
        for folder in folders {
            // Las carpetas estándar deben existir aunque estén vacías.
            if folder.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL &&
                canonical.contains(folder.lastPathComponent.lowercased()) {
                continue
            }
            // contentsOfDirectory sin skipsHiddenFiles: protege también archivos ocultos.
            let contents = try fm.contentsOfDirectory(at: folder,
                includingPropertiesForKeys: nil, options: [])
            if contents.isEmpty {
                try fm.removeItem(at: folder)
                removed += 1
            }
        }
        return removed
    }

    private nonisolated static func readDataIfSmall(_ url: URL, maxBytes: Int) throws -> Data? {
        guard fm.fileExists(atPath: url.path) else { return nil }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maxBytes else { throw NormalizationFailure.documentationTooLarge(url.lastPathComponent) }
        return try Data(contentsOf: url)
    }

    private nonisolated static func readTextIfSmall(_ url: URL, maxBytes: Int) throws -> String? {
        guard let data = try readDataIfSmall(url, maxBytes: maxBytes) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated static func extractURLs(_ s: String) -> [String] {
        let regex = try! NSRegularExpression(pattern: "https?://[^\\s<>\\\"'`]+", options: [.caseInsensitive])
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        var seen = Set<String>()
        return regex.matches(in: s, range: range).compactMap { match in
            guard let r = Range(match.range, in: s) else { return nil }
            let value = String(s[r]).trimmingCharacters(in: CharacterSet(charactersIn: ").,;"))
            guard URLComponents(string: value)?.host != nil, seen.insert(value).inserted else { return nil }
            return value
        }
    }
}
