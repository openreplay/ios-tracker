import XCTest
@testable import OpenReplay

// MARK: - Sensitive data masking

final class NetworkListenerSanitizeTests: XCTestCase {
    private var listener: NetworkListener!

    override func setUp() {
        super.setUp()
        listener = NetworkListener()
    }

    func testHeaderMaskingIsCaseInsensitive() {
        let masked = listener.sanitizeHeaders(headers: [
            "authorization": "Bearer secret",
            "COOKIE": "session=abc",
            "Accept": "application/json",
        ])
        XCTAssertEqual(masked?["authorization"], "***")
        XCTAssertEqual(masked?["COOKIE"], "***")
        XCTAssertEqual(masked?["Accept"], "application/json")
    }

    func testHeaderMaskingCoversCommonCredentialHeaders() {
        for header in ["Authorization", "Proxy-Authorization", "Cookie", "Set-Cookie", "X-Api-Key"] {
            let masked = listener.sanitizeHeaders(headers: [header: "leak"])
            XCTAssertEqual(masked?[header], "***", "\(header) was not masked")
        }
    }

    func testHeaderMaskingKeepsNilAndDoesNotAddKeys() {
        XCTAssertNil(listener.sanitizeHeaders(headers: nil))
        let masked = listener.sanitizeHeaders(headers: ["Accept": "*/*"])
        XCTAssertEqual(masked?.count, 1)
    }

    func testBodyMaskingHandlesWhitespaceAndNesting() {
        listener.ignoredKeys = ["password", "token"]
        let body = #"{"password" : "hunter2", "user": {"token": "abc", "name": "nikita"}}"#
        let masked = listener.sanitizeBody(body: body)
        XCTAssertNotNil(masked)
        XCTAssertFalse(masked!.contains("hunter2"))
        XCTAssertFalse(masked!.contains("abc"))
        XCTAssertTrue(masked!.contains("nikita"), "non-sensitive values must survive")
    }

    func testBodyMaskingHandlesArraysAndNonStringValues() {
        listener.ignoredKeys = ["pin"]
        let body = #"{"items":[{"pin":1234},{"pin":null}]}"#
        let masked = listener.sanitizeBody(body: body)
        XCTAssertNotNil(masked)
        XCTAssertFalse(masked!.contains("1234"))
        // Still valid JSON after the round-trip
        XCTAssertNotNil(try? JSONSerialization.jsonObject(with: Data(masked!.utf8)))
    }

    func testBodyMaskingMasksEveryOccurrenceInNonJSONBody() {
        listener.ignoredKeys = ["password"]
        // Not parseable as JSON, so the regex fallback runs
        let body = #"prefix "password":"a" middle "password" : "b" suffix"#
        let masked = listener.sanitizeBody(body: body)
        XCTAssertNotNil(masked)
        XCTAssertFalse(masked!.contains("\"a\""))
        XCTAssertFalse(masked!.contains("\"b\""))
    }

    func testBodyMaskingIgnoresKeysThatLookLikeRegex() {
        listener.ignoredKeys = ["a.b"]
        let masked = listener.sanitizeBody(body: #"{"a.b":"secret","axb":"kept"}"#)
        XCTAssertNotNil(masked)
        XCTAssertFalse(masked!.contains("secret"))
        XCTAssertTrue(masked!.contains("kept"), "'.' must not match an arbitrary character")
    }

    func testBodyMaskingPassesNilThrough() {
        XCTAssertNil(listener.sanitizeBody(body: nil))
    }

    func testMaskJSONValueLeavesScalarsAlone() {
        listener.ignoredKeys = ["password"]
        XCTAssertEqual(listener.maskJSONValue("plain") as? String, "plain")
        XCTAssertEqual(listener.maskJSONValue(42) as? Int, 42)
    }
}

// MARK: - Retry classification

final class RetryPolicyTests: XCTestCase {
    func testTransientFailuresAreRetried() {
        let net = NetworkManager.shared
        XCTAssertTrue(net.isRetryable(statusCode: nil), "network error with no response")
        XCTAssertTrue(net.isRetryable(statusCode: 429))
        XCTAssertTrue(net.isRetryable(statusCode: 500))
        XCTAssertTrue(net.isRetryable(statusCode: 503))
    }

