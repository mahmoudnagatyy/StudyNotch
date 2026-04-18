sed -i '' 's/UNUserNotificationCenter\.current()/safeCenter()/g' StudyNotch/NotificationService.swift StudyNotch/GoogleCalendarService.swift
cat << 'INNER_EOF' >> StudyNotch/NotificationService.swift

func safeCenter() -> UNUserNotificationCenter? {
    guard Bundle.main.bundleIdentifier != nil else { return nil }
    return UNUserNotificationCenter.current()
}
INNER_EOF
