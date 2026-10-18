import Foundation

nonisolated struct ImportPlanner {
    static let binary: Set<String> = ["stl", "3mf", "step", "stp", "obj", "amf", "ply"]
    static let sources: Set<String> = ["f3d", "scad", "fcstd", "blend", "ipt", "sldprt", "sldasm"]
    static let images: Set<String> = ["png", "jpg", "jpeg", "webp", "gif", "heic"]

    nonisolated static func validate(name: String, sourceURL: String, library: URL) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != ".", clean != "..",
              !clean.contains("/"), !clean.contains(":"), !clean.contains("\\"),
              !clean.hasPrefix("."), !clean.contains("\0") else { throw ImportError.invalidName }
        let urlText = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlText.isEmpty {
            guard let url = URLComponents(string: urlText),
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let host = url.host, host.contains(".") else { throw ImportError.invalidURL }
        }
        let dest = library.appendingPathComponent(clean, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: dest.path) else { throw ImportError.destinationExists }
        return clean
    }

    nonisolated static func collect(_ item: InboxItem, stagingRoot: URL? = nil) throws -> [(URL, String)] {
        let base: URL
        if let stagingRoot { base = stagingRoot }
        else if item.type == .folder { base = item.url }
        else { base = item.url.deletingLastPathComponent() }

        if item.type == .singleFile { return [(item.url, item.url.lastPathComponent)] }
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else {
            throw ImportError.emptyProject
        }
        var result: [(URL, String)] = []
        for case let file as URL in enumerator {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else { throw ImportError.unsafeArchive }
            guard values.isRegularFile == true else { continue }
            let prefix = base.standardizedFileURL.path + "/"
            guard file.standardizedFileURL.path.hasPrefix(prefix) else { throw ImportError.unsafeArchive }
            result.append((file, String(file.standardizedFileURL.path.dropFirst(prefix.count))))
        }
        return result.sorted { $0.1 < $1.1 }
    }

    nonisolated static func destinationPath(for relative: String) throws -> String {
        let parts = relative.split(separator: "/").map(String.init)
        guard !parts.isEmpty, parts.allSatisfy({ $0 != "." && $0 != ".." && !$0.isEmpty }) else { throw ImportError.unsafeArchive }
        let name = parts.last!
        let ext = URL(fileURLWithPath: name).pathExtension.lowercased()
        let category: String = binary.contains(ext) ? "models" : (sources.contains(ext) ? "sources" : (images.contains(ext) ? "images" : "others"))
        // Preservamos subdirectorios para no colisionar versiones con el mismo nombre.
        return ([category] + parts).joined(separator: "/")
    }

    nonisolated static func prepare(item: InboxItem, name: String, sourceURL: String, library: URL, staging: URL? = nil, categories: [String] = []) throws -> ImportPlan {
        let clean = try validate(name: name, sourceURL: sourceURL, library: library)
        let entries = try collect(item, stagingRoot: staging)
        guard !entries.isEmpty else { throw ImportError.emptyProject }
        var paths = Set<String>()
        let files = try entries.map { url, relative -> PlannedFile in
            let dest = try destinationPath(for: relative)
            guard paths.insert(dest.lowercased()).inserted else { throw ImportError.unsafeArchive }
            return PlannedFile(source: url, relativePath: dest)
        }
        return ImportPlan(item: item, name: clean, sourceURL: sourceURL.trimmingCharacters(in: .whitespacesAndNewlines), categories: categories, libraryURL: library, stagingRoot: staging, files: files)
    }
}
