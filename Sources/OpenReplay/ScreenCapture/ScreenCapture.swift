import UIKit
import Foundation
import SwiftUI
import SWCompression

// MARK: - screenshot manager
open class ScreenshotManager {
    public static let shared = ScreenshotManager()
    private let messagesQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        return q
    }()

    private var timer: Timer?
    private var sendTimer: Timer?
    private let maxPendingBatches = 50
    private let maxBufferedScreenshots = 500

    private var sanitizedElements: [Sanitizable] = []
    private var observedInputs: [UITextField] = []
    private var screenshots: [(Data, UInt64)] = []
    private var screenshotsBackup: [(Data, UInt64)] = []
    private var tick: UInt64 = 0
    private var bufferTimer: Timer?
    private var lastTs: UInt64 = 0
    private var firstTs: UInt64 = 0
    // MARK: capture settings
    // should we blur out sensitive views, or place a solid box on top
    private var isBlurMode = true
    private var blurRadius = 2.5
    // this affects how big the image will be compared to real phone screan.
    // we also can use default UIScreen.main.scale which is around 3.0 (dense pixel screen)
    private var screenScale = 1.25
    private var settings: (captureRate: Double, imgCompression: Double) = (captureRate: 0.33, imgCompression: 0.5)
    private var openReplay = Openreplay.shared
    
    private init() { }

    func start(startTs: UInt64) {
        firstTs = startTs
        startTakingScreenshots(every: settings.captureRate)
    }
    
    func setSettings(settings: (captureRate: Double, imgCompression: Double)) {
        self.settings = settings
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        bufferTimer?.invalidate()
        bufferTimer = nil
        lastTs = 0
        screenshots.removeAll()
        screenshotsBackup.removeAll()
    }
    
    func startTakingScreenshots(every interval: TimeInterval) {
        takeScreenshot()
        
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.takeScreenshot()
        }
    }

    public func addSanitizedElement(_ element: Sanitizable) {
        if (openReplay.options.debugLogs) {
            DebugUtils.log("addSanitizedElement")
        }
        sanitizedElements.append(element)
    }

    public func removeSanitizedElement(_ element: Sanitizable) {
        if (openReplay.options.debugLogs) {
            DebugUtils.log("removeSanitizedElement")
        }
        sanitizedElements.removeAll { $0 as AnyObject === element as AnyObject }
    }

    // MARK: - UI Capturing
    func takeScreenshot() {
        autoreleasepool {
            guard let window = UIApplication.shared.windows.first(where: { $0.isKeyWindow }) else { return }
            let size = window.frame.size
            
            guard size != .zero else { return }
            UIGraphicsBeginImageContextWithOptions(size, false, screenScale)
            guard let context = UIGraphicsGetCurrentContext() else { UIGraphicsEndImageContext(); return }
            
            // Rendering current window in custom context
            // 2nd option looks to be more precise
            //      window?.layer.render(in: context)
            //         #warning("Can slow down the app depending on complexity of the UI tree")
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: false)
            
            // MARK: sanitize
            // Sanitizing sensitive elements
            if isBlurMode {
                let stripeWidth: CGFloat = 5.0
                let stripeSpacing: CGFloat = 15.0
                let stripeColor: UIColor = .gray.withAlphaComponent(0.7)
                
                for element in sanitizedElements {
                    if let frame = element.frameInWindow {
                        let totalWidth = frame.size.width
                        let totalHeight = frame.size.height
                        let convertedFrame = CGRect(
                            x: frame.origin.x,
                            y: frame.origin.y,
                            width: frame.size.width,
                            height: frame.size.height
                        )
                        let cropFrame = CGRect(
                            x: frame.origin.x * screenScale,
                            y: frame.origin.y * screenScale,
                            width: frame.size.width * screenScale,
                            height: frame.size.height * screenScale
                        )
                        if let regionImage = UIGraphicsGetImageFromCurrentImageContext()?.cgImage?.cropping(to: cropFrame) {
                            let imageToBlur = UIImage(cgImage: regionImage, scale: screenScale, orientation: .up)
                            let blurredImage = imageToBlur.applyBlurWithRadius(blurRadius)
                            blurredImage?.draw(in: convertedFrame)
                            
                            context.saveGState()
                            UIRectClip(convertedFrame)
                            
                            // Draw diagonal lines within the clipped region
                            for x in stride(from: -totalHeight, to: totalWidth, by: stripeSpacing + stripeWidth) {
                                context.move(to: CGPoint(x: x + convertedFrame.minX, y: convertedFrame.minY))
                                context.addLine(to: CGPoint(x: x + totalHeight + convertedFrame.minX, y: totalHeight + convertedFrame.minY))
                            }
                            
                            context.setLineWidth(stripeWidth)
                            stripeColor.setStroke()
                            context.strokePath()
                            context.restoreGState()
                            
                            if (openReplay.options.debugImages) {
                                context.setStrokeColor(UIColor.black.cgColor)
                                context.setLineWidth(1)
                                context.stroke(convertedFrame)
                            }
                        }
                    } else {
                        removeSanitizedElement(element)
                    }
                }
            } else {
                context.setFillColor(UIColor.blue.cgColor)
                for element in sanitizedElements {
                    if let frame = element.frameInWindow {
                        context.fill(frame)
                    }
                }
            }
            
            // Get the resulting image
            if let image = UIGraphicsGetImageFromCurrentImageContext() {
                if let compressedData = image.jpegData(compressionQuality: self.settings.imgCompression) {
                    if (openReplay.bufferingMode) {
                        self.screenshotsBackup.append((compressedData, UInt64(Date().timeIntervalSince1970 * 1000)))
                    }
                    screenshots.append((compressedData, UInt64(Date().timeIntervalSince1970 * 1000)))
                    self.enforceScreenshotCaps()
                    if !openReplay.bufferingMode && screenshots.count >= openReplay.options.screenshotBatchSize.rawValue {
                        self.sendScreenshots()
                    }
                }
            }
            UIGraphicsEndImageContext()
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
        bufferTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true, block: { [weak self] _ in
            if Openreplay.shared.bufferingMode {
                let currTick = self?.tick ?? 0
                if (currTick % 2 == 0) {
                    self?.screenshots.removeAll()
                } else {
                    self?.screenshotsBackup.removeAll()
                }
                self?.tick += 1
            }
        })
    }

    func syncBuffers() {
        let buf1 = self.screenshots.count
        let buf2 = self.screenshotsBackup.count
        self.tick = 0
        bufferTimer?.invalidate()
        bufferTimer = nil

        if buf1 > buf2 {
            self.screenshotsBackup.removeAll()
        } else {
            self.screenshots = self.screenshotsBackup
            self.screenshotsBackup.removeAll()
        }
        
        self.sendScreenshots()
    }

    func saveScreenshotsLocally() {
        guard let sessionId = NetworkManager.shared.sessionId else {
            return
        }
        let archiveName = "\(sessionId)-\(self.lastTs).tar.gz"
        let localFilePath = "/Users/nikitamelnikov/Desktop/session/"
        let desktopURL = URL(fileURLWithPath: localFilePath)
        let archiveURL = desktopURL.appendingPathComponent(archiveName)

        // Ensure the directory exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: localFilePath) {
            try? fileManager.createDirectory(at: desktopURL, withIntermediateDirectories: true, attributes: nil)
        }
        var combinedData = Data()
        let images = screenshots
        for (_, imageData) in screenshots.enumerated() {
            combinedData.append(imageData.0)
            if (Openreplay.shared.options.debugImages) {
                let filename = "sessSt_1_\(imageData.1).jpeg"
                let fileURL = desktopURL.appendingPathComponent(filename)
                
                do {
                    try imageData.0.write(to: fileURL)
                } catch {
                    DebugUtils.log("Unexpected error: \(error).")
                }
            }
        }
        if (Openreplay.shared.options.debugLogs) {
            DebugUtils.log("saved image files in \(localFilePath)")
        }
    
        messagesQueue.addOperation {
            var entries: [TarEntry] = []
            for imageData in images {
                let filename = "\(self.firstTs)_1_\(imageData.1).jpeg"
                var tarEntry = TarContainer.Entry(info: .init(name: filename, type: .regular), data: imageData.0)
                tarEntry.info.permissions = Permissions(rawValue: 420)
                tarEntry.info.creationTime = Date()
                tarEntry.info.modificationTime = Date()
                
                entries.append(tarEntry)
                self.lastTs = imageData.1
            }
            do {
                let gzData = try GzipArchive.archive(data: TarContainer.create(from: entries))
                
                if (Openreplay.shared.options.debugImages) {
                    try gzData.write(to: archiveURL)
                    DebugUtils.log("Archive saved to \(archiveURL.path)")
                    MessageCollector.shared.sendImagesBatch(batch: gzData, fileName: archiveName)
                } else {
                    MessageCollector.shared.sendImagesBatch(batch: gzData, fileName: archiveName)
                }
            } catch {
                DebugUtils.log("Error writing tar.gz data: \(error)")
            }
        }
        screenshots.removeAll()
    }

    // MARK: - sending screenshots
    func sendScreenshots() {
        guard let sessionId = NetworkManager.shared.sessionId else {
            return
        }
        let archiveName = "\(sessionId)-\(self.lastTs).tar.gz"
    
        let images = screenshots
        messagesQueue.addOperation {
            if self.messagesQueue.operationCount > self.maxPendingBatches {
                DebugUtils.log("Dropping screenshot batch due to backlog")
                return
            }
            var entries: [TarEntry] = []
            for imageData in images {
                let filename = "\(self.firstTs)_1_\(imageData.1).jpeg"
                var tarEntry = TarContainer.Entry(info: .init(name: filename, type: .regular), data: imageData.0)
                tarEntry.info.permissions = Permissions(rawValue: 420)
                tarEntry.info.creationTime = Date()
                tarEntry.info.modificationTime = Date()
                
                entries.append(tarEntry)
                self.lastTs = imageData.1
            }
            do {
                let gzData = try GzipArchive.archive(data: TarContainer.create(from: entries))
                MessageCollector.shared.sendImagesBatch(batch: gzData, fileName: archiveName)
            } catch {
                DebugUtils.log("Error writing tar.gz data: \(error)")
            }
        }
        screenshots.removeAll()
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

// Protocol to make a UIView sanitizable
public protocol Sanitizable {
    var frameInWindow: CGRect? { get }
}


func getCaptureSettings(for quality: RecordingQuality) -> (captureRate: Double, imgCompression: Double) {
    switch quality {
    case .Low:
        return (captureRate: 1, imgCompression: 0.4)
    case .Standard:
        return (captureRate: 0.33, imgCompression: 0.5)
    case .High:
        return (captureRate: 0.20, imgCompression: 0.55)
    }
}
