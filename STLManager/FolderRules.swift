import Foundation

// Shared library rules: stored alongside the library, never inside purchased collections.
enum FolderMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case managed
    case readOnlyCollection
    case excluded

    var id: String { rawValue }
    var title: String {
        switch self {
        case .managed: return "Proyecto gestionado"
        case .readOnlyCollection: return "Colección de solo lectura"
        case .excluded: return "Excluir carpeta"
        }
    }
}

struct FolderRule: Codable, Equatable, Sendable {
    let path: String // Relative to the root of the library.
    let mode: FolderMode
}

enum FolderRuleError: LocalizedError {
    case invalidPath, unsafeLink, damagedConfiguration, unsupportedVersion, invalidRule(String)
    var errorDescription: String? {
        switch self {
        case .invalidPath: return "La carpeta debe estar dentro de la biblioteca."
        case .unsafeLink: return "Por seguridad, no se permiten enlaces simbólicos en la ruta."
        case .damagedConfiguration: return "No se pudo leer .stlmanager/library.json. No se normalizará nada hasta corregirlo."
        case .unsupportedVersion: return "La versión de .stlmanager/library.json no es compatible."
        case .invalidRule(let path): return "Regla de carpeta no válida: \(path)"
        }
    }
}

@MainActor
final class FolderRules {
    static let shared = FolderRules()
    private init() {}

    private struct LibraryConfiguration: Codable {
        var schema_version: Int = 1
        var folder_rules: [FolderRule] = []
    }

    // Old v0.5.5 format, used *only* to migrate an existing configuration.
    private struct LegacyConfiguration: Codable {
        let libraryPath: String
        let rules: [FolderRule]
    }

    private let legacyKey = "stlmanager.folderRules.v1"
    private let fm = FileManager.default

    private func fileURL(in library: URL) -> URL {
        library.appendingPathComponent(".stlmanager", isDirectory: true)
            .appendingPathComponent("library.json")
    }

    private func validate(_ config: LibraryConfiguration) throws {
        guard config.schema_version == 1 else { throw FolderRuleError.unsupportedVersion }
        var paths = Set<String>()
        for rule in config.folder_rules {
            let parts = rule.path.split(separator: "/", omittingEmptySubsequences: false)
            guard !parts.isEmpty,
                  parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  !rule.path.hasPrefix("/"),
                  paths.insert(rule.path).inserted else {
                throw FolderRuleError.invalidRule(rule.path)
            }
        }
    }

    private func verifyFolder(_ directory: URL) throws {
        // The configuration directory cannot be a symbolic link.
        var isDirectory: ObjCBool = false
        if fm.fileExists(atPath: directory.path, isDirectory: &isDirectory) {
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true, isDirectory.boolValue else { throw FolderRuleError.unsafeLink }
        }
    }

