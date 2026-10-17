import Foundation
import AppKit
import UserNotifications

// Un único puente para notificaciones del sistema y la navegación SwiftUI.
// No almacena datos de los archivos ni modifica el contenido de _Inbox.
@MainActor
final class InboxNotificationRouter {
    static let shared = InboxNotificationRouter()
    static let openItem = Notification.Name("STLManager.openInboxItem")
    private let delegate = InboxNotificationDelegate()
    private var configured = false
    // Se conserva hasta que ContentView haya encontrado y abierto el elemento.
    private(set) var pendingInboxPath: String?
    private(set) var authorized = false

    func configure() {
        guard !configured else { return }
        configured = true
        let center = UNUserNotificationCenter.current()
        center.delegate = delegate
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            Task { @MainActor in self.authorized = granted }
        }
    }

    func notify(item: InboxItem) {
        guard authorized else { return }
        let content = UNMutableNotificationContent()
        content.title = "Nuevo elemento para importar"
        content.body = item.displayName
        content.sound = .default
        content.userInfo = ["inboxPath": item.url.standardizedFileURL.path]
        let id = "inbox." + UUID().uuidString
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: nil)) { error in
            if let error { NSLog("STLManager: notificación no entregada: %@", error.localizedDescription) }
        }
    }

    func markOpened(path: String) {
        if pendingInboxPath == path { pendingInboxPath = nil }
    }

    func open(path: String) {
        // Guardar ANTES de activar la app: el evento podría llegar mientras se crea la vista.
        pendingInboxPath = path
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let window = NSApplication.shared.windows.first(where: {
            $0.canBecomeMain && !$0.isMiniaturized
        }) ?? NSApplication.shared.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
        NotificationCenter.default.post(name: Self.openItem, object: nil, userInfo: ["path": path])
    }
}

private final class InboxNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        if let path = response.notification.request.content.userInfo["inboxPath"] as? String {
            Task { @MainActor in InboxNotificationRouter.shared.open(path: path) }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
