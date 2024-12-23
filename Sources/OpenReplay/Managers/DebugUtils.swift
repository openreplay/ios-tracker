import Foundation

class DebugUtils: NSObject {

    static func error(_ str: String) {
        // TODO: fix this one
        // MessageCollector.shared.sendMessage(ASIOSInternalError(content: str))
        print("OpenReplay Error: \(str)")
    }

    static func log(_ str: String) {
        if (Openreplay.shared.options.debugLogs) {
         print("OpenReplay: \(str)")
        }
    }
}
