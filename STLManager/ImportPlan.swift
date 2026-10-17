import Foundation

struct PlannedFile: Identifiable {
    let source: URL
    let relativePath: String
    var id: String { relativePath }
}

struct ImportPlan {
    let item: InboxItem
    let name: String
    let sourceURL: String
    let libraryURL: URL
    let stagingRoot: URL?
    let files: [PlannedFile]

    var destination: URL { libraryURL.appendingPathComponent(name, isDirectory: true) }
    var sourceFolder: URL { stagingRoot ?? (item.type == .folder ? item.url : item.url.deletingLastPathComponent()) }
}

enum ImportError: LocalizedError {
    case invalidName, invalidURL, emptyProject, destinationExists, missingBookmark
    case unsafeArchive, tooLarge, sourceChanged, unsupportedSource, securityAccess

    var errorDescription: String? {
        switch self {
        case .invalidName: return "El nombre no es válido (no admite /, : ni . o ..)."
        case .invalidURL: return "La URL debe ser http:// o https:// y contener un dominio."
        case .emptyProject: return "No hay archivos para importar."
        case .destinationExists: return "Ya existe un proyecto con este nombre; no se sobrescribirá."
        case .missingBookmark: return "Selecciona y autoriza la biblioteca en Preferencias."
        case .unsafeArchive: return "El ZIP contiene rutas o tipos de entrada no seguros."
        case .tooLarge: return "El ZIP supera los límites de seguridad establecidos."
        case .sourceChanged: return "Algún archivo cambió durante la importación."
        case .unsupportedSource: return "No se puede importar este tipo de elemento."
        case .securityAccess: return "No se pudo activar el permiso de acceso a la carpeta."
        }
    }
}