    func testPermanentRejectionsAreNotRetried() {
        let net = NetworkManager.shared
        XCTAssertFalse(net.isRetryable(statusCode: 400))
        XCTAssertFalse(net.isRetryable(statusCode: 401))
        XCTAssertFalse(net.isRetryable(statusCode: 403))
        XCTAssertFalse(net.isRetryable(statusCode: 413))
    }
}

// MARK: - Capture settings

final class CaptureSettingsTests: XCTestCase {
    func testCaptureRateIsInverseFPS() {
        XCTAssertEqual(getCaptureSettings(fps: 4, quality: "standard").captureRate, 0.25, accuracy: 0.0001)
        XCTAssertEqual(getCaptureSettings(fps: 1, quality: "standard").captureRate, 1.0, accuracy: 0.0001)
    }

    func testFPSIsClampedToASaneRange() {
        // 0 or negative fps would divide by zero / produce a negative interval
        XCTAssertEqual(getCaptureSettings(fps: 0, quality: "low").captureRate, 1.0, accuracy: 0.0001)
        XCTAssertEqual(getCaptureSettings(fps: -5, quality: "low").captureRate, 1.0, accuracy: 0.0001)
        XCTAssertEqual(getCaptureSettings(fps: 10_000, quality: "low").captureRate,
                       1.0 / 99.0, accuracy: 0.0001)
    }

    func testQualityIsCaseInsensitiveAndDefaultsToStandard() {
        XCTAssertEqual(getCaptureSettings(fps: 3, quality: "HIGH").imgCompression, 0.6, accuracy: 0.0001)
        XCTAssertEqual(getCaptureSettings(fps: 3, quality: "Low").imgCompression, 0.4, accuracy: 0.0001)
        XCTAssertEqual(getCaptureSettings(fps: 3, quality: "nonsense").imgCompression, 0.5, accuracy: 0.0001)
    }
}

// MARK: - Message encoding primitives

final class DataEncodingTests: XCTestCase {
    func testUIntVarintIsLittleEndianBase128() {
        XCTAssertEqual([UInt8](Data(value: UInt64(0))), [0x00])
        XCTAssertEqual([UInt8](Data(value: UInt64(1))), [0x01])
        XCTAssertEqual([UInt8](Data(value: UInt64(127))), [0x7F])
        XCTAssertEqual([UInt8](Data(value: UInt64(128))), [0x80, 0x01])
        XCTAssertEqual([UInt8](Data(value: UInt64(300))), [0xAC, 0x02])
    }

    func testVarintWidthGrowsAtEachSevenBitBoundary() {
        // The batch-offset fixpoint in MessageCollector depends on this
        XCTAssertEqual(Data(value: UInt64(127)).count, 1)
        XCTAssertEqual(Data(value: UInt64(128)).count, 2)
        XCTAssertEqual(Data(value: UInt64(16_383)).count, 2)
        XCTAssertEqual(Data(value: UInt64(16_384)).count, 3)
    }

    func testStringIsLengthPrefixed() {
        let encoded = Data(value: "abc")
        XCTAssertEqual([UInt8](encoded), [0x03, 0x61, 0x62, 0x63])
    }

    func testSubdataRejectsOutOfBoundsRanges() {
        let data = Data([1, 2, 3, 4])
        XCTAssertEqual(data.subdata(start: 1, length: 2), Data([2, 3]))
        XCTAssertEqual(data.subdata(start: 0, length: 4), Data([1, 2, 3, 4]))
        XCTAssertNil(data.subdata(start: 3, length: 2))
        XCTAssertNil(data.subdata(start: -1, length: 1))
        XCTAssertNil(data.subdata(start: 0, length: -1))
    }

    func testLittleEndianFrameHeaders() {
        var d = Data()
        d.appendUInt32LE(1)
        XCTAssertEqual([UInt8](d), [0x01, 0x00, 0x00, 0x00])

        var d64 = Data()
        d64.appendUInt64LE(1)
        XCTAssertEqual([UInt8](d64), [0x01, 0, 0, 0, 0, 0, 0, 0])
    }
}

// MARK: - Timers

final class TimerSchedulingTests: XCTestCase {
    func testOrScheduledFiresOnTheMainRunLoop() {
        let fired = expectation(description: "timer fired")
        var timer: Timer?
        timer = Timer.orScheduled(interval: 0.05, repeats: false) { _ in
            XCTAssertTrue(Thread.isMainThread)
            fired.fulfill()
        }
        wait(for: [fired], timeout: 2)
        timer?.orInvalidate()
    }

    func testOrScheduledSurvivesBeingCreatedOffTheMainThread() {
        let fired = expectation(description: "timer fired")
        var timer: Timer?
        DispatchQueue.global(qos: .utility).async {
            timer = Timer.orScheduled(interval: 0.05, repeats: false) { _ in
                fired.fulfill()
            }
        }
        wait(for: [fired], timeout: 2)
        timer?.orInvalidate()
    }

