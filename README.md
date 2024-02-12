[Full Documentation](https://docs.openreplay.com/en/ios-sdk/)

Setting up tracker

[Cocoapods home page](https://cocoapods.org/pods/OpenReplay)

## installation

Please make sure to use latest version. (check in tags)

### Cocoapods

```ruby
  pod 'OpenReplay', '~> 1.0.10'
```

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/openreplay/ios-tracker.git", from: "1.0.10"),
]
```

```swift
// AppDelegate.swift
import OpenReplay

//...

class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        OpenReplay.shared.serverURL = "https://your.instance.com/ingest"
        OpenReplay.shared.start(projectKey: "projectkey", options: .defaults)

        // ...
        return true
    }
```

Options (default all `true`)

```swift
let crashes: Bool
let analytics: Bool
let performances: Bool
let logs: Bool
let screen: Bool
let wifiOnly: Bool
```

Setting up touches listener

```swift
// SceneDelegate.Swift
import OpenReplay

// ...
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        let contentView = ContentView()
            .environmentObject(TodoStore())

        if let windowScene = scene as? UIWindowScene {
            let window = TouchTrackingWindow(windowScene: windowScene) // <<<< here
            window.rootViewController = UIHostingController(rootView: contentView)
            self.window = window
            window.makeKeyAndVisible()
        }
    }
```

Adding sensitive views (will be blurred in replay)

```swift
import OpenReplay

// swiftUI
Text("Very important sensitive text")
    .sensitive()

// UIKit
OpenReplay.shared.addIgnoredView(view)
```

Adding tracked inputs

```swift

// swiftUI
TextField("Input", text: $text)
    .observeInput(text: $text, label: "tracker input #1", masked: Bool)

// UIKit will use placeholder as label and sender.isSecureTextEntry to mask the input
Analytics.shared.addObservedInput(inputEl)
```

Observing views

```swift
// swiftUI
TextField("Test")
  .observeView(title: "Screen title", viewName: "test input name")

// UIKit
Analytics.shared.addObservedView(view: inputEl, title: "Screen title", viewName: "test input name")
```

will send IOSScreenEnter and IOSScreenLeave when view appears/dissapears on/from screen
