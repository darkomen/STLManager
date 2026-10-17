import Foundation

enum InboxItemType {
    case singleFile
    case folder
    case archive
}

struct InboxItem: Identifiable {
    let url: URL
    let type: InboxItemType
    /// Archivos de modelo encontrados. Para ZIP, es el propio ZIP
    /// hasta que implementemos un analizador de archivos comprimidos.
    let files: [URL]

    var id: URL { url }

    var name: String {
        type == .folder ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }

    var fileCount: Int { files.count }

    var displayName: String { url.lastPathComponent }

    var kindDescription: String {
        switch type {
        case .singleFile: return url.pathExtension.uppercased()
        case .folder: return "Carpeta · \(fileCount) archivo(s)"
        case .archive: return "ZIP · sin descomprimir"
        }
    }

    var symbolName: String {
        switch type {
        case .singleFile: return "cube.transparent"
        case .folder: return "folder.fill"
        case .archive: return "doc.zipper"
        }
    }
}
