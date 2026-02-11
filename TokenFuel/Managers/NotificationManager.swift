import UserNotifications
import os.log

private let log = Logger(subsystem: "tech.pushtoprod.TokenFuel", category: "NotificationManager")

@MainActor
final class NotificationManager {
    static let shared = NotificationManager()
    
    private init() {}
    
    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                log.error("Notification auth error: \(error.localizedDescription)")
            } else {
                log.info("Notification auth granted: \(granted)")
            }
        }
    }
    
    func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                log.error("Failed to send immediate notification: \(error.localizedDescription)")
            } else {
                log.info("Immediate notification sent: \(title)")
            }
        }
    }
    
    func scheduleNotification(at date: Date, id: String, title: String, body: String) {
        // Don't schedule if in the past
        guard date > Date() else { return }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        
        // Use consistent ID to update/overwrite if needed
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                log.error("Failed to schedule future notification: \(error.localizedDescription)")
            } else {
                log.info("Scheduled notification for \(date): \(title)")
            }
        }
    }
}
