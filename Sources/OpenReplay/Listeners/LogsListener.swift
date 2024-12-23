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

            // Cancel dispatch sources
            stdoutSource?.cancel()
            stdoutSource = nil
            stderrSource?.cancel()
            stderrSource = nil

            // Close pipe read ends
            if stdoutPipe[0] >= 0 {
                close(stdoutPipe[0])
                stdoutPipe[0] = -1
            }

            if stderrPipe[0] >= 0 {
                close(stderrPipe[0])
                stderrPipe[0] = -1
            }
        }
    }

    private func setupSource(for fd: Int32, severity: String, originalFd: Int32) {
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global(qos: .background))
        source.setEventHandler { [weak self] in
            guard let strongSelf = self else { return }
            let bufferSize = 1024
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            let bytesRead = read(fd, &buffer, bufferSize)
            if bytesRead > 0 {
                let data = Data(buffer[0..<bytesRead])

                // Convert data to string and record
                if let string = String(data: data, encoding: .utf8) {
                    let message = ORMobileLog(severity: severity, content: string)
                    MessageCollector.shared.sendMessage(message)
                }

                // Also write back to the original fd so logs appear normally
                if originalFd >= 0 {
                    _ = data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int in
                        write(originalFd, ptr.baseAddress, ptr.count)
                    }
                }
            }
        }

        source.setCancelHandler {
            // We're closing fds in stop().
        }

        source.resume()

        if severity == "info" {
            stdoutSource = source
        } else {
            stderrSource = source
        }
    }
}
