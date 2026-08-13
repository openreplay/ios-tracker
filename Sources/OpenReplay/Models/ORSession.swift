import UIKit
import DeviceKit

class ORSessionRequest: NSObject {
    private static var params = [String: AnyHashable]()

    static func create(doNotRecord: Bool,  completion: @escaping (ORSessionResponse?) -> Void) {
        guard let projectKey = Openreplay.shared.projectKey else { return print("Openreplay: no project key added") }
        
        // Make sure is on the main thread: beginGeneratingDeviceOrientationNotifications need Main thread.
        DispatchQueue.main.async {
            // #warning("Can interfere with client usage")
            UIDevice.current.isBatteryMonitoringEnabled = true
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            
            let performances: [String: UInt64] = [
                "physicalMemory": UInt64(ProcessInfo.processInfo.physicalMemory),
                "processorCount": UInt64(ProcessInfo.processInfo.processorCount),
                "activeProcessorCount": UInt64(ProcessInfo.processInfo.activeProcessorCount),
                "systemUptime": UInt64(ProcessInfo.processInfo.systemUptime),
                "isLowPowerModeEnabled": UInt64(ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 : 0),
                "thermalState": UInt64(ProcessInfo.processInfo.thermalState.rawValue),
                "batteryLevel": UInt64(max(0.0, UIDevice.current.batteryLevel)*100),
                "batteryState": UInt64(UIDevice.current.batteryState.rawValue),
                "orientation": UInt64(UIDevice.current.orientation.rawValue),
            ]
            
            let device = Device.current
            // safeDescription reports simulators honestly, e.g. "Simulator (iPhone 15)"
            let deviceSafeName = device.safeDescription
            let deviceModel = Device.identifier
            
            let screenWidth = UIScreen.main.bounds.width
            let screenHeight = UIScreen.main.bounds.height
            
            DebugUtils.log(">>>> device \(device) type \(device.safeDescription) mem \(UInt64(ProcessInfo.processInfo.physicalMemory / 1024))")
            params = [
                "doNotRecord": doNotRecord,
                "projectKey": projectKey,
                "trackerVersion": Openreplay.shared.pkgVersion,
                "revID": Bundle(for: Openreplay.shared.classForCoder).object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "N/A",
                "userUUID": ORUserDefaults.shared.userUUID,
                "userOSVersion": UIDevice.current.systemVersion,
                "userDevice": deviceModel,
                "userDeviceType": deviceSafeName,
                "timestamp": UInt64(Date().timeIntervalSince1970 * 1000),
                "performances": performances,
                "deviceMemory": UInt64(ProcessInfo.processInfo.physicalMemory / 1024),
                "timezone": getTimezone(),
                "width": screenWidth,
                "height": screenHeight,
            ]
            callAPI(completion: completion)
        }
    }

    private static func callAPI(attempt: Int = 0, completion: @escaping (ORSessionResponse?) -> Void) {
        guard !params.isEmpty else { return }
        NetworkManager.shared.createSession(params: params) { (sessionResponse) in
            guard let sessionResponse = sessionResponse else {
                let maxAttempts = 10
                guard attempt < maxAttempts else {
                    DebugUtils.error("Could not start session after \(maxAttempts) attempts, giving up")
                    return completion(nil)
                }
                // Exponential backoff capped at 60s — a fixed 5s loop hammers the
                // backend (and the battery) forever when the server is down.
                let delay = min(60.0, 5.0 * pow(2.0, Double(attempt)))
                DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
                    callAPI(attempt: attempt + 1, completion: completion)
                }
                return
            }
            DebugUtils.log(">>>> Starting session : \(sessionResponse.sessionID)")
            return completion(sessionResponse)
        }
    }
}

struct ORSessionResponse: Decodable {
    let userUUID: String
    let token: String
    let imagesHashList: [String]?
    let sessionID: String
    let fps: Int
    let quality: String
    let projectID: String
    let framesSupport: Bool?
}

func getTimezone() -> String {
    let offset = TimeZone.current.secondsFromGMT()
    let sign = offset >= 0 ? "+" : "-"
    let hours = abs(offset) / 3600
    let minutes = (abs(offset) % 3600) / 60
    return String(format: "UTC%@%02d:%02d", sign, hours, minutes)
}
