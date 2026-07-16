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
    // Running total of messagesWaiting bytes — recomputing with reduce() on
    // every append would make message ingestion O(n²).
    private var waitingBytes = 0
    // Single serial queue owning ALL collector state. The previous mix of a
    // serial OperationQueue nested inside a concurrent barrier queue created two
    // competing mutual-exclusion domains and data races (sendingLastMessages).
    private let workQueue = DispatchQueue(label: "com.openreplay.messageCollector", qos: .utility)
    private let lateMessagesFile: URL?
    private var sendInterval: Timer?
    private var bufferTimer: Timer?
    private var tick = 0

    override init() {
        lateMessagesFile = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("lateMessages.dat")
        super.init()
    }

    func start() {
        sendInterval?.orInvalidate()
        sendInterval = Timer.orScheduled(interval: 5) { [weak self] _ in
            self?.flush()
        }
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
        bufferTimer?.orInvalidate()
        bufferTimer = Timer.orScheduled(interval: 30) { [weak self] _ in
            guard let self = self else { return }
            Openreplay.shared.sessionStartTs = UInt64(Date().timeIntervalSince1970 * 1000)
            if Openreplay.shared.bufferingMode {
                self.workQueue.async {
                    if (self.tick % 2 == 0) {
                        self.messagesWaiting = []
                        self.waitingBytes = 0
                    } else {
                        self.messagesWaitingBackup = []
                    }
                    self.tick += 1
                }
            }
        }
    }

    func syncBuffers() {
        bufferTimer?.orInvalidate()
        bufferTimer = nil

        workQueue.async {
            let buf1 = self.messagesWaiting.count
            let buf2 = self.messagesWaitingBackup.count
            self.tick = 0

            if buf1 > buf2 {
                self.messagesWaitingBackup.removeAll()
            } else {
                self.messagesWaiting = self.messagesWaitingBackup
                self.messagesWaitingBackup.removeAll()
            }
            self.waitingBytes = self.messagesWaiting.reduce(0) { $0 + $1.count }

            self.flushMessagesOnQueue()
        }
    }

    func stop() {
        DebugUtils.log("stopping sender")
        sendInterval?.orInvalidate(); sendInterval = nil
        NotificationCenter.default.removeObserver(self, name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: UIApplication.willTerminateNotification,  object: nil)
        bufferTimer?.orInvalidate(); bufferTimer = nil
        debounceTimer?.orInvalidate(); debounceTimer = nil
        self.terminate()
    }

    func sendImagesBatch(batch: Data, fileName: String) {
        workQueue.async {
            if self.imagesWaiting.count >= 200 {
                self.imagesWaiting.removeFirst(self.imagesWaiting.count - 199)
            }
            self.imagesWaiting.append(BatchArch(name: fileName, data: batch))
            self.flushImagesOnQueue()
        }
    }

    @objc func terminate() {
        workQueue.async {
            guard !self.sendingLastMessages else { return }
            self.sendingLastMessages = true
            self.flushMessagesOnQueue()
            self.flushImagesOnQueue()
        }
    }

    @objc func flush() {
        workQueue.async {
            self.flushMessagesOnQueue()
            self.flushImagesOnQueue()
        }
    }

    /// Must be called on workQueue.
    private func flushImagesOnQueue() {
        guard let images = imagesWaiting.first, let projectKey = Openreplay.shared.projectKey else { return }
        imagesWaiting.removeFirst()
        imagesSending.append(images)

        DebugUtils.log("Sending images \(images.name) \(images.data.count)")
        NetworkManager.shared.sendImages(projectKey: projectKey, images: images.data, name: images.name) { (success, shouldRetry) in
            self.workQueue.async {
                self.imagesSending.removeAll { waiting in images.name == waiting.name }
                guard success else {
                    if shouldRetry {
                        self.imagesWaiting.insert(images, at: 0)
                    } else {
                        DebugUtils.error("Dropping image batch \(images.name) after permanent server rejection")
                    }
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
        debounceTimer?.orInvalidate()

        debouncedMessage = message
        debounceTimer = Timer.orScheduled(interval: 2.0, repeats: false) { [weak self] _ in
            if let debouncedMessage = self?.debouncedMessage {
                self?.sendMessage(debouncedMessage)
                self?.debouncedMessage = nil
            }
        }
    }

    func sendRawMessage(_ data: Data) {
        workQueue.async {
            if self.messagesWaiting.count >= 10_000 {
                DebugUtils.log("Message queue size exceeded, dropping message")
                return
            }
            if data.count > self.maxMessagesSize {
                DebugUtils.log("<><><>Single message size exceeded limit")
                return
            }
            self.messagesWaiting.append(data)
            self.waitingBytes += data.count
            if Openreplay.shared.bufferingMode {
                self.messagesWaitingBackup.append(data)
            }
            let hardCapBytes = self.maxMessagesSize * 6 // ~3MB cap at 500KB batch size
            if self.waitingBytes > hardCapBytes {
                var shed = 0
                while self.waitingBytes > hardCapBytes && !self.messagesWaiting.isEmpty {
                    let removed = self.messagesWaiting.removeFirst().count
                    shed += removed
                    self.waitingBytes -= removed
                }
                DebugUtils.log("Dropped \(shed) bytes from message backlog to cap memory")
            }
            if !Openreplay.shared.bufferingMode && self.waitingBytes > Int(Double(self.maxMessagesSize) * 0.8) {
                self.flushMessagesOnQueue()
            }
        }
    }

    private func isReplay(_ data: Data) -> Bool {
        // orReplayerMessageTypes is generated from the :replayer flags in messages.rb.
        // Unknown/undecodable type falls back to analytics so it can't corrupt the player timeline.
        guard let type = data.peekMessageType() else { return false }
        return orReplayerMessageTypes.contains(type)
    }

    /// Must be called on workQueue.
    private func flushMessagesOnQueue() {
        guard !self.messagesWaiting.isEmpty else {
            // Nothing left to persist, so a terminate pass over an empty queue is
            // already complete — don't leave the flag latched.
            self.sendingLastMessages = false
            return
        }

        var messages = [Data]()
        var sentSize = 0
        while let message = self.messagesWaiting.first, sentSize + message.count <= self.maxMessagesSize {
            messages.append(message)
            self.messagesWaiting.removeFirst()
            self.waitingBytes -= message.count
            sentSize += message.count
        }

        guard !messages.isEmpty else { return }

        // Group into replay (player, saved to mob file) and analytics (not saved).
        let playerMessages = messages.filter { self.isReplay($0) }
        let analyticsMessages = messages.filter { !self.isReplay($0) }

        let batchMeta = ORMobileBatchMeta(firstIndex: UInt64(self.nextMessageIndex))

        // Every batch uses the split layout: [batchMeta][player][analytics]. Reuse the
        // BatchMeta Length field to carry the absolute byte offset where the analytics part
        // starts; backend writes [0, offset) to the mob file and pushes [offset, end) to the
        // DB. firstIndex follows as a bare trailing varint (backend special-cases type 107).
        //   player-only    -> offset == whole batch  (everything to the mob file)
        //   analytics-only -> offset == batchMeta size (nothing to the mob file)
        //   mixed          -> offset == end of the player region
        let typeBytes = Data(value: UInt64(107))
        let tsBytes = Data(value: batchMeta.timestamp)
        let firstIndexBytes = Data(value: batchMeta.firstIndex)
        let playerBytes = playerMessages.reduce(0) { $0 + $1.count }
        // offset includes the varint of offset itself (header is part of the file region),
        // so resolve the self-reference by fixpoint — converges in <=2 steps.
        let base = typeBytes.count + tsBytes.count + firstIndexBytes.count + playerBytes
        var offset = base + Data(value: UInt64(base)).count
        for _ in 0..<10 {
            let cand = base + Data(value: UInt64(offset)).count
            if cand == offset { break }
            offset = cand
        }

        var content = Data()
        content.append(typeBytes)
        content.append(tsBytes)
        content.append(Data(value: UInt64(offset)))   // Length field = analytics offset
        content.append(firstIndexBytes)                // firstIndex, bare trailing varint
        playerMessages.forEach { if !$0.isEmpty { content.append($0) } }
        analyticsMessages.forEach { if !$0.isEmpty { content.append($0) } }
        DebugUtils.log("split batch offset=\(offset) player=\(playerMessages.count) analytics=\(analyticsMessages.count) bytes=\(content.count)")

        // Crash/late backup keeps the plain single-BatchMeta format.
        if self.sendingLastMessages, let fileUrl = self.lateMessagesFile {
            var flat = Data()
            flat.append(batchMeta.contentData())
            messages.forEach { if !$0.isEmpty { flat.append($0) } }
            try? flat.write(to: fileUrl)
        }

        self.nextMessageIndex += messages.count
        NetworkManager.shared.sendMessage(content: content) { (success, shouldRetry) in
            self.workQueue.async {
                guard success else {
                    guard shouldRetry else {
                        DebugUtils.error("Dropping message batch after permanent server rejection")
                        // The batch is gone for good, so the terminate pass is over:
                        // leaving the flag set would make every later batch rewrite
                        // the late-messages file.
                        self.sendingLastMessages = false
                        return
                    }
                    DebugUtils.log("<><>re-sending failed batch<><>")
                    self.messagesWaiting.insert(contentsOf: messages, at: 0)
                    self.waitingBytes += sentSize
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
