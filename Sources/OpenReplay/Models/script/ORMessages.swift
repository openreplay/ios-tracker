
// Auto-generated, do not edit
import UIKit

enum ORMessageType: UInt64 {
    case mobileMetadata = 92
    case mobileEvent = 93
    case mobileUserID = 94
    case mobileUserAnonymousID = 95
    case mobileScreenChanges = 96
    case mobileCrash = 97
    case mobileViewComponentEvent = 98
    case mobileClickEvent = 100
    case mobileInputEvent = 101
    case mobilePerformanceEvent = 102
    case mobileLog = 103
    case mobileInternalError = 104
    case mobileNetworkCall = 105
    case mobileSwipeEvent = 106
    case mobileBatchMeta = 107
    case graphQL = 109
}

class ORMobileMetadata: ORMessage {
    let key: String
    let value: String

    init(key: String, value: String) {
        self.key = key
        self.value = value
        super.init(messageType: .mobileMetadata)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.key = try genericMessage.body.readString(offset: &offset)
            self.value = try genericMessage.body.readString(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(92), timestamp, Data(values: key, value))
    }

    override var description: String {
        return "-->> MobileMetadata(92): timestamp:\(timestamp) key:\(key) value:\(value)";
    }
}

class ORMobileEvent: ORMessage {
    let name: String
    let payload: String

    init(name: String, payload: String) {
        self.name = name
        self.payload = payload
        super.init(messageType: .mobileEvent)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.name = try genericMessage.body.readString(offset: &offset)
            self.payload = try genericMessage.body.readString(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(93), timestamp, Data(values: name, payload))
    }

    override var description: String {
        return "-->> MobileEvent(93): timestamp:\(timestamp) name:\(name) payload:\(payload)";
    }
}

class ORMobileUserID: ORMessage {
    let iD: String

    init(iD: String) {
        self.iD = iD
        super.init(messageType: .mobileUserID)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.iD = try genericMessage.body.readString(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(94), timestamp, Data(values: iD))
    }

    override var description: String {
        return "-->> MobileUserID(94): timestamp:\(timestamp) iD:\(iD)";
    }
}

class ORMobileUserAnonymousID: ORMessage {
    let iD: String

    init(iD: String) {
        self.iD = iD
        super.init(messageType: .mobileUserAnonymousID)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.iD = try genericMessage.body.readString(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(95), timestamp, Data(values: iD))
    }

    override var description: String {
        return "-->> MobileUserAnonymousID(95): timestamp:\(timestamp) iD:\(iD)";
    }
}

class ORMobileScreenChanges: ORMessage {
    let x: UInt64
    let y: UInt64
    let width: UInt64
    let height: UInt64

    init(x: UInt64, y: UInt64, width: UInt64, height: UInt64) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        super.init(messageType: .mobileScreenChanges)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.x = try genericMessage.body.readPrimary(offset: &offset)
            self.y = try genericMessage.body.readPrimary(offset: &offset)
            self.width = try genericMessage.body.readPrimary(offset: &offset)
            self.height = try genericMessage.body.readPrimary(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(96), timestamp, Data(values: x, y, width, height))
    }

    override var description: String {
        return "-->> MobileScreenChanges(96): timestamp:\(timestamp) x:\(x) y:\(y) width:\(width) height:\(height)";
    }
}

class ORMobileCrash: ORMessage {
    let name: String
    let reason: String
    let stacktrace: String

    init(name: String, reason: String, stacktrace: String) {
        self.name = name
        self.reason = reason
        self.stacktrace = stacktrace
        super.init(messageType: .mobileCrash)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.name = try genericMessage.body.readString(offset: &offset)
            self.reason = try genericMessage.body.readString(offset: &offset)
            self.stacktrace = try genericMessage.body.readString(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(97), timestamp, Data(values: name, reason, stacktrace))
    }

    override var description: String {
        return "-->> MobileCrash(97): timestamp:\(timestamp) name:\(name) reason:\(reason) stacktrace:\(stacktrace)";
    }
}

class ORMobileViewComponentEvent: ORMessage {
    let screenName: String
    let viewName: String
    let visible: Bool

    init(screenName: String, viewName: String, visible: Bool) {
        self.screenName = screenName
        self.viewName = viewName
        self.visible = visible
        super.init(messageType: .mobileViewComponentEvent)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.screenName = try genericMessage.body.readString(offset: &offset)
            self.viewName = try genericMessage.body.readString(offset: &offset)
            self.visible = try genericMessage.body.readPrimary(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(98), timestamp, Data(values: screenName, viewName, visible))
    }

    override var description: String {
        return "-->> MobileViewComponentEvent(98): timestamp:\(timestamp) screenName:\(screenName) viewName:\(viewName) visible:\(visible)";
    }
}

class ORMobileClickEvent: ORMessage {
    let label: String
    let x: UInt64
    let y: UInt64

    init(label: String, x: UInt64, y: UInt64) {
        self.label = label
        self.x = x
        self.y = y
        super.init(messageType: .mobileClickEvent)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.label = try genericMessage.body.readString(offset: &offset)
            self.x = try genericMessage.body.readPrimary(offset: &offset)
            self.y = try genericMessage.body.readPrimary(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(100), timestamp, Data(values: label, x, y))
    }

    override var description: String {
        return "-->> MobileClickEvent(100): timestamp:\(timestamp) label:\(label) x:\(x) y:\(y)";
    }
}

class ORMobileInputEvent: ORMessage {
    let value: String
    let valueMasked: Bool
    let label: String

