import UIKit

open class PerformanceListener: NSObject {
    public static let shared = PerformanceListener()
    private var cpuTimer: Timer?
    private var cpuIteration = 0
    private var memTimer: Timer?
    public var isActive = false
    private var pauseTimer: Timer?
    private var wasPaused = false
    
    func start() {
        guard !isActive else { return }
//         #warning("Can interfere with client usage")
        UIDevice.current.isBatteryMonitoringEnabled = true
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        
        let observe: (Notification.Name) -> Void = {
            NotificationCenter.default.addObserver(self, selector: #selector(self.notified(_:)), name: $0, object: nil)
        }
        observe(.NSBundleResourceRequestLowDiskSpace)
        observe(.NSProcessInfoPowerStateDidChange)
        observe(ProcessInfo.thermalStateDidChangeNotification)
        observe(UIApplication.didReceiveMemoryWarningNotification)
        observe(UIDevice.batteryLevelDidChangeNotification)
        observe(UIDevice.batteryStateDidChangeNotification)
        observe(UIDevice.orientationDidChangeNotification)

        getCpuMessage()
        getMemoryMessage()
        
        self.setupTimers()
        isActive = true
        
        
        NotificationCenter.default.addObserver(self, selector: #selector(pause), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.willEnterForegroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.didBecomeActiveNotification, object: nil)
    }
    
    private var resuming = false
    @objc func resume() {
        guard !self.resuming else { return }
        self.resuming = true
        defer { self.resuming = false }
        
        pauseTimer?.invalidate()
        pauseTimer = nil
        
        DebugUtils.log("Resume \(wasPaused)")
        getCpuMessage()
        DebugUtils.log("sent cpu")
        getMemoryMessage()
        DebugUtils.log("sent mem")
        MessageCollector.shared.sendMessage(ORMobilePerformanceEvent(name: "background", value: UInt64(0)))
        DebugUtils.log("stsarting stuff")
        if wasPaused {
            if Openreplay.shared.options.logs {
                if #available(iOS 13.4, *) {
                    LogsListener.shared.start()
                } else {
                    // Fallback on earlier versions
                }
            }
            
            if Openreplay.shared.options.crashes {
                Crashs.shared.start()
            }
            
            if Openreplay.shared.options.performances {
                PerformanceListener.shared.start()
            }
            
            if Openreplay.shared.options.screen {
                ScreenshotManager.shared.start(startTs: Openreplay.shared.sessionStartTs)
            }
            
            if Openreplay.shared.options.analytics {
                Analytics.shared.start()
            }
            
            DebugUtils.log("Resume collector")
            MessageCollector.shared.start()
            
            UIDevice.current.isBatteryMonitoringEnabled = true
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            
            let observe: (Notification.Name) -> Void = {
                NotificationCenter.default.addObserver(self, selector: #selector(self.notified(_:)), name: $0, object: nil)
            }
            observe(.NSBundleResourceRequestLowDiskSpace)
            observe(.NSProcessInfoPowerStateDidChange)
            observe(ProcessInfo.thermalStateDidChangeNotification)
            observe(UIApplication.didReceiveMemoryWarningNotification)
            observe(UIDevice.batteryLevelDidChangeNotification)
            observe(UIDevice.batteryStateDidChangeNotification)
            observe(UIDevice.orientationDidChangeNotification)

            DebugUtils.log("getting profiling")
            getCpuMessage()
            getMemoryMessage()
            
            self.setupTimers()
            isActive = true
            
            DebugUtils.log("done")
            wasPaused = false
        }
        self.resuming = false
    }
    
    private func setupTimers() {
        cpuTimer?.invalidate()
        cpuTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { _ in
            self.getCpuMessage()
        })

        memTimer?.invalidate()
        memTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true, block: { _ in
            self.getMemoryMessage()
        })
    }
    
