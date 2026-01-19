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
    private let messagesQueue: OperationQueue = {
       let q = OperationQueue()
       q.maxConcurrentOperationCount = 1
       q.qualityOfService = .utility
       q.name = "com.openreplay.messageCollector.queue"
       return q
   }()
    private let lateMessagesFile: URL?
    private var sendInterval: Timer?
    private var bufferTimer: Timer?
    private var catchUpTimer: Timer?
    private var tick = 0
    private let queue = DispatchQueue(label: "com.messageCollector.queue", attributes: .concurrent)

    override init() {
        lateMessagesFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("lateMessages.dat")
        super.init()
    }

    func start() {
        sendInterval = Timer.scheduledTimer(withTimeInterval: 5, repeats: true, block: { [weak self] _ in
            self?.flush()
        })
        NotificationCenter.default.addObserver(self, selector: #selector(terminate), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(terminate), name: UIApplication.willTerminateNotification, object: nil)

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
        
        self.flushMessages()
    }
    
    func stop() {
        DebugUtils.log("stopping sender")
        sendInterval?.invalidate()
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification,  object: nil)
        bufferTimer?.invalidate(); bufferTimer = nil
        catchUpTimer?.invalidate(); catchUpTimer = nil
        debounceTimer?.invalidate(); debounceTimer = nil
        self.terminate()
    }

    func sendImagesBatch(batch: Data, fileName: String) {
        messagesQueue.addOperation {
            if self.imagesWaiting.count >= 200 {
                let overflow = self.imagesWaiting.count - 199
                self.imagesWaiting.removeFirst(overflow)
            }
        self.imagesWaiting.append(BatchArch(name: fileName, data: batch))
        self.flushImages()
        }
    }

    @objc func terminate() {
        guard !sendingLastMessages else { return }
        messagesQueue.addOperation {
            self.sendingLastMessages = true
            self.flushMessages()
            self.flushImages()
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
            self.messagesQueue.addOperation {
                self.imagesSending.removeAll { waiting in images.name == waiting.name }
                guard success else {
                    self.imagesWaiting.insert(images, at: 0)
                    return
                }
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
            if !message.description.contains("Log") && !message.description.contains("NetworkCall") {
                DebugUtils.log("\(message.description)")
            }
            if let networkCallMessage = message as? ORMobileNetworkCall {
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
        if self.messagesWaiting.count >= 10_000 {
            DebugUtils.log("Message queue size exceeded, dropping message")
            return
        }
        messagesQueue.addOperation {
            self.queue.async(flags: .barrier) {
                if data.count > self.maxMessagesSize {
                    DebugUtils.log("<><><>Single message size exceeded limit")
                    return
                }
                self.messagesWaiting.append(data)
                if Openreplay.shared.bufferingMode {
                    self.messagesWaitingBackup.append(data)
                }
                let totalWaitingSize = self.messagesWaiting.reduce(0) { $0 + $1.count }
                let hardCapBytes = self.maxMessagesSize * 6 // ~3MB cap at 500KB batch size
                if totalWaitingSize > hardCapBytes {
                    var shed = 0
                    while shed < (totalWaitingSize - hardCapBytes) && !self.messagesWaiting.isEmpty {
                        shed += self.messagesWaiting.removeFirst().count
                    }
                    DebugUtils.log("Dropped \(shed) bytes from message backlog to cap memory")
                }
                if !Openreplay.shared.bufferingMode && totalWaitingSize > Int(Double(self.maxMessagesSize) * 0.8) {
                    self.flushMessages()
                }
            }
        }
    }

    private func flushMessages() {
        queue.async(flags: .barrier) {
            guard !self.messagesWaiting.isEmpty else { return }
            
            var messages = [Data]()
            var sentSize = 0
            while let message = self.messagesWaiting.first, sentSize + message.count <= self.maxMessagesSize {
                messages.append(message)
                self.messagesWaiting.remove(at: 0)
                sentSize += message.count
            }
            
            guard !messages.isEmpty else { return }
            
            var content = Data()
            let index = ORMobileBatchMeta(firstIndex: UInt64(self.nextMessageIndex))
            content.append(index.contentData())
            DebugUtils.log(index.description)
            messages.forEach { (message) in
              if !message.isEmpty {
                content.append(message)
              }
            }
            if self.sendingLastMessages, let fileUrl = self.lateMessagesFile {
                try? content.write(to: fileUrl)
            }
            self.nextMessageIndex += messages.count
            DebugUtils.log("messages batch \(content)")
            NetworkManager.shared.sendMessage(content: content) { (success) in
                guard success else {
                    DebugUtils.log("<><>re-sending failed batch<><>")
                    self.queue.async(flags: .barrier) {
                        self.messagesWaiting.insert(contentsOf: messages, at: 0)
                    }
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
}

extension Data {
    func hexString() -> String {
        return map { String(format: "%02x", $0) }.joined()
    }
}
