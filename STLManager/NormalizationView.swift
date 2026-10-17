import SwiftUI

struct NormalizationView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("libraryFolder") private var libraryFolder = ""
    @StateObject private var progress = NormalizationProgressModel()
    @State private var showProgress = false
    @State private var proposals: [NormalizationProposal] = []
    @State private var selected: Set<URL> = []
    @State private var folderModes: [URL: FolderMode] = [:]
    @State private var result: [String] = []
    @State private var errorMessage: String?
    @State private var busy = false
    @State private var showReport = false
    @State private var reportSuccesses = 0
    @State private var reportFailures = 0
    @State private var reportRequested = 0
    @State private var reportRows: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading) {
                    Text("Normalizar biblioteca").font(.title2.bold())
                    Text("Analiza primero; se modificarán los proyectos directamente, sin respaldos automáticos.")
                        .foregroundStyle(.secondary).font(.caption)
                }
                Spacer()
                Button("Analizar") { analyze() }.disabled(busy)
            }
            Text(libraryFolder.isEmpty ? "Selecciona la biblioteca en Preferencias" : libraryFolder)
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)

            HStack(spacing: 10) {
                Button("Seleccionar todos") {
                    selected = Set(proposals.filter {
                        $0.needsChanges && $0.warnings.isEmpty && folderModes[$0.id] == .managed
                    }.map(\.id))
                }
                .disabled(busy || !proposals.contains(where: { $0.needsChanges && $0.warnings.isEmpty && folderModes[$0.id] == .managed }))

                Button("Deseleccionar todos") {
                    selected.removeAll()
                }
                .disabled(busy || selected.isEmpty)

                Spacer()
                Text("Reglas compartidas en .stlmanager/library.json · Solo proyectos sin conflictos")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            List(proposals) { p in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Toggle(isOn: Binding(get: { selected.contains(p.id) }, set: { v in
                            if v { selected.insert(p.id) } else { selected.remove(p.id) }
                        })) {
                            Text(p.name).fontWeight(.medium)
                        }
                        .disabled(!p.needsChanges || !p.warnings.isEmpty || busy || folderModes[p.id] != .managed)
                        Spacer()
                        Picker("Tipo de carpeta", selection: Binding(
                            get: { folderModes[p.id] ?? .managed },
                            set: { setFolderMode($0, for: p) }
                        )) {
                            ForEach(FolderMode.allCases) { mode in
                                Text(mode.title).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                        .disabled(busy)

                        Text(!p.warnings.isEmpty ? "Revisar" : (p.needsChanges ? "Cambios" : "Correcto"))
                            .font(.caption).foregroundStyle(p.warnings.isEmpty ? Color.secondary : Color.orange)
                    }
                    if p.needsChanges {
                        Text("\(p.moves.count) movimiento(s) · README: \(p.needsReadme ? "actualizar" : "conservar") · JSON: \(p.needsMetadata ? "actualizar" : "conservar")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(p.moves) { move in
                        Text("\(move.source) → \(move.target)")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                    }
                    ForEach(p.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                    }
                }.padding(.vertical, 4)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.red)
            }
            if !result.isEmpty {
                Text(result.joined(separator: "\n"))
                    .font(.caption).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("\(selected.count) proyecto(s) seleccionado(s)")
                    .foregroundStyle(.secondary).font(.caption)
                Spacer()
                Button("Cerrar") { dismiss() }
                Button("Normalizar seleccionados") { normalizeSelected() }
                    .buttonStyle(.borderedProminent)
                    .disabled(busy || selected.isEmpty)
            }
        }
        .padding(18)
        .frame(minWidth: 730, minHeight: 500)
        .task { analyze() }
        .sheet(isPresented: $showProgress) {
            NormalizationProgressSheet(model: progress) {
                showProgress = false
                analyze()
            }
        }
    }

    @MainActor
    private func withLibrary<T>(_ action: (URL) throws -> T) throws -> T {
        guard let library = try FolderAccess.resolveBookmark(key: "libraryBookmark") else {
            throw ImportError.missingBookmark
        }
        guard library.startAccessingSecurityScopedResource() else { throw ImportError.securityAccess }
        defer { library.stopAccessingSecurityScopedResource() }
        return try action(library)
    }


    @MainActor
    private func setFolderMode(_ mode: FolderMode, for proposal: NormalizationProposal) {
        do {
            try withLibrary { library in
                try FolderRules.shared.setMode(mode, for: proposal.projectURL, in: library)
            }
            selected.remove(proposal.id)
            analyze()
        } catch {
            errorMessage = "No se pudo guardar la regla: \(error.localizedDescription)"
        }
    }

    @MainActor
    private func analyze() {
        errorMessage = nil
        result = []
        do {
            proposals = try withLibrary { library in
                let projectURLs = try NormalizationEngine.listProjects(in: library)
                folderModes = Dictionary(uniqueKeysWithValues: try projectURLs.map { url in
                    (url, try FolderRules.shared.mode(for: url, in: library))
                })
                var scanned: [NormalizationProposal] = []
                for url in projectURLs {
                    scanned.append(try NormalizationEngine.scan(url))
                }
                return scanned
            }
            selected = []
        } catch { errorMessage = error.localizedDescription }
    }

    @MainActor
    private func normalizeSelected() {
        let chosen = proposals.filter { selected.contains($0.id) && folderModes[$0.id] == .managed }
        guard !chosen.isEmpty, !busy else { return }
        let library: URL
        do {
            guard let resolved = try FolderAccess.resolveBookmark(key: "libraryBookmark") else {
                throw ImportError.missingBookmark
            }
            library = resolved
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        busy = true
        selected.removeAll()
        progress.begin(total: chosen.count)
        showProgress = true
        let model = progress
        let token = progress.token

        Task {
            // Ningún actor de SwiftUI participa en los cálculos de hashes.
            await Task.detached(priority: .utility) {
                guard library.startAccessingSecurityScopedResource() else {
                    await MainActor.run {
                        model.completedProject("Sin permiso para acceder a la biblioteca", success: false)
                        model.finish(cancelled: true)
                    }
                    return
                }
                defer { library.stopAccessingSecurityScopedResource() }
                for proposal in chosen {
                    if token.isCancelled { break }
                    await MainActor.run { model.starting(proposal.name) }
                    do {
                        let output = try NormalizationEngine.normalize(proposal, in: library) { step in
                            // No saturar la cola principal con miles de notificaciones SHA.
                            Task { @MainActor in model.step(step) }
                        }
                        await MainActor.run { model.completedProject(output, success: true) }
                    } catch {
                        let description = error.localizedDescription
                        await MainActor.run {
                            model.completedProject("\(proposal.name): \(description)", success: false)
                        }
                    }
                }
                await MainActor.run { model.finish(cancelled: token.isCancelled) }
            }.value
            busy = false
        }
    }

    // Pantalla de resultado. Es una sheet independiente de la lista de proyectos.
    private var normalizationReport: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: reportFailures == 0 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(reportFailures == 0 ? Color.green : Color.orange)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(reportFailures == 0 ? "¡Biblioteca normalizada!" : "Normalización con incidencias")
                        .font(.title2.bold())
                    Text(reportFailures == 0
                         ? "Los proyectos seleccionados se han procesado correctamente."
                         : "Algunos proyectos necesitan revisión. Consulta los detalles antes de continuar.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 22)

            HStack(spacing: 12) {
                resultMetric(value: reportSuccesses, label: "Completados", symbol: "checkmark.circle", tint: .green)
                resultMetric(value: reportFailures, label: "Incidencias", symbol: "exclamationmark.triangle", tint: reportFailures > 0 ? .orange : .secondary)
                resultMetric(value: reportRequested, label: "Seleccionados", symbol: "folder", tint: .blue)
            }

            Divider()
                .padding(.vertical, 20)

            HStack {
                Label("Detalles de la operación", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text("\(reportRows.count) registros")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(reportRows.enumerated()), id: \.offset) { _, entry in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: entry.hasPrefix("✗") ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(entry.hasPrefix("✗") ? Color.orange : Color.green)
                                .padding(.top, 2)
                            Text(entry.replacingOccurrences(of: "✓ ", with: "")
                                .replacingOccurrences(of: "✗ ", with: ""))
                                .font(.subheadline)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 260)

            Divider()
                .padding(.vertical, 16)

            HStack {
                Text("El resultado también queda visible en el asistente.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Seguir revisando") {
                    showReport = false
                }
                Button("Cerrar asistente") {
                    showReport = false
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(26)
        .frame(width: 660)
    }

    private func resultMetric(value: Int, label: String, symbol: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Image(systemName: symbol)
                    .foregroundStyle(tint)
                Spacer()
                Text(String(value))
                    .font(.title.bold())
                    .monospacedDigit()
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

}

