import UIKit
import ObjectiveC

private var viewCounter = 0
private enum UIViewIdStore {
    static let lock = NSLock()
    static var counter = 0
}
private var associatedIdKey: UInt8 = 0

extension UIView: Sanitizable {
    public var identifier: String {
        if let existing = objc_getAssociatedObject(self, &associatedIdKey) as? String { return existing }
            UIViewIdStore.lock.lock(); defer { UIViewIdStore.lock.unlock() }
            let shortId = "\(UIViewIdStore.counter)"
            UIViewIdStore.counter += 1
            objc_setAssociatedObject(self, &associatedIdKey, shortId, .OBJC_ASSOCIATION_COPY_NONATOMIC)
            return shortId
    }

    public var longIdentifier: String {
        return String(describing: type(of: self)) + "-" + Unmanaged.passUnretained(self).toOpaque().debugDescription
    }
    
    public var frameInWindow: CGRect? {
        return self.window == nil ? nil : self.convert(self.bounds, to: self.window)
    }
}

