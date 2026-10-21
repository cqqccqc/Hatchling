import Foundation
import UserNotifications
import HatchlingKit

/// 毒舌闹钟（零文字约束只约束 UI；通知文案是内容）
/// 性格参数调制语气：毒舌高 → 毒舌池
enum NotificationService {
    private static let gentlePool = [
        "⛏ 矿洞开张了，起床挖矿！",
        "☀️ 我已经醒了，豆豆在等你",
        "起床～昨晚我梦见你迟到了",
    ]
    private static let snarkyPool = [
        "再睡啊，豆子我自己吃",
        "太阳都晒到我的天线了",
        "闹钟响了。不理我也行，反正饿的是你",
    ]

    static func scheduleMorningAlarm(personality: Personality? = nil, hour: Int = 8) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            let snarky = (personality?.snark ?? 0.5) > 0.6
            let content = UNMutableNotificationContent()
            content.body = snarky ? snarkyPool.randomElement()! : gentlePool.randomElement()!
            content.sound = .default
            var comp = DateComponents()
            comp.hour = hour
            let trigger = UNCalendarNotificationTrigger(dateMatching: comp, repeats: true)
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
        }
    }

    static let identifier = "hatchling.alarm.morning"
}
