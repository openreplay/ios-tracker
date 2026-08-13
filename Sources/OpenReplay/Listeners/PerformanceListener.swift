import UIKit

open class PerformanceListener: NSObject {
    public static let shared = PerformanceListener()
    private var cpuTimer: Timer?
    private var memTimer: Timer?
    public var isActive = false
    private var wasPaused = false
    // Lifecycle observers (pause/resume) are registered once and survive pause() —
    // removing them there would leave nothing to fire resume() on foregrounding.
    private var lifecycleObserversRegistered = false

    private let metricNotifications: [Notification.Name] = [
        .NSBundleResourceRequestLowDiskSpace,
        .NSProcessInfoPowerStateDidChange,
        ProcessInfo.thermalStateDidChangeNotification,
        UIApplication.didReceiveMemoryWarningNotification,
        UIDevice.batteryLevelDidChangeNotification,
        UIDevice.batteryStateDidChangeNotification,
        UIDevice.orientationDidChangeNotification,
    ]

    func start() {
        guard !isActive else { return }
        DispatchQueue.main.async {
            UIDevice.current.isBatteryMonitoringEnabled = true
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        }

        for name in metricNotifications {
            NotificationCenter.default.addObserver(self, selector: #selector(notified(_:)), name: name, object: nil)
        }

        getCpuMessage()
        getMemoryMessage()

        setupTimers()
        isActive = true

        if !lifecycleObserversRegistered {
            lifecycleObserversRegistered = true
            NotificationCenter.default.addObserver(self, selector: #selector(pause), name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(resume), name: UIApplication.willEnterForegroundNotification, object: nil)
        }
    }

    @objc func resume() {
        guard wasPaused else { return }
        wasPaused = false
        DebugUtils.log("Resuming Openreplay after background")

        MessageCollector.shared.sendMessage(ORMobilePerformanceEvent(name: "background", value: UInt64(0)))

        let options = Openreplay.shared.options
        Openreplay.shared.startListeners(options: options)
        if options.screen {
            ScreenshotManager.shared.resume()
        }
        MessageCollector.shared.start()
    }

    private func setupTimers() {
        cpuTimer?.orInvalidate()
        cpuTimer = Timer.orScheduled(interval: 5) { [weak self] _ in
            self?.getCpuMessage()
        }

        memTimer?.orInvalidate()
        memTimer = Timer.orScheduled(interval: 10) { [weak self] _ in
            self?.getMemoryMessage()
        }
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
        ScreenshotManager.shared.stop()
        Crashs.shared.stop()
        Analytics.shared.pause()
        PerformanceListener.shared.stop()
        if #available(iOS 13.4, *) {
            LogsListener.shared.stop()
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

    private func stopTrackingMethods() {
        DispatchQueue.main.async {
            UIDevice.current.isBatteryMonitoringEnabled = false
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }

        for name in metricNotifications {
            NotificationCenter.default.removeObserver(self, name: name, object: nil)
        }
        cpuTimer?.orInvalidate()
        cpuTimer = nil
        memTimer?.orInvalidate()
        memTimer = nil
    }

    func stop(disableLifecycle: Bool = false) {
        if isActive {
            stopTrackingMethods()
            isActive = false
        }
        if disableLifecycle && lifecycleObserversRegistered {
            NotificationCenter.default.removeObserver(self, name: UIApplication.didEnterBackgroundNotification, object: nil)
            NotificationCenter.default.removeObserver(self, name: UIApplication.willEnterForegroundNotification, object: nil)
            lifecycleObserversRegistered = false
        }
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
