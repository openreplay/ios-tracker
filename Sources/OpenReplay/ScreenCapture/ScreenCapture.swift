import UIKit
import Foundation
import SwiftUI
import SWCompression

// MARK: - screenshot manager
open class ScreenshotManager {
    public static let shared = ScreenshotManager()
    private let stateLock = NSLock()
    private let messagesQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        return q
    }()

    // Off-main lane for mask compositing + JPEG encoding — only the UIKit render
    // itself must run on the main thread.
    private let processingQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        q.name = "com.openreplay.screenshots.processing"
        return q
    }()

    private var timer: Timer?
    private let maxPendingBatches = 50
    private let maxBufferedScreenshots = 500
    // Each queued operation retains a full-window UIImage (~2MB at scale 1.25 on a
    // 6.1" screen). The old synchronous path self-throttled on the main thread;
    // now that encoding is async, a slow encode must drop frames instead of
    // growing the queue without bound.
    private let maxPendingProcessing = 4

    // Weak registry: a strong array would keep sanitized views alive after their
    // screens are dismissed (leak) and scan dead entries forever.
    private let sanitizedElements = NSHashTable<AnyObject>.weakObjects()
    private var screenshots: [(Data, UInt64)] = []
    private var screenshotsBackup: [(Data, UInt64)] = []
    private var tick: UInt64 = 0
    private var bufferTimer: Timer?
    private var lastTs: UInt64 = 0
    private var firstTs: UInt64 = 0
    private var useFramesFormat = false
    // MARK: capture settings
    // should we blur out sensitive views, or place a solid box on top
    private var isBlurMode: Bool { openReplay.options.isBlur }
    private var blurRadius = 2.5
    // this affects how big the image will be compared to real phone screan.
    // we also can use default UIScreen.main.scale which is around 3.0 (dense pixel screen)
    private var screenScale = 1.25
    private var settings: (captureRate: Double, imgCompression: Double) = (captureRate: 0.33, imgCompression: 0.5)
    private var openReplay = Openreplay.shared
    
    private init() { }

    func start(startTs: UInt64, framesSupport: Bool = false) {
        firstTs = startTs
        useFramesFormat = framesSupport
        startTakingScreenshots(every: settings.captureRate)
    }

    /// Restart capture after foregrounding without resetting session timestamps,
    /// capture settings, or the negotiated archive format.
    func resume() {
        startTakingScreenshots(every: settings.captureRate)
    }
    
    func setSettings(settings: (captureRate: Double, imgCompression: Double)) {
        self.settings = settings
    }
    
    func stop() {
        timer?.orInvalidate()
        timer = nil
        bufferTimer?.orInvalidate()
        bufferTimer = nil
        stateLock.lock()
        lastTs = 0
        screenshots.removeAll()
        screenshotsBackup.removeAll()
        stateLock.unlock()
    }
    
    func startTakingScreenshots(every interval: TimeInterval) {
        takeScreenshot()

        timer?.orInvalidate()
        timer = Timer.orScheduled(interval: interval) { [weak self] _ in
            self?.takeScreenshot()
        }
    }

    public func addSanitizedElement(_ element: Sanitizable) {
        if (openReplay.options.debugLogs) {
            DebugUtils.log("addSanitizedElement")
        }
        sanitizedElements.add(element)
    }

    public func removeSanitizedElement(_ element: Sanitizable) {
        if (openReplay.options.debugLogs) {
            DebugUtils.log("removeSanitizedElement")
        }
        sanitizedElements.remove(element)
    }

    // Modern replacement for the deprecated UIApplication.shared.windows —
    // resolves the key window of the active scene (correct on multi-window iPad).
    private static func keyWindow() -> UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }

    // MARK: - UI Capturing
    func takeScreenshot() {
        guard let window = Self.keyWindow() else { return }
        let size = window.frame.size
        guard size.width > 0 && size.height > 0 else { return }

        // Drop this frame rather than render one we can't keep up with encoding.
        guard processingQueue.operationCount < maxPendingProcessing else {
            DebugUtils.log("Dropping screenshot: encoder backlog")
            return
        }

        // Pass 1 — main thread (UIKit requirement): render the window once.
        let format = UIGraphicsImageRendererFormat()
        format.scale = screenScale
        format.opaque = true
        let base = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
        }

        // View geometry is main-thread-only: snapshot the sanitized frames here.
        let maskFrames = sanitizedElements.allObjects.compactMap { ($0 as? Sanitizable)?.frameInWindow }

        let ts = UInt64(Date().timeIntervalSince1970 * 1000)
        let compression = settings.imgCompression
        let blurMode = isBlurMode
        let debugImages = openReplay.options.debugImages

        // Pass 2 — background: compositing and JPEG encoding are the expensive
        // parts and don't need UIKit, so they stay off the main thread.
        processingQueue.addOperation { [weak self] in
            guard let self = self else { return }
            autoreleasepool {
                let finalImage = self.applyMasks(to: base, frames: maskFrames, blurMode: blurMode, debugImages: debugImages)
                guard let compressedData = finalImage.jpegData(compressionQuality: compression) else { return }

                self.stateLock.lock()
                if (self.openReplay.bufferingMode) {
                    self.screenshotsBackup.append((compressedData, ts))
                }
                self.screenshots.append((compressedData, ts))
                self.enforceScreenshotCaps()
                let shouldSend = !self.openReplay.bufferingMode &&
                    self.screenshots.count >= self.openReplay.options.screenshotBatchSize.rawValue
                self.stateLock.unlock()
                if shouldSend {
                    self.sendScreenshots()
                }
            }
        }
    }

    private func applyMasks(to base: UIImage, frames: [CGRect], blurMode: Bool, debugImages: Bool) -> UIImage {
        guard !frames.isEmpty else { return base }

        let format = UIGraphicsImageRendererFormat()
        format.scale = base.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: base.size, format: format).image { ctx in
            base.draw(at: .zero)
            let context = ctx.cgContext

            if blurMode {
                let stripeWidth: CGFloat = 5.0
                let stripeSpacing: CGFloat = 15.0
                let stripeColor: UIColor = .gray.withAlphaComponent(0.7)

                for frame in frames {
                    // cgImage coordinates are in pixels, frames are in points
                    let cropFrame = CGRect(
                        x: frame.origin.x * base.scale,
                        y: frame.origin.y * base.scale,
                        width: frame.size.width * base.scale,
                        height: frame.size.height * base.scale
                    )
                    if let regionImage = base.cgImage?.cropping(to: cropFrame) {
                        let imageToBlur = UIImage(cgImage: regionImage, scale: base.scale, orientation: .up)
                        imageToBlur.applyBlurWithRadius(blurRadius)?.draw(in: frame)
                    }

                    context.saveGState()
                    context.clip(to: frame)

                    // Draw diagonal lines within the clipped region
                    let totalWidth = frame.size.width
                    let totalHeight = frame.size.height
                    for x in stride(from: -totalHeight, to: totalWidth, by: stripeSpacing + stripeWidth) {
                        context.move(to: CGPoint(x: x + frame.minX, y: frame.minY))
                        context.addLine(to: CGPoint(x: x + totalHeight + frame.minX, y: totalHeight + frame.minY))
                    }

                    context.setLineWidth(stripeWidth)
                    stripeColor.setStroke()
                    context.strokePath()
                    context.restoreGState()

                    if debugImages {
                        context.setStrokeColor(UIColor.black.cgColor)
                        context.setLineWidth(1)
                        context.stroke(frame)
                    }
                }
            } else {
                context.setFillColor(UIColor.blue.cgColor)
                frames.forEach { context.fill($0) }
            }
        }
    }
    
    private func enforceScreenshotCaps() {
        if screenshots.count > maxBufferedScreenshots {
            screenshots.removeFirst(screenshots.count - maxBufferedScreenshots)
        }
        if screenshotsBackup.count > maxBufferedScreenshots {
            screenshotsBackup.removeFirst(screenshotsBackup.count - maxBufferedScreenshots)
        }
    }
    
    func cycleBuffer() {
        bufferTimer?.orInvalidate()
        bufferTimer = Timer.orScheduled(interval: 30) { [weak self] _ in
            guard let self = self else { return }
            if Openreplay.shared.bufferingMode {
                self.stateLock.lock()
                let currTick = self.tick
                if (currTick % 2 == 0) {
                    self.screenshots.removeAll()
                } else {
                    self.screenshotsBackup.removeAll()
                }
                self.tick += 1
                self.stateLock.unlock()
            }
        }
    }

    func syncBuffers() {
        stateLock.lock()
        let buf1 = self.screenshots.count
        let buf2 = self.screenshotsBackup.count
        self.tick = 0

        if buf1 > buf2 {
            self.screenshotsBackup.removeAll()
        } else {
            self.screenshots = self.screenshotsBackup
            self.screenshotsBackup.removeAll()
        }
        stateLock.unlock()

        bufferTimer?.orInvalidate()
        bufferTimer = nil

        self.sendScreenshots()
    }

    // MARK: - sending screenshots
    func sendScreenshots() {
        guard let sessionId = NetworkManager.shared.sessionId else {
            return
        }
        if messagesQueue.operationCount > maxPendingBatches {
            DebugUtils.log("Dropping screenshot batch due to backlog")
            return
        }
        
        stateLock.lock()
        let images = screenshots
        screenshots.removeAll()
        let firstTsSnapshot = self.firstTs
        let lastTsSnapshot = self.lastTs
        let framesFormat = self.useFramesFormat
        stateLock.unlock()
        
        var archiveName = ""
    
        messagesQueue.addOperation {
            if self.messagesQueue.operationCount > self.maxPendingBatches {
                DebugUtils.log("Dropping screenshot batch due to backlog")
                return
            }
            if framesFormat {
                archiveName = "\(sessionId)-\(lastTsSnapshot).gz"
                // New binary format: [uint64 LE timestamp][uint32 LE size][data]...
                var binaryData = Data()
                var newLastTs = lastTsSnapshot
                
                for imageData in images {
                    let timestamp = imageData.1
                    let imageBytes = imageData.0
                    let size = UInt32(imageBytes.count)
                    
                    binaryData.appendUInt64LE(timestamp)
                    binaryData.appendUInt32LE(size)
                    binaryData.append(imageBytes)
                    
                    newLastTs = timestamp
                }
                do {
                    let gzData = try GzipArchive.archive(data: binaryData)
                    
                    MessageCollector.shared.sendImagesBatch(batch: gzData, fileName: archiveName)
                    self.stateLock.lock()
                    self.lastTs = newLastTs
                    self.stateLock.unlock()
                } catch {
                    DebugUtils.log("Error creating frames format archive: \(error)")
                }
            } else {
                // Old tar format: separate .jpeg files
                archiveName = "\(sessionId)-\(lastTsSnapshot).tar.gz"
                var entries: [TarEntry] = []
                var newLastTs = lastTsSnapshot
                for imageData in images {
                    let filename = "\(firstTsSnapshot)_1_\(imageData.1).jpeg"
                    var tarEntry = TarContainer.Entry(info: .init(name: filename, type: .regular), data: imageData.0)
                    tarEntry.info.permissions = Permissions(rawValue: 420)
                    tarEntry.info.creationTime = Date()
                    tarEntry.info.modificationTime = Date()
                    
                    entries.append(tarEntry)
                    newLastTs = imageData.1
                }
                do {
                    let gzData = try GzipArchive.archive(data: TarContainer.create(from: entries))
                    MessageCollector.shared.sendImagesBatch(batch: gzData, fileName: archiveName)
                    self.stateLock.lock()
                    self.lastTs = newLastTs
                    self.stateLock.unlock()
                } catch {
                    DebugUtils.log("Error writing tar.gz data: \(error)")
                }
            }
        }
    }
    
    
    }