    init(value: String, valueMasked: Bool, label: String) {
        self.value = value
        self.valueMasked = valueMasked
        self.label = label
        super.init(messageType: .mobileInputEvent)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.value = try genericMessage.body.readString(offset: &offset)
            self.valueMasked = try genericMessage.body.readPrimary(offset: &offset)
            self.label = try genericMessage.body.readString(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(101), timestamp, Data(values: value, valueMasked, label))
    }

    override var description: String {
        return "-->> MobileInputEvent(101): timestamp:\(timestamp) value:\(value) valueMasked:\(valueMasked) label:\(label)";
    }
}

class ORMobilePerformanceEvent: ORMessage {
    let name: String
    let value: UInt64

    init(name: String, value: UInt64) {
        self.name = name
        self.value = value
        super.init(messageType: .mobilePerformanceEvent)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.name = try genericMessage.body.readString(offset: &offset)
            self.value = try genericMessage.body.readPrimary(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(102), timestamp, Data(values: name, value))
    }

    override var description: String {
        return "-->> MobilePerformanceEvent(102): timestamp:\(timestamp) name:\(name) value:\(value)";
    }
}

class ORMobileLog: ORMessage {
    let severity: String
    let content: String

    init(severity: String, content: String) {
        self.severity = severity
        self.content = content
        super.init(messageType: .mobileLog)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.severity = try genericMessage.body.readString(offset: &offset)
            self.content = try genericMessage.body.readString(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(103), timestamp, Data(values: severity, content))
    }

    override var description: String {
        return "-->> MobileLog(103): timestamp:\(timestamp) severity:\(severity) content:\(content)";
    }
}

class ORMobileInternalError: ORMessage {
    let content: String

    init(content: String) {
        self.content = content
        super.init(messageType: .mobileInternalError)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.content = try genericMessage.body.readString(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(104), timestamp, Data(values: content))
    }

    override var description: String {
        return "-->> MobileInternalError(104): timestamp:\(timestamp) content:\(content)";
    }
}

class ORMobileNetworkCall: ORMessage {
    let type: String
    let method: String
    let URL: String
    let request: String
    let response: String
    let status: UInt64
    let duration: UInt64

    init(type: String, method: String, URL: String, request: String, response: String, status: UInt64, duration: UInt64) {
        self.type = type
        self.method = method
        self.URL = URL
        self.request = request
        self.response = response
        self.status = status
        self.duration = duration
        super.init(messageType: .mobileNetworkCall)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.type = try genericMessage.body.readString(offset: &offset)
            self.method = try genericMessage.body.readString(offset: &offset)
            self.URL = try genericMessage.body.readString(offset: &offset)
            self.request = try genericMessage.body.readString(offset: &offset)
            self.response = try genericMessage.body.readString(offset: &offset)
            self.status = try genericMessage.body.readPrimary(offset: &offset)
            self.duration = try genericMessage.body.readPrimary(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(105), timestamp, Data(values: type, method, URL, request, response, status, duration))
    }

    override var description: String {
        return "-->> MobileNetworkCall(105): timestamp:\(timestamp) type:\(type) method:\(method) URL:\(URL) request:\(request) response:\(response) status:\(status) duration:\(duration)";
    }
}

class ORMobileSwipeEvent: ORMessage {
    let label: String
    let x: UInt64
    let y: UInt64
    let direction: String

    init(label: String, x: UInt64, y: UInt64, direction: String) {
        self.label = label
        self.x = x
        self.y = y
        self.direction = direction
        super.init(messageType: .mobileSwipeEvent)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.label = try genericMessage.body.readString(offset: &offset)
            self.x = try genericMessage.body.readPrimary(offset: &offset)
            self.y = try genericMessage.body.readPrimary(offset: &offset)
            self.direction = try genericMessage.body.readString(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(106), timestamp, Data(values: label, x, y, direction))
    }

    override var description: String {
        return "-->> MobileSwipeEvent(106): timestamp:\(timestamp) label:\(label) x:\(x) y:\(y) direction:\(direction)";
    }
}

class ORMobileBatchMeta: ORMessage {
    let firstIndex: UInt64

    init(firstIndex: UInt64) {
        self.firstIndex = firstIndex
        super.init(messageType: .mobileBatchMeta)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.firstIndex = try genericMessage.body.readPrimary(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(107), timestamp, Data(values: firstIndex))
    }

    override var description: String {
        return "-->> MobileBatchMeta(107): timestamp:\(timestamp) firstIndex:\(firstIndex)";
    }
}

class ORGraphQL: ORMessage {
    let operationKind: String
    let operationName: String
    let variables: String
    let response: String
    let duration: UInt64

    init(operationKind: String, operationName: String, variables: String, response: String, duration: UInt64) {
        self.operationKind = operationKind
        self.operationName = operationName
        self.variables = variables
        self.response = response
        self.duration = duration
        super.init(messageType: .graphQL)
    }

    override init?(genericMessage: GenericMessage) {
      do {
            var offset = 0
            self.operationKind = try genericMessage.body.readString(offset: &offset)
            self.operationName = try genericMessage.body.readString(offset: &offset)
            self.variables = try genericMessage.body.readString(offset: &offset)
            self.response = try genericMessage.body.readString(offset: &offset)
            self.duration = try genericMessage.body.readPrimary(offset: &offset)
            super.init(genericMessage: genericMessage)
        } catch {
            return nil
        }
    }

    override func contentData() -> Data {
        return Data(values: UInt64(109), timestamp, Data(values: operationKind, operationName, variables, response, duration))
    }

    override var description: String {
        return "-->> GraphQL(109): timestamp:\(timestamp) operationKind:\(operationKind) operationName:\(operationName) variables:\(variables) response:\(response) duration:\(duration)";
    }
}

