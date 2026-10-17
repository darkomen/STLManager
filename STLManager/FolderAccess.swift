import Foundation

enum FolderAccess {
    static func saveBookmark(for url: URL, key: String) throws {
        let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: key)
    }

    static func resolveBookmark(key: String) throws -> URL? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale { try saveBookmark(for: url, key: key) }
        return url
    }
}