    var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    @objc func pause() {
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "PauseOperations") {
            self.endBackgroundTask()
        }
        DebugUtils.log("Entering Background")
        MessageCollector.shared.sendMessage(ORMobilePerformanceEvent(name: "background", value: UInt64(1)))
        pauseOperations {
            self.endBackgroundTask()
        }
    }
    
    private func endBackgroundTask() {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }
    
    private func pauseOperations(completion: (() -> Void)? = nil) {
        MessageCollector.shared.stop()
        DebugUtils.log("messages stop")
        ScreenshotManager.shared.stop()
        DebugUtils.log("screenshots stop")
        Crashs.shared.stop()
        DebugUtils.log("crash stop")
        PerformanceListener.shared.stop()
        DebugUtils.log("perf stop")
        Analytics.shared.stop()
        DebugUtils.log("graphs stop")
        self.stopTrackingMethods()
        DebugUtils.log("self stop")
        if #available(iOS 13.4, *) {
            LogsListener.shared.stop()
        } else {
            // Fallback on earlier versions
        }
        wasPaused = true
        completion?()
    }
    
    func getCpuMessage() {
        if let cpu = self.cpuUsage() {
            MessageCollector.shared.sendMessage(ORMobilePerformanceEvent(name: "mainThreadCPU", value: UInt64(cpu)))
        }
    }
    
    func getMemoryMessage() {
        if let mem = self.memoryUsage() {
            MessageCollector.shared.sendMessage(ORMobilePerformanceEvent(name: "memoryUsage", value: UInt64(mem)))
        }
    }
    
    func stopTrackingMethods() {
        UIDevice.current.isBatteryMonitoringEnabled = false
        UIDevice.current.endGeneratingDeviceOrientationNotifications()

        NotificationCenter.default.removeObserver(self, name: .NSBundleResourceRequestLowDiskSpace, object: nil)
        NotificationCenter.default.removeObserver(self, name: .NSProcessInfoPowerStateDidChange, object: nil)
        NotificationCenter.default.removeObserver(self, name: ProcessInfo.thermalStateDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIDevice.batteryStateDidChangeNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIDevice.orientationDidChangeNotification, object: nil)
        cpuTimer?.invalidate()
        cpuTimer = nil
        memTimer?.invalidate()
        memTimer = nil
    }
    
    func stop() {
        if isActive {
            self.stopTrackingMethods()
            NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
            isActive = false
        }
    }
    
    public func sendBattery() {
        let message = ORMobilePerformanceEvent(name: "batteryLevel", value: 20)
        
        MessageCollector.shared.sendMessage(message)
    }
    
    public func sendThermal() {
        let message2 = ORMobilePerformanceEvent(name: "thermalState", value: 2)
        MessageCollector.shared.sendMessage(message2)
    }

    @objc func notified(_ notification: Notification) {
        var message: ORMobilePerformanceEvent? = nil
        switch notification.name {
        case .NSBundleResourceRequestLowDiskSpace:
            message = ORMobilePerformanceEvent(name: "lowDiskSpace", value: 0)
        case .NSProcessInfoPowerStateDidChange:
            message = ORMobilePerformanceEvent(name: "isLowPowerModeEnabled", value: ProcessInfo.processInfo.isLowPowerModeEnabled ? 1 : 0)
        case ProcessInfo.thermalStateDidChangeNotification:
            message = ORMobilePerformanceEvent(name: "thermalState", value: UInt64(ProcessInfo.processInfo.thermalState.rawValue))
        case UIApplication.didReceiveMemoryWarningNotification:
            message = ORMobilePerformanceEvent(name: "memoryWarning", value: 0)
        case UIDevice.batteryLevelDidChangeNotification:
            message = ORMobilePerformanceEvent(name: "batteryLevel", value: UInt64(max(0.0, UIDevice.current.batteryLevel)*100))
        case UIDevice.batteryStateDidChangeNotification:
            message = ORMobilePerformanceEvent(name: "batteryState", value: UInt64(UIDevice.current.batteryState.rawValue))
        case UIDevice.orientationDidChangeNotification:
            message = ORMobilePerformanceEvent(name: "orientation", value: UInt64(UIDevice.current.orientation.rawValue))
        default: break
        }
        if let message = message {
            MessageCollector.shared.sendMessage(message)
        }
    }
    
    func networkStateChange(_ state: UInt64) {
        let message = ORMobilePerformanceEvent(name: "networkState", value: state)
        MessageCollector.shared.sendMessage(message)
    }

    func memoryUsage() -> UInt64? {
        var taskInfo = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info>.size) / 4
        let result: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }

        guard result == KERN_SUCCESS else {
            return nil
        }
        return UInt64(taskInfo.phys_footprint)
    }

    func cpuUsage() -> Double? {
        var threadsListContainer: thread_act_array_t?
        var threadsCount = mach_msg_type_number_t(0)
        let threadsResult = withUnsafeMutablePointer(to: &threadsListContainer) {
            return $0.withMemoryRebound(to: thread_act_array_t?.self, capacity: 1) {
                task_threads(mach_task_self_, $0, &threadsCount)
            }
        }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threadsListContainer)), vm_size_t(Int(threadsCount) * MemoryLayout<thread_t>.stride))
        }

        guard threadsCount > 0, threadsResult == KERN_SUCCESS, let threadsList = threadsListContainer else {
            return nil
        }
        var threadInfo = thread_basic_info()
        var threadInfoCount = mach_msg_type_number_t(THREAD_INFO_MAX)
        let infoResult = withUnsafeMutablePointer(to: &threadInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                thread_info(threadsList[0], thread_flavor_t(THREAD_BASIC_INFO), $0, &threadInfoCount)
            }
        }

        let threadBasicInfo = threadInfo as thread_basic_info
        guard infoResult == KERN_SUCCESS, threadBasicInfo.flags & TH_FLAGS_IDLE == 0 else { return nil }
        return Double(threadBasicInfo.cpu_usage) / Double(TH_USAGE_SCALE) * 100.0
    }
}
