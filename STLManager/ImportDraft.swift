
import Foundation

struct ImportDraft {
    var projectName: String = ""
    var sourceURL: String = ""
    var selectedFiles: Set<URL> = []

    var isValid: Bool {
        !projectName.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty && !selectedFiles.isEmpty
    }
}
