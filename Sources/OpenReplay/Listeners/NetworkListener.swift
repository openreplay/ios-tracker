import UIKit

open class NetworkListener: NSObject {
    // Monotonic clock: wall clock (Date) can step backwards on NTP sync,
    // which would underflow the UInt64 duration math and crash.
    private let startTime = DispatchTime.now()
    private var url: String = ""
    private var method: String = ""
    private var requestBody: String?
    private var requestHeaders: [String: String]?
    /// JSON body keys whose values are masked before recording (case-insensitive).
    public var ignoredKeys = ["password"]
    /// Headers whose values are masked before recording (case-insensitive).
    public var ignoredHeaders = [
        "Authorization",
        "Proxy-Authorization",
        "Cookie",
        "Set-Cookie",
        "Authentication",
        "Auth",
        "X-Api-Key",
    ]

    public override init() {
        super.init()
    }

    public convenience init(request: URLRequest) {
        self.init()
        start(request: request)
    }

    public convenience init(task: URLSessionTask) {
        self.init()
        start(task: task)
    }

    open func start(request: URLRequest) {
        url = request.url?.absoluteString ?? ""
        method = request.httpMethod ?? "GET"
        requestHeaders = request.allHTTPHeaderFields

        if let body = request.httpBody {
            requestBody = String(data: body, encoding: .utf8)
        } else {
            requestBody = ""
            DebugUtils.log("error getting request body (start request)")
        }
    }

    open func start(task: URLSessionTask) {
        if let request = task.currentRequest {
            start(request: request)
        } else {
            DebugUtils.log("error getting request body (start task)")
        }
    }

    open func finish(response: URLResponse?, data: Data?) {
        let dur = (DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000
        let httpResponse = response as? HTTPURLResponse

        var responseBody: String? = nil
        if let data = data {
            responseBody = String(data: data, encoding: .utf8)
        } else {
            DebugUtils.log("error getting request body (finish)")
        }

        let requestContent: [String: Any?] = [
            "body": sanitizeBody(body: requestBody),
            "headers": sanitizeHeaders(headers: requestHeaders)
        ]

        var responseContent: [String: Any?]
        if let httpResponse = httpResponse {
            let headers = transformHeaders(httpResponse.allHeaderFields)
            responseContent = [
                "body": sanitizeBody(body: responseBody),
                "headers": sanitizeHeaders(headers: headers)
            ]
        } else {
            responseContent = [
                "body": "",
                "headers": ""
            ]
        }
        

        let requestJSON = convertDictionaryToJSONString(dictionary: requestContent) ?? ""
        let responseJSON = convertDictionaryToJSONString(dictionary: responseContent) ?? ""

        let status = httpResponse?.statusCode ?? 0
        sendNetworkMessage(url: url, method: method, requestJSON: requestJSON, responseJSON: responseJSON, status: status, duration: dur)
    }

    // internal (not private) so the masking rules are unit-testable
    func sanitizeHeaders(headers: [String: String]?) -> [String: String]? {
        guard let headerContent = headers else { return nil }

        // HTTP header names are case-insensitive — "authorization" must match "Authorization"
        let masked = Set(ignoredHeaders.map { $0.lowercased() })
        var sanitizedHeaders = headerContent
        for key in sanitizedHeaders.keys where masked.contains(key.lowercased()) {
            sanitizedHeaders[key] = "***"
        }
        return sanitizedHeaders
    }

    func sanitizeBody(body: String?) -> String? {
        guard let bodyContent = body else { return nil }

        // JSON-aware path: parse, mask ignored keys recursively (handles nesting,
        // arrays, non-string values, and any whitespace/formatting), re-serialize.
        if let data = bodyContent.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data),
           let maskedData = try? JSONSerialization.data(withJSONObject: maskJSONValue(json)),
           let maskedString = String(data: maskedData, encoding: .utf8) {
            return maskedString
        }

        // Fallback for non-JSON bodies: whitespace-tolerant regex, all occurrences.
        var sanitizedBody = bodyContent
        for key in ignoredKeys {
            let escaped = NSRegularExpression.escapedPattern(for: key)
            let pattern = "\"\(escaped)\"\\s*:\\s*(\"(?:[^\"\\\\]|\\\\.)*\"|[^,}\\]\\s]+)"
            sanitizedBody = sanitizedBody.replacingOccurrences(
                of: pattern,
                with: "\"\(key)\":\"***\"",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return sanitizedBody
    }

    func maskJSONValue(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            let masked = Set(ignoredKeys.map { $0.lowercased() })
            var result = [String: Any]()
            for (key, nested) in dict {
                result[key] = masked.contains(key.lowercased()) ? "***" : maskJSONValue(nested)
            }
            return result
        }
        if let array = value as? [Any] {
            return array.map { maskJSONValue($0) }
        }
        return value
    }
}

func convertDictionaryToJSONString(dictionary: [String: Any?]) -> String? {
    if let jsonData = try? JSONSerialization.data(withJSONObject: dictionary, options: []) {
        return String(data: jsonData, encoding: .utf8)
    }
    return nil
}

public func sendNetworkMessage(url: String, method: String, requestJSON: String, responseJSON: String, status: Int, duration: UInt64) {
    let message = ORMobileNetworkCall(
        type: "request",
        method: method,
        URL: url,
        request: requestJSON,
        response: responseJSON,
        status: UInt64(max(0, status)),
        duration: duration
    )
    
    MessageCollector.shared.sendMessage(message)
}

func transformHeaders(_ headers: [AnyHashable: Any]) -> [String: String] {
    var stringHeaders: [String: String] = [:]
    for (key, value) in headers {
        if let stringKey = key.base as? String, let stringValue = value as? String {
            stringHeaders[stringKey] = stringValue
        }
    }
    return stringHeaders
}
