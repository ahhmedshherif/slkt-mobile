import UserNotifications

final class NotificationService: UNNotificationServiceExtension {
    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = request.content.mutableCopy() as? UNMutableNotificationContent

        guard let bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        // Keep the extension dependency-free. OneSignal in the Runner target
        // registers with APNs; this extension merely preserves the notification
        // content if iOS invokes it for mutable-content payloads.
        contentHandler(bestAttemptContent)
    }

    override func serviceExtensionTimeWillExpire() {
        guard let bestAttemptContent else { return }
        contentHandler?(bestAttemptContent)
    }
}
