import UIKit

struct Filter: Decodable {
  var `operator`: String
  var value: [String]
  var type: String
  var source: String?
  var filters: [Filter]?
}

struct ApiResponse: Decodable {
  var name: String
  var filters: [Filter]
}

struct Condition {
    var name: String
    var target: [String]
    var op: (String) -> Bool
    var type: String
    var tp: ORMessageType
    var subConditions: [Condition]?
}

class ConditionsManager: NSObject {
    public static let shared = ConditionsManager()
    private var mappedConditions: [Condition] = []
    
    func processMessage(msg: ORMessage) -> String? {
        guard let messageType = msg.message else { return nil }
        
        let matchingConditions = mappedConditions.filter { $0.tp == messageType }
        for activeCon in matchingConditions {
            switch msg {
            case let networkMsg as ORIOSNetworkCall:
                if let matchingNetworkConditions = activeCon.subConditions {
                    // we simply check that ALL conditions match
                    var networkConditionsMet = true
                    for networkCondition in matchingNetworkConditions {
                        switch networkCondition.name {
                        case "fetchUrl":
                            networkConditionsMet = networkConditionsMet && networkCondition.op(networkMsg.URL)
                        case "fetchStatusCode":
                            networkConditionsMet = networkConditionsMet && networkCondition.op(String(networkMsg.status))
                        case "fetchMethod":
                            networkConditionsMet = networkConditionsMet && networkCondition.op(networkMsg.method)
                        case "fetchDuration":
                            networkConditionsMet = networkConditionsMet && networkCondition.op(String(networkMsg.duration))
                        default:
                            continue
                        }
                    }
                    if networkConditionsMet {
                        return activeCon.name
                    }
                } else {
                    continue
                }
            case let viewMsg as ORIOSViewComponentEvent:
                if (activeCon.op(viewMsg.viewName) || activeCon.op(viewMsg.screenName)) {
                    return activeCon.name
                }
            case let clickMsg as ORIOSClickEvent:
                if activeCon.op(clickMsg.label) {
                    return activeCon.name
                }
            case let metaMsg as ORIOSMetadata:
                if (activeCon.op(metaMsg.value) || activeCon.op(metaMsg.key)) {
                    return activeCon.name
                }
            case let eventMsg as ORIOSEvent:
                if (activeCon.op(eventMsg.payload) || activeCon.op(eventMsg.name)) {
                    return activeCon.name
                }
            case let logMsg as ORIOSLog:
                if activeCon.op(logMsg.content) {
                    return activeCon.name
                }
            case let idMsg as ORIOSUserID:
                if activeCon.op(idMsg.iD) {
                    return activeCon.name
                }
                // thermalState  (0:nominal 1:fair 2:serious 3:critical)
                // batteryLevel (0..100)
                // "mainThreadCPU": Possible values (0 .. 100)
                // "memoryUsage": Used memory in bytes, so we divide by total
            case let perfMsg as ORIOSPerformanceEvent:
                if perfMsg.name == "memoryUsage" {
                    if activeCon.op(String(perfMsg.value / UInt64(ProcessInfo.processInfo.physicalMemory))) {
                        return activeCon.name
                    }
                } else {
                    if activeCon.op(String(perfMsg.value)) {
                        return activeCon.name
                    }
                }
            default:
                continue;
            }
        }
        
        return nil
    }
    
    
    func getConditions(projectId: String, token: String) {
        guard let url = URL(string: "\(Openreplay.shared.serverURL)/v1/mobile/conditions/\(projectId)") else {
                DebugUtils.error("Invalid URL")
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
                guard let self = self, let data = data, error == nil else {
                    DebugUtils.error("Network request to get conditions failed: \(error?.localizedDescription ?? "No error")")
                    return
                }

                do {
                    let jsonResponse = try JSONDecoder().decode([String: [ApiResponse]].self, from: data)
                    guard let conditions = jsonResponse["conditions"] else {
                        DebugUtils.error("Conditions key not found in JSON")
                        return
                    }
                    self.mapConditions(resp: conditions)
                } catch {
                    DebugUtils.error("Openreplay: Conditions JSON parsing error: \(error)")
                }
            }

            task.resume()
        }
    
    func mapConditions(resp: [ApiResponse]) {
        var conds: [Condition] = []
        resp.forEach({ condition in
            let filters = condition.filters
            
            filters.forEach({ filter in
                if filter.type == "session_duration" {
                    self.durationCond(dur: filter.value, name: condition.name)
                }
                if filter.type == "network_message" {
                    var networkConditions: [Condition] = []
                    filter.filters?.forEach { subfilter in
                        if let mappedCondition = OperatorsManager.shared.mapConditions(cond: subfilter) {
                            networkConditions.append(mappedCondition)
                        }
                    }
                    
                    if !networkConditions.isEmpty {
                        let combinedCondition = Condition(
                            name: condition.name,
                            target: [],
                            op: { _ in true },
                            type: "network_message",
                            tp: ORMessageType.iOSNetworkCall,
                            subConditions: networkConditions
                        )
                        conds.append(combinedCondition)
                    }
                } else {
                    if let mappedCondition = OperatorsManager.shared.mapConditions(cond: filter) {
                        conds.append(mappedCondition)
                    }
                }
            })
        })
        DebugUtils.log("conditions \(conds)")
        if !conds.isEmpty {
            self.mappedConditions = conds
        }
    }
    
