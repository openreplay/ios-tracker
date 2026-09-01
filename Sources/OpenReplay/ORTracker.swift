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
    public var bufferingMode = false
    private var pathMonitor: NWPathMonitor?
    private var sessionStartRequested = false
    // Flipped by the path monitor when wifiOnly is set and the device is on
    // cellular — uploads pause (batches stay queued) until WiFi returns.
    var uploadsAllowed = true
    public var serverURL: String {
        get { NetworkManager.shared.baseUrl }
        set { NetworkManager.shared.baseUrl = newValue }
    }
    public var options: OROptions = OROptions.defaults

    @objc open func start(projectKey: String, options: OROptions) {
        self.options = options
        self.projectKey = projectKey
        self.sessionStartRequested = false
        self.pathMonitor?.cancel()
        self.pathMonitor = NWPathMonitor()

        // NWPathMonitor is push-based — the session starts straight from the first
        // satisfying path update. It keeps monitoring afterwards: if the app launches
        // on cellular with wifiOnly set, recording starts once WiFi appears, and
        // uploads pause/resume on later network changes.
        self.pathMonitor?.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            DispatchQueue.main.async {
                if path.usesInterfaceType(.wifi) || path.usesInterfaceType(.wiredEthernet) {
                    if PerformanceListener.shared.isActive {
                        PerformanceListener.shared.networkStateChange(1)
                    }
                    self.trackerState = .canStart
                    self.uploadsAllowed = true
                } else if path.usesInterfaceType(.cellular) {
                    if PerformanceListener.shared.isActive {
                        PerformanceListener.shared.networkStateChange(0)
                    }
                    if options.wifiOnly {
                        self.trackerState = .cantStart
                        self.uploadsAllowed = false
                        print("Connected to Cellular and options.wifiOnly is true. Openreplay will not start.")
                    } else {
                        self.trackerState = .canStart
                        self.uploadsAllowed = true
                    }
                } else {
                    self.trackerState = .cantStart
                    // No usable interface: hold the batches instead of dispatching
                    // uploads that can only fail and be requeued.
                    self.uploadsAllowed = false
                    print("Not connected to either WiFi or Cellular. Openreplay will not start.")
                }

                if self.trackerState == .canStart && !self.sessionStartRequested {
                    self.sessionStartRequested = true
                    self.startSession(projectKey: projectKey, options: options)
                }
            }
        }

        self.pathMonitor?.start(queue: DispatchQueue.global(qos: .utility))
    }

    /// Shared listener wiring for session start, cold start, and foreground resume.
    func startListeners(options: OROptions) {
        if options.logs {
            if #available(iOS 13.4, *) {
                LogsListener.shared.start()
            }
        }
        if options.crashes {
            Crashs.shared.start()
        }
        if options.performances {
            PerformanceListener.shared.start()
        }
        if options.analytics {
            Analytics.shared.start()
        }
    }
    
    @objc open func startSession(projectKey: String, options: OROptions) {
        self.projectKey = projectKey
        ORSessionRequest.create(doNotRecord: false) { sessionResponse in
            guard let sessionResponse = sessionResponse else { return print("Openreplay: no response from /start request") }
            self.sessionStartTs = UInt64(Date().timeIntervalSince1970 * 1000)
            self.sessionData = sessionResponse
            let captureSettings = getCaptureSettings(fps: sessionResponse.fps, quality: sessionResponse.quality)
            ScreenshotManager.shared.setSettings(settings: captureSettings)
            
            MessageCollector.shared.start()
            self.startListeners(options: options)

            if options.screen {
                ScreenshotManager.shared.start(startTs: self.sessionStartTs, framesSupport: sessionResponse.framesSupport ?? false)
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
            self.startListeners(options: options)

            if options.screen {
                ScreenshotManager.shared.setSettings(settings: captureSettings)
                ScreenshotManager.shared.start(startTs: self.sessionStartTs, framesSupport: sessionResponse.framesSupport ?? false)
                ScreenshotManager.shared.cycleBuffer()
            }
        }
    }
    
    @objc open func triggerRecording(condition: String?) {
        self.bufferingMode = false
        ORSessionRequest.create(doNotRecord: false) { sessionResponse in
            guard sessionResponse != nil else { return print("Openreplay: no response from /start request") }
            
            // sending buffered messages and images - should not be bigger than 30sec buffer,
            // so the performance impact is minimal (as long as fps was lower than 10)
            MessageCollector.shared.syncBuffers()
            ScreenshotManager.shared.syncBuffers()
            
            MessageCollector.shared.start()
        }
    }
    
    @objc open func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        sessionStartRequested = false
        // Nothing is monitoring the path anymore, so leave uploads unblocked for
        // any explicit call after stop() (e.g. sendLateMessage on next start).
        uploadsAllowed = true

        MessageCollector.shared.stop()
        ScreenshotManager.shared.stop()
        Crashs.shared.stop()
        PerformanceListener.shared.stop(disableLifecycle: true)
        Analytics.shared.stop()
        ConditionsManager.shared.stop()
        if #available(iOS 13.4, *) {
            LogsListener.shared.stop()
        }
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
        } else if payload != nil {
            DebugUtils.error("event '\(name)': payload is not Encodable, sending empty payload")
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
            // UInt64(negative) traps at runtime — clamp integrator-supplied values
            let duration = UInt64(max(0, dict["duration"] as? Int ?? 0))

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
    
    @objc open func useTouchSwizzle() {
        UIWindow.useOpenReplayTouchCapture()
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