// MARK: making extensions for UI
struct SensitiveViewWrapperRepresentable: UIViewRepresentable {
    @Binding var viewWrapper: SensitiveViewWrapper?

    func makeUIView(context: Context) -> SensitiveViewWrapper {
        let wrapper = SensitiveViewWrapper()
        viewWrapper = wrapper
        return wrapper
    }

    func updateUIView(_ uiView: SensitiveViewWrapper, context: Context) { }
}

struct SensitiveModifier: ViewModifier {
    @State private var viewWrapper: SensitiveViewWrapper?

    func body(content: Content) -> some View {
        content
            .background(SensitiveViewWrapperRepresentable(viewWrapper: $viewWrapper))
    }
}

public extension View {
    func sensitive() -> some View {
        self.modifier(SensitiveModifier())
    }
}

class SensitiveViewWrapper: UIView {
    override func didMoveToSuperview() {
        super.didMoveToSuperview()
        if self.superview != nil {
            ScreenshotManager.shared.addSanitizedElement(self)
        } else {
            ScreenshotManager.shared.removeSanitizedElement(self)
        }
    }
}

class SensitiveTextField: UITextField {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if self.window != nil {
            ScreenshotManager.shared.addSanitizedElement(self)
        } else {
            ScreenshotManager.shared.removeSanitizedElement(self)
        }
    }
}

// Protocol to make a UIView sanitizable.
// Class-bound so registered elements can be held weakly.
public protocol Sanitizable: AnyObject {
    var frameInWindow: CGRect? { get }
}

// MARK: - Binary Data Helpers
extension Data {
    mutating func appendUInt64LE(_ value: UInt64) {
        var val = value.littleEndian
        Swift.withUnsafeBytes(of: &val) { self.append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var val = value.littleEndian
        Swift.withUnsafeBytes(of: &val) { self.append(contentsOf: $0) }
    }
}

