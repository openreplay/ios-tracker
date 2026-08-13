import Foundation

extension Timer {
    /// Schedules a timer on the main run loop in `.common` mode so it keeps firing
    /// while the user is scrolling (`.default`-mode timers pause during touch tracking).
    /// Tolerance lets the OS coalesce wakeups to save battery.
    @discardableResult
    static func orScheduled(interval: TimeInterval, repeats: Bool = true, block: @escaping (Timer) -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats, block: block)
        timer.tolerance = interval * 0.1
        if Thread.isMainThread {
            RunLoop.main.add(timer, forMode: .common)
        } else {
            DispatchQueue.main.async {
                RunLoop.main.add(timer, forMode: .common)
            }
        }
        return timer
    }

    /// Timers from `orScheduled` live on the main run loop; `invalidate()` must be
    /// called from that run loop's thread or the timer may keep firing / crash.
    /// Public `stop()` entry points are reachable from any thread, so hop.
    func orInvalidate() {
        if Thread.isMainThread {
            invalidate()
        } else {
            DispatchQueue.main.async { self.invalidate() }
        }
    }
}
