import UIKit

class ORUserDefaults: NSObject {
    public static let shared = ORUserDefaults()
    private let userDefaults: UserDefaults?

    override init() {
        userDefaults = UserDefaults(suiteName: "io.orenreplay.openreplaytr-defaults")
    }

    var userUUID: String {
        get {
            if let savedUUID = userDefaults?.string(forKey: "userUUID") {
                return savedUUID
            }
            let newUUID = UUID().uuidString
            self.userUUID = newUUID
            return newUUID
        }
        set {
            userDefaults?.set(newValue, forKey: "userUUID")
        }
    }

    var lastToken: String? {
        get {
            if let token = ORKeychain.get("lastToken") {
                return token
            }
            // Migrate a token stored by older SDK versions in UserDefaults
            if let legacy = userDefaults?.string(forKey: "lastToken") {
                ORKeychain.set(legacy, forKey: "lastToken")
                userDefaults?.removeObject(forKey: "lastToken")
                return legacy
            }
            return nil
        }
        set {
            ORKeychain.set(newValue, forKey: "lastToken")
        }
    }
}
