import Foundation

@objc public enum RecordingQuality: Int {
    case Low
    case Standard
    case High
}

open class OROptions: NSObject {
    let crashes: Bool
    let analytics: Bool
    let performances: Bool
    let logs: Bool
    let screen: Bool
    let minScreenCount: Int
    let wifiOnly: Bool
    let debugLogs: Bool
    let debugImages: Bool
    
    public static let defaults = OROptions(crashes: true, analytics: true, performances: true, logs: true, screen: true, minScreenCount: 20, wifiOnly: true, debugLogs: false, debugImages: false)
    public static let defaultDebug = OROptions(crashes: true, analytics: true, performances: true, logs: true, screen: true, minScreenCount: 20, wifiOnly: true, debugLogs: true, debugImages: false)

    @objc public init(crashes: Bool = true, analytics: Bool = true, performances: Bool = true, logs: Bool = true, screen: Bool = true, minScreenCount: Int = 20, wifiOnly: Bool = true, debugLogs: Bool = false, debugImages: Bool = false) {
        self.crashes = crashes
        self.analytics = analytics
        self.performances = performances
        self.logs = logs
        self.screen = screen
        self.minScreenCount = minScreenCount
        self.wifiOnly = wifiOnly
        self.debugLogs = debugLogs
        self.debugImages = debugImages
    }
}
