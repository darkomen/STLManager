import Foundation
import ZIPFoundation

struct ZipExtractor {
    // Necesita el paquete Swift https://github.com/weichsel/ZIPFoundation
    static func unpack(_ zipURL: URL) throws -> URL {
        let fm = FileManager.default
        let staging = fm.temporaryDirectory.appendingPathComponent("stlmanager-zip-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let archive = try Archive(
                url: zipURL,
                accessMode: .read
            )
            var total: UInt64 = 0
            var count = 0
            for entry in archive {
                count += 1
                guard count <= 3000 else { throw ImportError.tooLarge }
                guard entry.type == .file || entry.type == .directory else { throw ImportError.unsafeArchive }
                let path = entry.path.replacingOccurrences(of: "\\", with: "/")
                let components = path.split(separator: "/", omittingEmptySubsequences: false)
                guard !path.hasPrefix("/"), !path.contains(":"),
                      !components.contains(where: { $0 == ".." || $0 == "." }),
                      !components.isEmpty else { throw ImportError.unsafeArchive }
                total += UInt64(entry.uncompressedSize)
                guard total <= 2_000_000_000 else { throw ImportError.tooLarge }
                let target = staging.appendingPathComponent(path)
                guard target.standardizedFileURL.path.hasPrefix(staging.path + "/") else { throw ImportError.unsafeArchive }
                if entry.type == .directory {
                    try fm.createDirectory(at: target, withIntermediateDirectories: true)
                } else {
                    try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    _ = try archive.extract(
                        entry,
                        to: target
                    )
                }
            }
            return staging
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }
}
