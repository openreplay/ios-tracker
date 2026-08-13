import UIKit
import SWCompression

let START_URL = "/v1/mobile/start"
let INGEST_URL = "/v1/mobile/i"
let LATE_URL = "/v1/mobile/late"
let IMAGES_URL = "/v1/mobile/images"

class NetworkManager: NSObject {
    static let shared = NetworkManager()
    var baseUrl = "https://api.openreplay.com/ingest"
    public var sessionId: String? = nil
    private var token: String? = nil
    public var writeToFile = false
    private var framesSupport = false
    // Guards against a 401 storm: N queued requests failing at once must not
    // spawn N parallel session restarts. Reset when a new session is created.
    private var isRestartingSession = false
    
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    private var localSessionFile: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("session.dat")
    }

    override init() {
        super.init()
        if Openreplay.shared.options.debugLogs, writeToFile, let fileURL = localSessionFile {
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    private func createRequest(method: String, path: String) -> URLRequest? {
        guard let url = URL(string: baseUrl + path) else {
            DebugUtils.error("Invalid URL: \(baseUrl + path)")
            return nil
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }

    private func callAPI(request: URLRequest,
                 onSuccess: @escaping (Data) -> Void,
                 onError: @escaping (_ error: Error?, _ statusCode: Int?) -> Void) {
        guard !writeToFile else { return }
        let task = session.dataTask(with: request) { (data, response, error) in
            if Openreplay.shared.options.debugLogs {
                DebugUtils.log(">>> \(request.httpMethod ?? "") \(request.url?.absoluteString ?? "") status=\((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }

            DispatchQueue.main.async {
                let statusCode = (response as? HTTPURLResponse)?.statusCode
                guard let data = data,
                      let statusCode = statusCode,
                      (200...299).contains(statusCode) else {
                    let failedUrl = request.url?.absoluteString ?? ""
                    let errorStr = error?.localizedDescription ?? "N/A"
                    let respData = String(data: data ?? Data(), encoding: .utf8) ?? ""
                    DebugUtils.error(">>>>>> Error in call \(failedUrl), \n error: \(errorStr) \n response: \(respData)")

                    if statusCode == 401 {
                        self.token = nil
                        if !self.isRestartingSession {
                            self.isRestartingSession = true
                            Openreplay.shared.startSession(projectKey: Openreplay.shared.projectKey ?? "", options: Openreplay.shared.options)
                        }
                    }
                    onError(error, statusCode)
                    return
                }
                onSuccess(data)
            }
        }
        task.resume()
    }

    /// Transient failures (offline, 5xx, 429) are worth retrying; other 4xx means
    /// the server rejected the payload/session — retrying the same bytes forever
    /// just burns battery and bandwidth.
    func isRetryable(statusCode: Int?) -> Bool {
        guard let status = statusCode else { return true } // network error, no response
        return (500...599).contains(status) || status == 429
    }

    func createSession(params: [String: AnyHashable], completion: @escaping (ORSessionResponse?) -> Void) {
        guard !writeToFile else {
            self.token = "writeToFile"
            return
        }
        // Every terminal path clears the restart latch: if a 401-triggered restart
        // fails, leaving it set would block all later restarts for the whole
        // process lifetime.
        let finish: (ORSessionResponse?) -> Void = { response in
            self.isRestartingSession = false
            completion(response)
        }
        guard var request = createRequest(method: "POST", path: START_URL) else {
            finish(nil)
            return
        }
        guard let jsonData = try? JSONSerialization.data(withJSONObject: params, options: []) else {
            finish(nil)
            DebugUtils.error("no params data")
            return
        }
        request.httpBody = jsonData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        callAPI(request: request) { (data) in
            do {
                let session = try JSONDecoder().decode(ORSessionResponse.self, from: data)

                self.token = session.token
                self.sessionId = session.sessionID
                self.framesSupport = session.framesSupport ?? false
                ORUserDefaults.shared.lastToken = self.token
                finish(session)
            } catch {
                DebugUtils.log("Can't unwrap session start resp: \(error)")
                finish(nil)
            }
        } onError: { err, _ in
            DebugUtils.error(err.debugDescription)
            finish(nil)
        }
    }

    func sendMessage(content: Data, completion: @escaping (_ success: Bool, _ shouldRetry: Bool) -> Void) {
        guard !writeToFile else {
            appendLocalFile(data: content)
            return
        }
        guard Openreplay.shared.uploadsAllowed else {
            // wifiOnly + cellular: keep the batch queued until WiFi returns
            completion(false, true)
            return
        }
        guard var request = createRequest(method: "POST", path: INGEST_URL) else {
            completion(false, false)
            return
        }
        guard let token = token else {
            // No token yet — keep the batch queued until a session is established.
            completion(false, true)
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        var compressedContent = content
        let oldSize = compressedContent.count
        var newSize = oldSize
        do {
            let compressed = try GzipArchive.archive(data: content)
            compressedContent = compressed
            newSize = compressed.count
            request.setValue("gzip", forHTTPHeaderField: "Content-Encoding")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            DebugUtils.log(">>>>Compress batch file \(oldSize)>\(newSize)")
        } catch {
            DebugUtils.log("Error with compression: \(error)")
        }

        request.httpBody = compressedContent
        callAPI(request: request) { (data) in
            completion(true, false)
        } onError: { _, statusCode in
            completion(false, self.isRetryable(statusCode: statusCode))
        }
    }

    func sendLateMessage(content: Data, completion: @escaping (Bool) -> Void) {
        DebugUtils.log(">>>sending late messages")
        guard var request = createRequest(method: "POST", path: LATE_URL) else {
            completion(false)
            return
        }
        guard let token = ORUserDefaults.shared.lastToken else {
            completion(false)
            DebugUtils.log("! No last token found")
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = content
        callAPI(request: request) { (data) in
            completion(true)
            DebugUtils.log("<<< late messages sent")
        } onError: { _, _ in
            completion(false)
        }
    }

    func sendImages(projectKey: String, images: Data, name: String, completion: @escaping (_ success: Bool, _ shouldRetry: Bool) -> Void) {
        guard Openreplay.shared.uploadsAllowed else {
            completion(false, true)
            return
        }
        guard var request = createRequest(method: "POST", path: IMAGES_URL) else {
            completion(false, false)
            return
        }
        guard let token = token else {
            completion(false, true)
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let boundary = "Boundary-\(NSUUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        var parameters = ["projectKey": projectKey]
        
        if framesSupport {
            parameters["type"] = "frames"
        }
        
        for (key, value) in parameters {
            body.appendString("--\(boundary)\r\n")
            body.appendString("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.appendString("\(value)\r\n")
        }

        body.appendString("--\(boundary)\r\n")
        body.appendString("Content-Disposition: form-data; name=\"batch\"; filename=\"\(name)\"\r\n")
        body.appendString("Content-Type: gzip\r\n\r\n")
        body.append(images)
        body.appendString("\r\n")

        body.appendString("--\(boundary)--\r\n")
        DebugUtils.log(">>>>>> sending \(body.count) bytes")
        request.httpBody = body

        callAPI(request: request) { (data) in
            completion(true, false)
        } onError: { _, statusCode in
            completion(false, self.isRetryable(statusCode: statusCode))
        }
    }

    private func appendLocalFile(data: Data) {
        if (Openreplay.shared.options.debugLogs) {
            DebugUtils.log("appendInFile \(data.count) bytes")

            guard let fileURL = localSessionFile else { return }
            if let fileHandle = try? FileHandle(forWritingTo: fileURL) {
                defer {
                    fileHandle.closeFile()
                }
                fileHandle.seekToEndOfFile()
                fileHandle.write(data)
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }
}
