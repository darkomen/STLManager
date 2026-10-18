import SwiftUI
import AppKit

struct ImportView: View {
    let initialItem: InboxItem

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var projectName = ""
    @State private var sourceURL = ""
    @State private var categoryText = ""
    @State private var plan: ImportPlan?
    @State private var warning: String?
    @State private var result: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                    Text(result == nil ? "Nueva importación" : "Importación completada")
                        .font(.title2).bold()

                    Label(initialItem.displayName, systemImage: initialItem.symbolName)
                        .font(.headline)
                    Text(initialItem.kindDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if result == nil {
                        Form {
                            TextField("Nombre del proyecto", text: $projectName)
                            TextField("URL de origen (opcional)", text: $sourceURL)
                            TextField("Categorías (separadas por comas, opcional)", text: $categoryText)
                                .help("Ejemplo: Escalada, Accesorios. Se guardan en .stlmanager.json")
                        }
                        .formStyle(.grouped)
                        .frame(height: 158)
                        .onChange(of: projectName) { _, _ in
                            cleanup()
                            warning = nil
                        }
.onChange(of: sourceURL) { _, _ in
                            cleanup()
                            warning = nil
                        }
                        .onChange(of: categoryText) { _, _ in
                            cleanup()
                            warning = nil
                        }
                    }

                    if let plan {
                        Text("Destino: \(plan.destination.path)")
                            .font(.caption)
                            .textSelection(.enabled)

                        Text("Vista previa del proyecto")
                            .font(.headline)

                        ScrollView {
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(previewRows(for: plan)) { row in
                                HStack(spacing: 7) {
                                    Image(systemName: row.symbol)
                                        .foregroundColor(row.isFolder ? .blue : .secondary)
                                        .frame(width: 18)
                                    Text(row.name)
                                        .font(.callout)
                                        .lineLimit(1)
                                        .help(row.path)
                                    Spacer(minLength: 0)
                                }
                                .padding(.leading, CGFloat(row.depth) * 22)
                                .frame(height: 25)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .frame(height: previewTreeHeight(for: plan))
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                        Text("\(plan.files.count) archivo(s) de origen; además se generarán README.md y .stlmanager.json.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("Tras verificar la copia, el original se enviará a Papelera.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if result == nil {
                        Text("Al preparar se analizará el contenido, sin modificar tu biblioteca.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let warning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                            .font(.caption)
                            .textSelection(.enabled)
                    }

                    if let result {
                        Label(result, systemImage: "checkmark.circle")
                            .foregroundStyle(.green)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 10)
            Divider()

            HStack {
                Spacer()
                Button(result == nil ? "Cancelar" : "Cerrar") {
                    dismiss()
                }

                if result == nil {
                    if plan == nil {
                        Button("Preparar importación") { prepare() }
                            .buttonStyle(.borderedProminent)
                            .disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("Confirmar importación") { confirm() }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 790)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            if projectName.isEmpty { projectName = initialItem.name }
        }
        .onDisappear { cleanup() }
    }

    // Altura natural del árbol, sin estirar la ventana artificialmente.
    // Cuando el contenido supera el espacio disponible, solo el árbol hace scroll.
    private func previewTreeHeight(for plan: ImportPlan) -> CGFloat {
        let rowCount = previewRows(for: plan).count
        let contentHeight = CGFloat(rowCount) * 25
            + CGFloat(max(0, rowCount - 1)) * 5
            + 4 // padding vertical del VStack interior

        // Reservamos espacio para cabecera, formulario, avisos y botones.
        let screenHeight = NSScreen.main?.visibleFrame.height ?? 800
        let maximumTreeHeight = max(100, screenHeight - 430)

        return min(contentHeight, maximumTreeHeight)
    }

    private struct PreviewRow: Identifiable {
        let path: String
        let name: String
        let depth: Int
        let isFolder: Bool
        let symbol: String
        var id: String { path }
    }

    private func previewRows(for plan: ImportPlan) -> [PreviewRow] {
        let paths = plan.files.map(\.relativePath)
        var directories = Set(["models", "sources", "images"])

        for path in paths {
            let parts = path.split(separator: "/").map(String.init)
            if parts.count > 1 {
                for count in 1..<parts.count {
                    directories.insert(parts.prefix(count).joined(separator: "/"))
                }
            }
        }

        var rows: [PreviewRow] = []

        func addFolder(_ folder: String, depth: Int) {
            rows.append(PreviewRow(path: folder + "/", name: folder.split(separator: "/").last.map(String.init)! + "/", depth: depth, isFolder: true, symbol: "folder"))

            let childFolders = directories.filter { candidate in
                let components = candidate.split(separator: "/")
                return components.dropLast().joined(separator: "/") == folder
            }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

            for child in childFolders { addFolder(child, depth: depth + 1) }

            let childFiles = paths.filter { path in
                path.split(separator: "/").dropLast().joined(separator: "/") == folder
            }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }

            for path in childFiles {
                rows.append(PreviewRow(path: path, name: String(path.split(separator: "/").last!), depth: depth + 1, isFolder: false, symbol: "doc"))
            }
        }

        let order = ["models", "sources", "images", "others"]
        for root in order where directories.contains(root) {
            addFolder(root, depth: 0)
        }
        // Mostrar también categorías adicionales presentes en el plan.
        let extraRoots = directories.filter { !$0.contains("/") && !order.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        for root in extraRoots {
            addFolder(root, depth: 0)
        }

        rows.append(PreviewRow(path: "README.md", name: "README.md", depth: 0, isFolder: false, symbol: "doc.text"))
        rows.append(PreviewRow(path: ".stlmanager.json", name: ".stlmanager.json", depth: 0, isFolder: false, symbol: "curlybraces"))
        return rows
    }

    private var parsedCategories: [String] {
        var result: [String] = []
        var seen = Set<String>()
        for raw in categoryText.split(separator: ",") {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty && seen.insert(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted {
                result.append(name)
            }
        }
        return result
    }

    private func scopedLibrary() throws -> URL {
        guard let library = try FolderAccess.resolveBookmark(key: "libraryBookmark") else {
            throw ImportError.missingBookmark
        }
        guard library.startAccessingSecurityScopedResource() else {
            throw ImportError.securityAccess
        }
        return library
    }

    private func prepare() {
        warning = nil
        cleanup()
        do {
            let library = try scopedLibrary()
            defer { library.stopAccessingSecurityScopedResource() }
            let inbox = try FolderAccess.resolveBookmark(key: "inboxBookmark")
            guard inbox?.startAccessingSecurityScopedResource() == true else {
                throw ImportError.securityAccess
            }
            defer { inbox?.stopAccessingSecurityScopedResource() }
            let staging = initialItem.type == .archive
                ? try ZipExtractor.unpack(initialItem.url) : nil
            do {
                plan = try ImportPlanner.prepare(
                    item: initialItem,
                    name: projectName,
                    sourceURL: sourceURL,
                    library: library,
                    staging: staging,
                    categories: parsedCategories
                )
            } catch {
                if let staging { try? FileManager.default.removeItem(at: staging) }
                throw error
            }
        } catch {
            warning = error.localizedDescription
        }
    }

    private func confirm() {
        guard let plan else { return }
        warning = nil
        do {
            let library = try scopedLibrary()
            defer { library.stopAccessingSecurityScopedResource() }
            let inbox = try FolderAccess.resolveBookmark(key: "inboxBookmark")
            guard inbox?.startAccessingSecurityScopedResource() == true else {
                throw ImportError.securityAccess
            }
            defer { inbox?.stopAccessingSecurityScopedResource() }
            result = try ProjectImporter.execute(plan)
            appState.scanDownloads()
            cleanup()
        } catch {
            warning = error.localizedDescription
        }
    }

    private func cleanup() {
        if let staging = plan?.stagingRoot {
            try? FileManager.default.removeItem(at: staging)
        }
        plan = nil
    }
}

