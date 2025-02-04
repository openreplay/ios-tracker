import UIKit
import Network

public enum CheckState {
    case unchecked
    case canStart
    case cantStart
}

open class Openreplay: NSObject {
    @objc public static let shared = Openreplay()
    public let userDefaults = UserDefaults(suiteName: "io.asayer.AsayerSDK-defaults")
    public var projectKey: String?
    public var pkgVersion = "1.0.14"
    private var sessionData: ORSessionResponse?
    public var sessionStartTs: UInt64 = 0
    public var trackerState = CheckState.unchecked
    private var networkCheckTimer: Timer?
    public var bufferingMode = false
    public var serverURL: String {
        get { NetworkManager.shared.baseUrl }
        set { NetworkManager.shared.baseUrl = newValue }
    }
    public var options: OROptions = OROptions.defaults

    @objc open func start(projectKey: String, options: OROptions) {
        self.options = options
        self.projectKey = projectKey
        let monitor = NWPathMonitor()
        let q = DispatchQueue.global(qos: .background)
        
        monitor.start(queue: q)
        
        monitor.pathUpdateHandler = { path in
            if path.usesInterfaceType(.wifi) {
                if PerformanceListener.shared.isActive {
                    PerformanceListener.shared.networkStateChange(1)
                }
                self.trackerState = CheckState.canStart
            } else if path.usesInterfaceType(.cellular) {
                if PerformanceListener.shared.isActive {
                    PerformanceListener.shared.networkStateChange(0)
                }
                if options.wifiOnly {
                    self.trackerState = CheckState.cantStart
                    print("Connected to Cellular and options.wifiOnly is true. Openreplay will not start.")
                } else {
                    self.trackerState = CheckState.canStart
                }
            } else {
                self.trackerState = CheckState.cantStart
                print("Not connected to either WiFi or Cellular. Openreplay will not start.")
            }
        }
        
        networkCheckTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { (_) in
            if self.trackerState == CheckState.canStart {
                self.startSession(projectKey: projectKey, options: options)
                self.networkCheckTimer?.invalidate()
            }
            if self.trackerState == CheckState.cantStart {
                self.networkCheckTimer?.invalidate()
            }
        })
    }
    
    @objc open func startSession(projectKey: String, options: OROptions) {
        self.projectKey = projectKey
        ORSessionRequest.create(doNotRecord: false) { sessionResponse in
            guard let sessionResponse = sessionResponse else { return print("Openreplay: no response from /start request") }
            self.sessionStartTs = UInt64(Date().timeIntervalSince1970 * 1000)
            self.sessionData = sessionResponse
            let captureSettings = getCaptureSettings(fps: 3, quality: "high") // getCaptureSettings(fps: sessionResponse.fps, quality: sessionResponse.quality)
            ScreenshotManager.shared.setSettings(settings: captureSettings)
            
            MessageCollector.shared.start()
            
            if options.logs {
                if #available(iOS 13.4, *) {
                    LogsListener.shared.start()
                } else {
                    // Fallback on earlier versions
                }
            }
            
            if options.crashes {
                Crashs.shared.start()
            }
            
            if options.performances {
                PerformanceListener.shared.start()
            }
            
            if options.screen {
                ScreenshotManager.shared.start(startTs: self.sessionStartTs)
            }
            
            if options.analytics {
                Analytics.shared.start()
            }
        }
    }
    
    @objc open func coldStart(projectKey: String, options: OROptions) {
        self.options = options
        self.projectKey = projectKey
        self.bufferingMode = true
        ORSessionRequest.create(doNotRecord: true) { sessionResponse in
            guard let sessionResponse = sessionResponse else { return print("Openreplay: no response from /start request") }
            self.sessionStartTs = UInt64(Date().timeIntervalSince1970 * 1000)
            self.sessionData = sessionResponse
            ConditionsManager.shared.getConditions(projectId: sessionResponse.projectID, token: sessionResponse.token)
            let captureSettings = getCaptureSettings(fps: sessionResponse.fps, quality: sessionResponse.quality)

            MessageCollector.shared.cycleBuffer()

            if options.logs {
                if #available(iOS 13.4, *) {
                    LogsListener.shared.start()
                } else {
                    // Fallback on earlier versions
                }
            }
            
            if options.crashes {
                Crashs.shared.start()
            }
            
            if options.performances {
                PerformanceListener.shared.start()
            }
            
            if options.screen {
                ScreenshotManager.shared.setSettings(settings: captureSettings)
                ScreenshotManager.shared.start(startTs: self.sessionStartTs)
                ScreenshotManager.shared.cycleBuffer()
            }
            
            if options.analytics {
                Analytics.shared.start()
            }
        }
    }
    
    @objc open func triggerRecording(condition: String?) {
        self.bufferingMode = false
        ORSessionRequest.create(doNotRecord: false) { sessionResponse in
            guard let sessionResponse = sessionResponse else { return print("Openreplay: no response from /start request") }
            
            // sending buffered messages and images - should not be bigger than 30sec buffer,
            // so the performance impact is minimal (as long as fps was lower than 10)
            MessageCollector.shared.syncBuffers()
            ScreenshotManager.shared.syncBuffers()
            
            MessageCollector.shared.start()
        }
    }
    
    @objc open func stop() {
        MessageCollector.shared.stop()
        ScreenshotManager.shared.stop()
        Crashs.shared.stop()
        PerformanceListener.shared.stop()
        Analytics.shared.stop()
    }
    
    @objc open func addIgnoredView(_ view: UIView) {
        ScreenshotManager.shared.addSanitizedElement(view)
    }
    
    @objc open func setMetadata(key: String, value: String) {
        let message = ORMobileMetadata(key: key, value: value)
        MessageCollector.shared.sendMessage(message)
    }

    @objc open func event(name: String, object: NSObject?) {
        event(name: name, payload: object as? Encodable)
    }

    open func event(name: String, payload: Encodable?) {
        var json = ""
        if let payload = payload,
           let data = payload.toJSONData(),
           let jsonStr = String(data: data, encoding: .utf8) {
            json = jsonStr
        }
        let message = ORMobileEvent(name: name, payload: json)
        MessageCollector.shared.sendMessage(message)
    }
    
    open func eventStr(name: String, payload: String?) {
        let message = ORMobileEvent(name: name, payload: payload ?? "")
        MessageCollector.shared.sendMessage(message)
    }

    @objc open func setUserID(_ userID: String) {
        let message = ORMobileUserID(iD: userID)
        MessageCollector.shared.sendMessage(message)
    }

    @objc open func userAnonymousID(_ userID: String) {
        let message = ORMobileUserAnonymousID(iD: userID)
        MessageCollector.shared.sendMessage(message)
    }
    
    @objc open func networkRequest(url: String, method: String, requestJSON: String, responseJSON: String, status: Int, duration: UInt64) {
        sendNetworkMessage(url: url, method: method, requestJSON: requestJSON, responseJSON: responseJSON, status: status, duration: duration)
    }
    
    @objc open func getSessionID() -> String {
        if let sessionId = self.sessionData?.sessionID {
            return sessionId
        } else {
            return ""
        }
    }
    
    @objc open func sendMessage(_ type: String, _ msg: String) {
        if type == "gql" {
            guard let data = msg.data(using: .utf8),
                  let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return
            }

            let operationKind = dict["operationKind"] as? String ?? ""
            let operationName = dict["operationName"] as? String ?? ""
            let duration = UInt64(dict["duration"] as? Int ?? 0)

            var variablesString = ""
            if let variablesObj = dict["variables"],
               let variablesData = try? JSONSerialization.data(withJSONObject: variablesObj, options: []),
               let jsonStr = String(data: variablesData, encoding: .utf8) {
                variablesString = jsonStr
            }
            variablesString = variablesString.trimmingCharacters(in: .whitespacesAndNewlines)

            var responseString = ""
            if let responseObj = dict["response"],
               let responseData = try? JSONSerialization.data(withJSONObject: responseObj, options: []),
               let jsonStr = String(data: responseData, encoding: .utf8) {
                responseString = jsonStr
            }
            responseString = responseString.trimmingCharacters(in: .whitespacesAndNewlines)

            let gqlMessage = ORGraphQL(operationKind: operationKind, operationName: operationName, variables: variablesString, response: responseString, duration: duration)
            MessageCollector.shared.sendMessage(gqlMessage)
        } else {
            print("Openreplay: Unknown msg type passed.")
        }
    }
}



func getCaptureSettings(fps: Int, quality: String) -> (captureRate: Double, imgCompression: Double) {
    let limitedFPS = min(max(fps, 1), 99)
    let captureRate = 1.0 / Double(limitedFPS)
    
    var imgCompression: Double
    switch quality.lowercased() {
    case "low":
        imgCompression = 0.4
    case "standard":
        imgCompression = 0.5
    case "high":
        imgCompression = 0.6
    default:
        imgCompression = 0.5  // default to standard if quality string is not recognized
    }
    
    return (captureRate: captureRate, imgCompression: imgCompression)
}
