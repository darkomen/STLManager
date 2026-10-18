import SwiftUI
import AppKit

@main
struct STLManagerApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        Window("STL Manager", id: "main") {
            ContentView().environment(appState)
        }
        MenuBarExtra {
            STLManagerMenu(appState: appState)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "shippingbox.fill")
                if appState.pendingCount > 0 {
                    Text("\(appState.pendingCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .monospacedDigit()
                }
            }
            .accessibilityLabel(
                appState.pendingCount == 0
                    ? "STL Manager: no hay proyectos pendientes"
                    : "STL Manager: \(appState.pendingCount) proyectos pendientes"
            )
        }
        Settings {
            SettingsView()
        }
        // Reemplaza «Acerca de ...» del menú de la app por la ventana
        // estándar de macOS con créditos propios.
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Acerca de STL Manager") {
                    STLManagerAbout.show()
                }
            }
        }
    }
}

// Reutilizamos el panel nativo: toma el icono y la versión del bundle.
private enum STLManagerAbout {
    static func show() {
        let credits = NSAttributedString(
            string: "Gestor de proyectos de impresión 3D para macOS.\n\n" +
                "Importación y organización de STL, 3MF, STEP y ZIP. " +
                "Normalización de bibliotecas, protección de colecciones " +
                "y notificaciones de nuevos elementos en _Inbox.\n\n" +
                "Proyecto personal desarrollado con SwiftUI y Swift, " +
                "mediante vibe coding asistido por IA."
        )
        NSApplication.shared.orderFrontStandardAboutPanel(
            options: [.credits: credits]
        )
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

private struct STLManagerMenu: View {
    let appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text("Proyectos en _Inbox: \(appState.pendingCount)")
        Divider()
        Button("Abrir STL Manager") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button("Actualizar") {
            appState.refreshManually()
        }
        Divider()
        Button("Acerca de STL Manager") {
            STLManagerAbout.show()
        }
        SettingsLink {
            Label("Preferencias…", systemImage: "gear")
        }
        Divider()
        Button("Salir") {
            NSApplication.shared.terminate(nil)
        }
    }
}
