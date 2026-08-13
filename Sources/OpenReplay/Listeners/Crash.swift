import UIKit

public class Crashs: NSObject {
    public static let shared = Crashs()
    private static var fileUrl: URL? = nil
    // Handler installed before ours (Crashlytics, Sentry, ...) — must be chained,
    // otherwise this SDK silently disables the app's other crash reporters.
    private static var previousHandler: (@convention(c) (NSException) -> Void)? = nil
    private var isActive = false
    
    private override init() {
        Crashs.fileUrl = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("ASCrash.dat")
        if let fileUrl = Crashs.fileUrl,
           FileManager.default.fileExists(atPath: fileUrl.path),
           let crashData = try? Data(contentsOf: fileUrl) {
            NetworkManager.shared.sendLateMessage(content: crashData) { (success) in
                guard success else { return }
                if FileManager.default.fileExists(atPath: fileUrl.path) {
                    try? FileManager.default.removeItem(at: fileUrl)
                }
            }
        }
    }

    public func start() {
        guard !isActive else { return }
        Crashs.previousHandler = NSGetUncaughtExceptionHandler()
        NSSetUncaughtExceptionHandler { (exception) in
            DebugUtils.log("<><> captured crash \(exception)")
            let message = ORMobileCrash(name: exception.name.rawValue,
                                     reason: exception.reason ?? "",
                                     stacktrace: exception.callStackSymbols.joined(separator: "\n"))
            // Disk only: the process dies when this handler returns, so async
            // network work never completes. The file is sent via /late on next launch.
            if let fileUrl = Crashs.fileUrl {
                try? message.contentData().write(to: fileUrl)
            }
            Crashs.previousHandler?(exception)
        }
        isActive = true
    }
    
    public func sendLateError(exception: NSException) {
        let message = ORMobileCrash(name: exception.name.rawValue,
                                 reason: exception.reason ?? "",
                                 stacktrace: exception.callStackSymbols.joined(separator: "\n")
        )
        NetworkManager.shared.sendLateMessage(content: message.contentData()) { (success) in
            guard success else { return }
            if let fileUrl = Crashs.fileUrl,
               FileManager.default.fileExists(atPath: fileUrl.path) {
                try? FileManager.default.removeItem(at: fileUrl)
            }
        }
    }
    
    public func stop() {
        if isActive {
            NSSetUncaughtExceptionHandler(Crashs.previousHandler)
            Crashs.previousHandler = nil
            isActive = false
        }
    }
}