    func durationCond(dur: [String], name: String) {
        var timer: Timer? = nil
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { (_) in
            let now = UInt64(Date().timeIntervalSince1970 * 1000)
            let diff = now - Openreplay.shared.sessionStartTs
            if dur.first(where: { UInt64($0) ?? 9999999 <= diff }) != nil {
                Openreplay.shared.triggerRecording(condition: name)
                timer?.invalidate()
            }
        })
    }
}

class OperatorsManager: NSObject {
    public static let shared = OperatorsManager()

    func isAnyOp(val: String, target: [String]) -> Bool {
        return true
    }
    
    func isOp(val: String, target: [String]) -> Bool {
        return target.first(where: { $0 == val }) != nil
    }

    func isNotOp(val: String, target: [String]) -> Bool {
        return !isOp(val: val, target: target)
    }

    func containsOp(val: String, target: [String]) -> Bool {
      return target.contains(val)
    }

    func notContainsOp(val: String, target: [String]) -> Bool {
      return !target.contains(val)
    }

    func startsWithOp(val: String, target: [String]) -> Bool {
      return target.first(where: { $0.hasPrefix(val) }) != nil
    }

    func endsWithOp(val: String, target: [String]) -> Bool {
      return target.first(where: { $0.hasSuffix(val) }) != nil
    }

    func greaterThanOp(val: String, target: [String]) -> Bool {
            guard let valInt = Int(val) else { return false }
            return target.contains(where: { Int($0) ?? Int.min > valInt })
        }

    func lessThanOp(val: String, target: [String]) -> Bool {
        guard let valInt = Int(val) else { return false }
        return target.contains(where: { Int($0) ?? Int.max < valInt })
    }

    func greaterOrEqualOp(val: String, target: [String]) -> Bool {
        guard let valInt = Int(val) else { return false }
        return target.contains(where: { Int($0) ?? Int.min >= valInt })
    }

    func lessOrEqualOp(val: String, target: [String]) -> Bool {
        guard let valInt = Int(val) else { return false }
        return target.contains(where: { Int($0) ?? Int.max <= valInt })
    }
    
    func equalOp(val: String, target: [String]) -> Bool {
        guard let valInt = Int(val) else { return false }
        return target.first(where: { Int($0) ?? Int.max == valInt }) != nil
    }

    func getOperator(op: String) -> (String, [String]) -> Bool {
            let opMap = [
                "is": self.isOp,
                "isNot": self.isNotOp,
                "contains": self.containsOp,
                "notContains": self.notContainsOp,
                "startsWith": self.startsWithOp,
                "endsWith": self.endsWithOp,
                "greaterThan": self.greaterThanOp,
                "\u{003e}": self.greaterThanOp,
                "lessThan": self.lessThanOp,
                "\u{003c}": self.lessThanOp,
                "greaterOrEqual": self.greaterOrEqualOp,
                "\u{003e}\u{003d}": self.greaterOrEqualOp,
                "lessOrEqual": self.lessOrEqualOp,
                "\u{003c}\u{003d}": self.lessOrEqualOp,
                "isAny": self.isAnyOp,
                "=": self.equalOp
            ]

            if let operation = opMap[op] {
                return operation
            } else {
                return self.isAnyOp
            }
        }
    
    
    func mapConditions(cond: Filter) -> Condition? {
        let opFn = self.getOperator(op: cond.operator)

        switch cond.type {
            case "event":
                return Condition(
                    name: "event",
                    target: cond.value,
                    op: { val in opFn(val, cond.value) },
                    type: cond.type,
                    tp: ORMessageType.iOSEvent
                )
            case "metadata":
                return Condition(
                    name: "metadata",
                    target: cond.value,
                    op: { val in opFn(val, cond.value) },
                    type: cond.type,
                    tp: ORMessageType.iOSMetadata
                )
            case "userId":
                return Condition(
                    name: "user_id",
                    target: cond.value,
                    op: { val in opFn(val, cond.value) },
                    type: cond.type,
                    tp: ORMessageType.iOSUserID
                )
            case "viewComponent":
                return Condition(
                    name: "view_component",
                    target: cond.value,
                    op: { val in opFn(val, cond.value) },
                    type: cond.type,
                    tp: ORMessageType.iOSViewComponentEvent
                )
            case "clickEvent":
                return Condition(
                    name: "click",
                    target: cond.value,
                    op: { val in opFn(val, cond.value) },
                    type: cond.type,
                    tp: ORMessageType.iOSClickEvent
                )
            case "logEvent":
                return Condition(
                    name: "log",
                    target: cond.value,
                    op: { val in opFn(val, cond.value) },
                    type: cond.type,
                    tp: ORMessageType.iOSLog
                )
            case "fetchUrl", "fetchStatusCode", "fetchMethod", "fetchDuration":
                return Condition(
                    name: cond.type,
                    target: cond.value,
                    op: { val in opFn(val, cond.value) },
                    type: cond.type,
                    tp: ORMessageType.iOSNetworkCall
                )
            case "thermalState", "mainThreadCpu", "memoryUsage":
                return Condition(
                    name: cond.type,
                    target: cond.value,
                    op: { val in opFn(val, cond.value) },
                    type: cond.type,
                    tp: ORMessageType.iOSPerformanceEvent
                )
            default:
                return nil
            }
    }

}
