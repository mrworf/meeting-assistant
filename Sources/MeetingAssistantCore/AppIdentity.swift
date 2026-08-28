import Foundation

public enum AppIdentity {
    public static let name = "Meeting Assistant"
    public static let bundleIdentifier = "nu.sensenet.meetingassistant"
    public static let legacyBundleIdentifier = "com.henricandersson.MeetingAssistant"
    public static let alertLeadMinuteOptions = [5, 10, 15]
    public static let alertLeadTime: TimeInterval = 5 * 60
    public static let refreshInterval: TimeInterval = 5 * 60
}
