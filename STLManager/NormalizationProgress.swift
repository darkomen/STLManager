import SwiftUI
import Combine
import Foundation

// Cancelación cooperativa: se comprueba entre proyectos (nunca a mitad de un movimiento).
final class NormalizationCancelToken: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var requested = false
    nonisolated func cancel() { lock.lock(); requested = true; lock.unlock() }
    nonisolated var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return requested }
}

@MainActor
final class NormalizationProgressModel: ObservableObject {
    @Published var isRunning = false
    @Published var cancelled = false
    @Published var total = 0
    @Published var completed = 0
    @Published var successes = 0
    @Published var failures = 0
    @Published var currentProject = ""
    @Published var currentStep = ""
    @Published var entries: [String] = []
    @Published var elapsed: TimeInterval = 0
    private var startedAt = Date()
    var token = NormalizationCancelToken()

    func begin(total: Int) {
        self.total = total; completed = 0; successes = 0; failures = 0
        currentProject = ""; currentStep = "Preparando operaciones"
        entries = []; elapsed = 0; cancelled = false; isRunning = true
        startedAt = Date(); token = NormalizationCancelToken()
    }
    func starting(_ name: String) {
        currentProject = name; currentStep = "Analizando proyecto"
        entries.append("▶ \(name)")
    }
    func step(_ message: String) {
        currentStep = message
        // Conservar un registro acotado: RAM estable incluso con miles de ficheros.
        if !message.hasPrefix("SHA-256") {
            entries.append("   \(message)")
            if entries.count > 300 { entries.removeFirst(entries.count - 300) }
        }
    }
    func completedProject(_ message: String, success: Bool) {
        completed += 1
        if success { successes += 1 } else { failures += 1 }
        entries.append((success ? "✓ " : "✗ ") + message)
        if entries.count > 300 { entries.removeFirst(entries.count - 300) }
        elapsed = Date().timeIntervalSince(startedAt)
    }
    func finish(cancelled: Bool) {
        self.cancelled = cancelled
        isRunning = false
        elapsed = Date().timeIntervalSince(startedAt)
        currentStep = cancelled ? "Operación detenida entre proyectos" : "Proceso finalizado"
    }
}

struct NormalizationProgressSheet: View {
    @ObservedObject var model: NormalizationProgressModel
    let onClose: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: model.isRunning ? "arrow.triangle.2.circlepath.circle.fill" :
                        (model.failures > 0 ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"))
                    .font(.system(size: 34))
                    .foregroundStyle(model.isRunning ? .blue : (model.failures > 0 ? .orange : .green))
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.isRunning ? "Normalizando biblioteca" : (model.cancelled ? "Normalización detenida" : "Normalización terminada"))
                        .font(.title2.bold())
                    Text(model.currentStep).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
            }
            ProgressView(value: Double(model.completed), total: Double(max(model.total, 1)))
                .progressViewStyle(.linear)
            HStack {
                Text("\(model.completed) de \(model.total) proyectos")
                Spacer()
                Text("\(Int(Double(model.completed) / Double(max(model.total, 1)) * 100)) %").monospacedDigit()
            }.font(.caption).foregroundStyle(.secondary)
            if model.isRunning {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.currentProject.isEmpty ? "Preparando..." : model.currentProject)
                        .fontWeight(.medium).lineLimit(1)
                }
            }
            HStack(spacing: 16) {
                Label("\(model.successes) completados", systemImage: "checkmark.circle")
                    .foregroundStyle(.green)
                Label("\(model.failures) incidencias", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(model.failures > 0 ? .orange : .secondary)
                Spacer()
                if !model.isRunning {
                    Text("\(Int(model.elapsed)) s").foregroundStyle(.secondary)
                }
            }.font(.callout)
            Divider()
            HStack {
                Label("Registro de operaciones", systemImage: "text.alignleft")
                    .font(.headline)
                Spacer()
                Text("Últimos \(model.entries.count) eventos").font(.caption).foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(model.entries.enumerated()), id: \.offset) { _, entry in
                        Text(entry).font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                }.padding(12)
            }
            .frame(height: 230)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 11))
            HStack {
                if model.isRunning {
                    Text(model.token.isCancelled ? "Cancelación solicitada: terminando el proyecto actual" : "Se puede cancelar entre proyectos")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button(model.token.isCancelled ? "Cancelación solicitada" : "Cancelar") {
                        model.token.cancel()
                        model.currentStep = "Cancelación solicitada · esperando un punto seguro"
                    }.disabled(model.token.isCancelled)
                } else {
                    Text(model.cancelled ? "Los proyectos pendientes no se han procesado." : "Puedes revisar el resultado antes de cerrar.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Cerrar") { onClose() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .frame(width: 690)
        .interactiveDismissDisabled(model.isRunning)
    }
}
