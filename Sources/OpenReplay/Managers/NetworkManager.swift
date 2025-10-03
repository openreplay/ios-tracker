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
    
    private lazy var session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.waitsForConnectivity = true
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        return URLSession(configuration: cfg)
    }()

    override init() {
        super.init()
        if (Openreplay.shared.options.debugLogs) {
            if writeToFile, FileManager.default.fileExists(atPath: "/Users/nikitamelnikov/Desktop/session.dat") {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: "/Users/nikitamelnikov/Desktop/session.dat"))
            }
        }
    }

    private func createRequest(method: String, path: String) -> URLRequest {
        let url = URL(string: baseUrl+path)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        return request
    }

    private func callAPI(request: URLRequest,
                 onSuccess: @escaping (Data) -> Void,
                 onError: @escaping (Error?) -> Void) {
        guard !writeToFile else { return }
        let task = session.dataTask(with: request) { (data, response, error) in
            if Openreplay.shared.options.debugLogs {
                DebugUtils.log(">>> \(request.httpMethod ?? "") \(request.url?.absoluteString ?? "") status=\((response as? HTTPURLResponse)?.statusCode ?? -1)")
            }
            
            DispatchQueue.main.async {
                guard let data = data,
                      let httpResponse = response as? HTTPURLResponse,
                      (200...299).contains(httpResponse.statusCode) else {
                    let failedUrl = request.url?.absoluteString ?? ""
                    let errorStr = error?.localizedDescription ?? "N/A"
                    let respData = String(data: data ?? Data(), encoding: .utf8) ?? ""
                    DebugUtils.error(">>>>>> Error in call \(failedUrl), \n error: \(errorStr) \n response: \(respData)")
                    
                    if (response as? HTTPURLResponse)?.statusCode == 401 {
                        self.token = nil
                        Openreplay.shared.startSession(projectKey: Openreplay.shared.projectKey ?? "", options: Openreplay.shared.options)
                    }
                    onError(error)
                    return
                }
                onSuccess(data)
            }
        }
        task.resume()
    }

    func createSession(params: [String: AnyHashable], completion: @escaping (ORSessionResponse?) -> Void) {
        guard !writeToFile else {
            self.token = "writeToFile"
            return
        }
        var request = createRequest(method: "POST", path: START_URL)
        guard let jsonData = try? JSONSerialization.data(withJSONObject: params, options: []) else {
            completion(nil)
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
                ORUserDefaults.shared.lastToken = self.token
                completion(session)
            } catch {
                DebugUtils.log("Can't unwrap session start resp: \(error)")
            }
        } onError: { err in
            DebugUtils.error(err.debugDescription)
            completion(nil)
        }
    }

    func sendMessage(content: Data, completion: @escaping (Bool) -> Void) {
        guard !writeToFile else {
            appendLocalFile(data: content)
            return
        }
        var request = createRequest(method: "POST", path: INGEST_URL)
        guard let token = token else {
            completion(false)
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
            completion(true)
        } onError: { _ in
            completion(false)
        }
    }

    func sendLateMessage(content: Data, completion: @escaping (Bool) -> Void) {
        DebugUtils.log(">>>sending late messages")
        var request = createRequest(method: "POST", path: LATE_URL)
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
        } onError: { _ in
            completion(false)
        }
    }

    func sendImages(projectKey: String, images: Data, name: String, completion: @escaping (Bool) -> Void) {
        var request = createRequest(method: "POST", path: IMAGES_URL)
        guard let token = token else {
            completion(false)
            return
        }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let boundary = "Boundary-\(NSUUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        let parameters = ["projectKey": projectKey]
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
            completion(true)
        } onError: { _ in
            completion(false)
        }
    }

    private func appendLocalFile(data: Data) {
        if (Openreplay.shared.options.debugLogs) {
            DebugUtils.log("appendInFile \(data.count) bytes")
            
            let fileURL = URL(fileURLWithPath: "/Users/nikitamelnikov/Desktop/session.dat")
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
