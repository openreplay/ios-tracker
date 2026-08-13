import Foundation

class LogsListener {
    static let shared = LogsListener()

    private var originalStdout: Int32 = -1
    private var originalStderr: Int32 = -1

    private var stdoutPipe: [Int32] = [-1, -1]
    private var stderrPipe: [Int32] = [-1, -1]

    private var stdoutSource: DispatchSourceRead?
    private var stderrSource: DispatchSourceRead?

    private var isStarted = false
    private let operationQueue = DispatchQueue(label: "com.ORlogsListener.queue")

    func start() {
        operationQueue.sync {
            guard !isStarted else { return }
            isStarted = true

            // Intercept STDOUT
            if pipe(&stdoutPipe) == 0 {
                // Save original stdout
                originalStdout = dup(STDOUT_FILENO)
                // Redirect stdout to pipe
                dup2(stdoutPipe[1], STDOUT_FILENO)
                close(stdoutPipe[1])
                setupSource(for: stdoutPipe[0], severity: "info", originalFd: originalStdout)
            }

            // Intercept STDERR
            if pipe(&stderrPipe) == 0 {
                // Save original stderr
                originalStderr = dup(STDERR_FILENO)
                // Redirect stderr to pipe
                dup2(stderrPipe[1], STDERR_FILENO)
                close(stderrPipe[1])
                setupSource(for: stderrPipe[0], severity: "error", originalFd: originalStderr)
            }
        }
    }

    func stop() {
        operationQueue.sync {
            guard isStarted else { return }
            isStarted = false

            // Restore original stdout/stderr
            if originalStdout >= 0 {
                dup2(originalStdout, STDOUT_FILENO)
                close(originalStdout)
                originalStdout = -1
            }

            if originalStderr >= 0 {
                dup2(originalStderr, STDERR_FILENO)
                close(originalStderr)
                originalStderr = -1
            }

            // Cancel dispatch sources. The read ends are closed by each source's
            // cancel handler, which GCD runs only after any in-flight event handler
            // has returned — closing them here would race with a handler that is
            // mid-read() on its own queue (and could hand it a recycled fd).
            stdoutSource?.cancel()
            stdoutSource = nil
            stdoutPipe[0] = -1
            stderrSource?.cancel()
            stderrSource = nil
            stderrPipe[0] = -1
        }
    }

    private func setupSource(for fd: Int32, severity: String, originalFd: Int32) {
        // Line-buffer per source: fixed-size reads can split a multi-byte UTF-8
        // character at the chunk boundary, making String(data:) return nil and
        // silently dropping the whole chunk. Accumulate and emit complete lines.
        var pending = Data()
        let maxPendingBytes = 64_000
        // Own serial queue per source — the captured `pending` buffer must not be
        // touched concurrently.
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "com.openreplay.logs.\(severity)"))
        source.setEventHandler {
            let bufferSize = 1024
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            let bytesRead = read(fd, &buffer, bufferSize)
            guard bytesRead > 0 else { return }
            let data = Data(buffer[0..<bytesRead])

            // Write back to the original fd first so logs appear normally
            if originalFd >= 0 {
                _ = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int in
                    write(originalFd, ptr.baseAddress, ptr.count)
                }
            }

            pending.append(data)
            while let newlineIndex = pending.firstIndex(of: 0x0A) {
                let lineData = pending.subdata(in: pending.startIndex..<newlineIndex)
                pending.removeSubrange(pending.startIndex...newlineIndex)
                if let line = String(data: lineData, encoding: .utf8), !line.isEmpty {
                    MessageCollector.shared.sendMessage(ORMobileLog(severity: severity, content: line))
                }
            }
            // A pathological line with no newline shouldn't grow the buffer forever
            if pending.count > maxPendingBytes {
                if let chunk = String(data: pending, encoding: .utf8), !chunk.isEmpty {
                    MessageCollector.shared.sendMessage(ORMobileLog(severity: severity, content: chunk))
                }
                pending.removeAll(keepingCapacity: true)
            }
        }

        source.setCancelHandler {
            // Owns the read end: GCD guarantees this runs after the last event
            // handler returns, so nothing can be reading `fd` at this point.
            close(fd)
        }

        source.resume()

        if severity == "info" {
            stdoutSource = source
        } else {
            stderrSource = source
        }
    }
}