    private func save(_ config: LibraryConfiguration, in library: URL) throws {
        try validate(config)
        let dir = library.appendingPathComponent(".stlmanager", isDirectory: true)
        try verifyFolder(dir)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = fileURL(in: library)
        if fm.fileExists(atPath: destination.path) {
            let values = try destination.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw FolderRuleError.unsafeLink }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: destination, options: .atomic)
    }

    private func load(for library: URL) throws -> LibraryConfiguration {
        let dir = library.appendingPathComponent(".stlmanager", isDirectory: true)
        try verifyFolder(dir)
        let url = fileURL(in: library)
        if fm.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw FolderRuleError.unsafeLink }
            // Invalid JSON is NEVER treated as an unprotected library.
            let data = try Data(contentsOf: url)
            guard let config = try? JSONDecoder().decode(LibraryConfiguration.self, from: data) else {
                throw FolderRuleError.damagedConfiguration
            }
            try validate(config)
            return config
        }

        // One-time migration. The old settings are left untouched in case the user
        // needs to roll back the application version.
        var config = LibraryConfiguration()
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let legacy = try? JSONDecoder().decode(LegacyConfiguration.self, from: data),
           legacy.libraryPath == library.standardizedFileURL.path {
            config.folder_rules = legacy.rules
        }
        try save(config, in: library)
        return config
    }

    func rules(for library: URL) throws -> [FolderRule] {
        try load(for: library).folder_rules
    }

    // Check path components, not raw prefixes ("foo" must not match "foobar").
    func mode(for folder: URL, in library: URL) throws -> FolderMode {
        let root = library.standardizedFileURL.pathComponents
        let path = folder.standardizedFileURL.pathComponents
        guard path.starts(with: root), path.count > root.count else { throw FolderRuleError.invalidPath }
        let relative = Array(path.dropFirst(root.count))
        var result: (depth: Int, mode: FolderMode)?
        for rule in try rules(for: library) {
            let parts = rule.path.split(separator: "/").map(String.init)
            if relative.starts(with: parts), result == nil || parts.count > result!.depth {
                result = (parts.count, rule.mode)
            }
        }
        return result?.mode ?? .managed
    }

    func setMode(_ mode: FolderMode, for folder: URL, in library: URL) throws {
        let root = library.standardizedFileURL.pathComponents
        let path = folder.standardizedFileURL.pathComponents
        guard path.starts(with: root), path.count > root.count else { throw FolderRuleError.invalidPath }
        let parts = Array(path.dropFirst(root.count))
        var cursor = library.standardizedFileURL
        for part in parts {
            cursor.appendPathComponent(part)
            let values = try cursor.resourceValues(forKeys: [.isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw FolderRuleError.unsafeLink }
        }
        let relative = parts.joined(separator: "/")
        var config = try load(for: library)
        config.folder_rules.removeAll { $0.path == relative }
        // Store explicit "managed" only when needed to override an inherited rule.
        let ancestorProtected = config.folder_rules.contains { rule in
            rule.mode != .managed && relative.hasPrefix(rule.path + "/")
        }
        if mode != .managed || ancestorProtected {
            config.folder_rules.append(FolderRule(path: relative, mode: mode))
        }
        config.folder_rules.sort { $0.path < $1.path }
        try save(config, in: library)
    }
}


// Lectura segura desde tareas de fondo. Nunca crea ni cambia library.json.
// Si no está disponible, NO asumimos que una carpeta está desprotegida.
extension FolderRules {
    nonisolated static func backgroundMode(for folder: URL, in library: URL) throws -> FolderMode {
        let root = library.standardizedFileURL.pathComponents
        let parts = folder.standardizedFileURL.pathComponents
        guard parts.starts(with: root), parts.count > root.count else { throw FolderRuleError.invalidPath }
        let configDir = library.appendingPathComponent(".stlmanager", isDirectory: true)
        let file = configDir.appendingPathComponent("library.json")
        let dirAttributes = try configDir.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        guard dirAttributes.isDirectory == true, dirAttributes.isSymbolicLink != true else { throw FolderRuleError.damagedConfiguration }
        let attrs = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard attrs.isSymbolicLink != true, attrs.isRegularFile == true,
              (attrs.fileSize ?? Int.max) <= 1024 * 1024 else { throw FolderRuleError.damagedConfiguration }
        let data = try Data(contentsOf: file)
        struct DiskRules: Decodable {
            let schema_version: Int
            let folder_rules: [FolderRule]
        }
        guard let decoded = try? JSONDecoder().decode(DiskRules.self, from: data) else {
            throw FolderRuleError.damagedConfiguration
        }
        guard decoded.schema_version == 1 else { throw FolderRuleError.unsupportedVersion }
        var seen = Set<String>()
        var chosen: (depth: Int, mode: FolderMode)?
        let relative = Array(parts.dropFirst(root.count))
        for rule in decoded.folder_rules {
            let sections = rule.path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            guard !sections.isEmpty, sections.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }),
                  !rule.path.hasPrefix("/"), seen.insert(rule.path).inserted else {
                throw FolderRuleError.invalidRule(rule.path)
            }
            if relative.starts(with: sections), sections.count > (chosen?.depth ?? 0) {
                chosen = (sections.count, rule.mode)
            }
        }
        return chosen?.mode ?? .managed
    }
}
