import Foundation

/// An enum representing different recording quality options.
/// - Low: Low recording quality.
/// - Standard: Standard recording quality.
/// - High: High recording quality.
@objc public enum RecordingQuality: Int {
    case Low
    case Standard
    case High
}

/// A class that encapsulates various configuration options for the library.
///
/// - Properties:
///   - crashes: Enable or disable crash reporting.
///   - analytics: Enable or disable analytics collection.
///   - performances: Enable or disable performance monitoring.
///   - logs: Enable or disable log collection.
///   - screen: Enable or disable screen recording.
///   - screenshotBatchSize: Number of screenshots to be taken before packing them together and sending to the server.
///   - wifiOnly: Restrict data transmission to Wi-Fi connections only.
///   - debugLogs: Enable or disable debug logging.
///   - debugImages: Enable or disable capturing debug images.
open class OROptions: NSObject {
    /// Enable or disable crash reporting.
    let crashes: Bool
    /// Enable or disable analytics collection.
    let analytics: Bool
    /// Enable or disable performance monitoring.
    let performances: Bool
    /// Enable or disable log collection.
    let logs: Bool
    /// Enable or disable screen recording.
    let screen: Bool
    /// Number of screenshots to be taken before packing them together and sending to the server.
    let screenshotBatchSize: ScreenshotBatchSize
    /// Restrict data transmission to Wi-Fi connections only.
    let wifiOnly: Bool
    /// Enable or disable debug logging.
    let debugLogs: Bool
    /// Enable or disable capturing debug images.
    let debugImages: Bool
    
    /// Default options for release builds.
    public static let defaults = OROptions(crashes: true, analytics: true, performances: true, logs: true, screen: true, screenshotBatchSize: .normal, wifiOnly: true, debugLogs: false, debugImages: false)
    
    /// Default options for debug builds.
    public static let defaultDebug = OROptions(crashes: true, analytics: true, performances: true, logs: true, screen: true, screenshotBatchSize: .normal, wifiOnly: true, debugLogs: true, debugImages: false)
    
    /// Initializes a new instance of `OROptions` with the provided configuration.
    ///
    /// - Parameters:
    ///   - crashes: Enable or disable crash reporting. Default is `true`.
    ///   - analytics: Enable or disable analytics collection. Default is `true`.
    ///   - performances: Enable or disable performance monitoring. Default is `true`.
    ///   - logs: Enable or disable log collection. Default is `true`.
    ///   - screen: Enable or disable screen recording. Default is `true`.
    ///   - screenshotBatchSize: Number of screenshots to be taken before packing them together and sending to the server. Default is `.normal`.
    ///   - wifiOnly: Restrict data transmission to Wi-Fi connections only. Default is `true`.
    ///   - debugLogs: Enable or disable debug logging. Default is `false`.
    ///   - debugImages: Enable or disable capturing debug images. Default is `false`.
    @objc public init(crashes: Bool = true, analytics: Bool = true, performances: Bool = true, logs: Bool = true, screen: Bool = true, screenshotBatchSize: ScreenshotBatchSize = .normal, wifiOnly: Bool = true, debugLogs: Bool = false, debugImages: Bool = false) {
        self.crashes = crashes
        self.analytics = analytics
        self.performances = performances
        self.logs = logs
        self.screen = screen
        self.screenshotBatchSize = screenshotBatchSize
        self.wifiOnly = wifiOnly
        self.debugLogs = debugLogs
        self.debugImages = debugImages
    }
}

public extension OROptions {
    /// An enum representing different screenshot batch sizes.
    ///
    /// - low: Capture 10 screenshots before packing them.
    /// - normal: Capture 20 screenshots before packing them.
    /// - high: Capture 30 screenshots before packing them.
    @objc enum ScreenshotBatchSize: Int {
        case low = 10
        case normal = 20
        case high = 30
    }
}