    func testOrInvalidateFromABackgroundThreadStopsTheTimer() {
        var fireCount = 0
        let timer = Timer.orScheduled(interval: 0.05) { _ in fireCount += 1 }

        let invalidated = expectation(description: "invalidated")
        DispatchQueue.global(qos: .utility).async {
            timer.orInvalidate()
            invalidated.fulfill()
        }
        wait(for: [invalidated], timeout: 2)

        // Let the run loop turn a few more times; the timer must be dead.
        let settled = expectation(description: "settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settled.fulfill() }
        wait(for: [settled], timeout: 2)

        XCTAssertFalse(timer.isValid)
        let countAfterInvalidate = fireCount

        let settledAgain = expectation(description: "settled again")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { settledAgain.fulfill() }
        wait(for: [settledAgain], timeout: 2)
        XCTAssertEqual(fireCount, countAfterInvalidate)
    }
}

// MARK: - Analytics registries

final class AnalyticsRegistryTests: XCTestCase {
    override func tearDown() {
        Analytics.shared.stop()
        super.tearDown()
    }

    func testPauseKeepsRegisteredViewsButStopsEmitting() {
        let view = UIView()
        Analytics.shared.start()
        Analytics.shared.addObservedView(view: view, screenName: "Home", viewName: "CTA")
        XCTAssertTrue(Analytics.shared.isObserved(view))

        // Backgrounding must not forget views: integrators register them once.
        Analytics.shared.pause()
        XCTAssertFalse(Analytics.shared.enabled)
        XCTAssertTrue(Analytics.shared.isObserved(view))

        Analytics.shared.start()
        XCTAssertTrue(Analytics.shared.enabled)
        XCTAssertTrue(Analytics.shared.isObserved(view))
    }

    func testStopForgetsRegisteredViews() {
        let view = UIView()
        Analytics.shared.start()
        Analytics.shared.addObservedView(view: view, screenName: "Home", viewName: "CTA")

        Analytics.shared.stop()
        XCTAssertFalse(Analytics.shared.enabled)
        XCTAssertFalse(Analytics.shared.isObserved(view))
    }

    func testRegistryDoesNotRetainViews() {
        weak var weakView: UIView?
        autoreleasepool {
            let view = UIView()
            weakView = view
            Analytics.shared.start()
            Analytics.shared.addObservedView(view: view, screenName: "Home", viewName: "CTA")
        }
        XCTAssertNil(weakView, "the observed-view registry must hold views weakly")
    }

    func testObservedNamesRoundTrip() {
        let view = UIView()
        Analytics.shared.addObservedView(view: view, screenName: "Checkout", viewName: "PayButton")
        XCTAssertEqual(view.orScreenName, "Checkout")
        XCTAssertEqual(view.orViewName, "PayButton")
    }
}

// MARK: - Sanitized element registry

final class SanitizedElementTests: XCTestCase {
    func testRegistryDoesNotRetainElements() {
        weak var weakField: SensitiveTextField?
        autoreleasepool {
            let field = SensitiveTextField()
            weakField = field
            ScreenshotManager.shared.addSanitizedElement(field)
        }
        XCTAssertNil(weakField, "the sanitized-element registry must hold elements weakly")
    }

    func testRemoveIsIdempotent() {
        let field = SensitiveTextField()
        ScreenshotManager.shared.addSanitizedElement(field)
        ScreenshotManager.shared.removeSanitizedElement(field)
        ScreenshotManager.shared.removeSanitizedElement(field)
    }
}

// MARK: - stdout/stderr interception lifecycle

final class LogsListenerLifecycleTests: XCTestCase {
    /// Regression guard for the fd lifetime: the read ends are closed by each
    /// source's cancel handler, so a start/stop cycle must not double-close (which
    /// aborts the process) and must leave stdout usable.
    func testRepeatedStartStopCyclesAreSafe() {
        for _ in 0..<3 {
            LogsListener.shared.start()
            print("openreplay test line")
            LogsListener.shared.stop()
        }
        // stdout is restored and still writable
        var byte: UInt8 = 0x0A
        XCTAssertEqual(write(STDOUT_FILENO, &byte, 0), 0)
    }

    func testStopWithoutStartIsANoop() {
        LogsListener.shared.stop()
        LogsListener.shared.stop()
    }
}
