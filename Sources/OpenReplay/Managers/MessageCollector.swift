import UIKit

struct BatchArch {
    var name: String
    var data: Data
}

class MessageCollector: NSObject {
    public static let shared = MessageCollector()
    private var imagesWaiting = [BatchArch]()
    private var imagesSending = [BatchArch]()
    private var messagesWaiting: [Data] = []
    private var messagesWaitingBackup: [Data] = []
    private var nextMessageIndex = 0
    private var sendingLastMessages = false
    private let maxMessagesSize = 500_000
    private let messagesQueue = OperationQueue()
    private let lateMessagesFile: URL?
    private var sendInterval: Timer?
    private var bufferTimer: Timer?
    private var catchUpTimer: Timer?
    private var tick = 0
    
    override init() {
        lateMessagesFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("/lateMessages.dat")
        super.init()
    }

    func start() {
        sendInterval = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { [weak self] _ in
            self?.flush()
        })
        NotificationCenter.default.addObserver(self, selector: #selector(terminate), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(terminate), name: UIApplication.willTerminateNotification, object: nil)
        messagesQueue.maxConcurrentOperationCount = 1

        if let fileUrl = lateMessagesFile,
           FileManager.default.fileExists(atPath: fileUrl.path),
           let lateData = try? Data(contentsOf: fileUrl) {
            NetworkManager.shared.sendLateMessage(content: lateData) { (success) in
                guard success else { return }
                try? FileManager.default.removeItem(at: fileUrl)
            }
        }
    }

    func cycleBuffer() {
        bufferTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true, block: { [weak self] _ in
            if (self == nil) {
                return
            }
            Openreplay.shared.sessionStartTs = UInt64(Date().timeIntervalSince1970 * 1000)
            if Openreplay.shared.bufferingMode {
                let currTick = self?.tick ?? 0
                if (currTick % 2 == 0) {
                    self?.messagesWaiting = []
                } else {
                    self?.messagesWaitingBackup = []
                }
                self?.tick += 1
            }
        })
    }

    func syncBuffers() {
        let buf1 = self.messagesWaiting.count
        let buf2 = self.messagesWaitingBackup.count
        self.tick = 0
        bufferTimer?.invalidate()
        bufferTimer = nil

        if buf1 > buf2 {
            self.messagesWaitingBackup.removeAll()
        } else {
            self.messagesWaiting = self.messagesWaitingBackup
            self.messagesWaitingBackup.removeAll()
        }
        
        catchUpTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true, block: { [weak self] _ in
            let isEmpty = self?.messagesWaiting.isEmpty ?? true
            if isEmpty {
                self?.catchUpTimer?.invalidate()
                return
            }
            
            self?.flushMessages()
        })
        
    }
    
    func stop() {
        sendInterval?.invalidate()
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification,  object: nil)
        self.terminate()
    }

    func sendImagesBatch(batch: Data, fileName: String) {
        self.imagesWaiting.append(BatchArch(name: fileName, data: batch))
        messagesQueue.addOperation {
            self.flushImages()
        }
    }

    @objc func terminate() {
        guard !sendingLastMessages else { return }
        messagesQueue.addOperation {
            self.sendingLastMessages = true
            self.flushMessages()
        }
    }

    @objc func flush() {
        messagesQueue.addOperation {
            self.flushMessages()
            self.flushImages()
        }
    }

    private func flushImages() {
        let images = imagesWaiting.first
        guard !imagesWaiting.isEmpty, let images = images, let projectKey = Openreplay.shared.projectKey else { return }
        imagesWaiting.remove(at: 0)
        
        imagesSending.append(images)

        DebugUtils.log("Sending images \(images.name) \(images.data.count)")
        NetworkManager.shared.sendImages(projectKey: projectKey, images: images.data, name: images.name) { (success) in
            self.imagesSending.removeAll { (waiting) -> Bool in
                images.name == waiting.name
            }
            guard success else {
                self.imagesWaiting.append(images)
                return
            }
        }
    }

    func sendMessage(_ message: ORMessage) {
        if Openreplay.shared.bufferingMode {
            if let trigger = ConditionsManager.shared.processMessage(msg: message) {
                Openreplay.shared.triggerRecording(condition: trigger)
            }
        }
        let data = message.contentData()
        if (Openreplay.shared.options.debugLogs) {
            if !message.description.contains("IOSLog") && !message.description.contains("IOSNetworkCall") {
//                DebugUtils.log(message.description)
            }
            if let networkCallMessage = message as? ORIOSNetworkCall {
                DebugUtils.log("-->> IOSNetworkCall(105): \(networkCallMessage.method) \(networkCallMessage.URL)")
            }
        }
        self.sendRawMessage(data)
    }
    
    private var debounceTimer: Timer?
    private var debouncedMessage: ORMessage?
    func sendDebouncedMessage(_ message: ORMessage) {
        debounceTimer?.invalidate()

        debouncedMessage = message
        debounceTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { [weak self] _ in
            if let debouncedMessage = self?.debouncedMessage {
                self?.sendMessage(debouncedMessage)
                self?.debouncedMessage = nil
            }
        }
    }

    func sendRawMessage(_ data: Data) {
        messagesQueue.addOperation {
            if data.count > self.maxMessagesSize {
                DebugUtils.log("<><><>Single message size exceeded limit")
                return
            }
            self.messagesWaiting.append(data)
            if Openreplay.shared.bufferingMode {
                self.messagesWaitingBackup.append(data)
            }
            var totalWaitingSize = 0
            self.messagesWaiting.forEach { totalWaitingSize += $0.count }
            if !Openreplay.shared.bufferingMode && totalWaitingSize > Int(Double(self.maxMessagesSize) * 0.8) {
                self.flushMessages()
            }
        }
    }

    private func flushMessages() {
        var messages = [Data]()
        var sentSize = 0
        while let message = messagesWaiting.first, sentSize + message.count <= maxMessagesSize {
            messages.append(message)
            messagesWaiting.remove(at: 0)
            sentSize += message.count
        }
        guard !messages.isEmpty else { return }
        var content = Data()
        let index = ORIOSBatchMeta(firstIndex: UInt64(nextMessageIndex))
        content.append(index.contentData())
        DebugUtils.log(index.description)
        messages.forEach { (message) in
            content.append(message)
        }
        if sendingLastMessages, let fileUrl = lateMessagesFile {
            try? content.write(to: fileUrl)
        }
        nextMessageIndex += messages.count
        DebugUtils.log("messages batch \(content)")
        NetworkManager.shared.sendMessage(content: content) { (success) in
            guard success else {
                DebugUtils.log("<><>re-sending failed batch<><>")
                self.messagesWaiting.insert(contentsOf: messages, at: 0)
                return
            }
            if self.sendingLastMessages {
                self.sendingLastMessages = false
                if let fileUrl = self.lateMessagesFile, FileManager.default.fileExists(atPath: fileUrl.path) {
                    try? FileManager.default.removeItem(at: fileUrl)
                }
            }
        }
    }
}
