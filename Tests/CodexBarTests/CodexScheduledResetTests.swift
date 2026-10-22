import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct CodexScheduledResetReaderTests {
    private static func payload(scheduled: String) -> Data {
        Data(#"{"data":{"latest_reset":{"id":"1"},"scheduled_reset":\#(scheduled),"stats":{}},"meta":{}}"#.utf8)
    }

    private static let scheduledJSON = """
    {"id":"2","status":"scheduled","scheduled_for":"2026-10-22T17:00:00.000Z",
     "source":{"type":"x_post","url":"https://x.com/example/status/2"}}
    """

    @Test
    func `a scheduled reset yields its time and source`() throws {
        let reset = try #require(CodexScheduledResetReader
            .scheduledReset(from: Self.payload(scheduled: Self.scheduledJSON)))
        #expect(reset.scheduledFor == Date(timeIntervalSince1970: 1_792_688_400))
        #expect(reset.sourceURL?.absoluteString == "https://x.com/example/status/2")
    }

    @Test
    func `no scheduled reset, another status or malformed data yield nothing`() {
        let other = Self.scheduledJSON.replacingOccurrences(of: "\"scheduled\"", with: "\"landed\"")
        let badDate = Self.scheduledJSON.replacingOccurrences(of: "2026-10-22T17:00:00.000Z", with: "tomorrow")
        for data in [
            Self.payload(scheduled: "null"),
            Self.payload(scheduled: other),
            Self.payload(scheduled: badDate),
            Self.payload(scheduled: #"{"status":"scheduled"}"#),
            Data("not json".utf8),
            Data(#"{"data":[]}"#.utf8),
        ] {
            #expect(CodexScheduledResetReader.scheduledReset(from: data) == nil)
        }
    }

    @Test
    func `a source that is not https is dropped but the reset stays`() throws {
        let http = Self.scheduledJSON.replacingOccurrences(of: "https://", with: "http://")
        let reset = try #require(CodexScheduledResetReader.scheduledReset(from: Self.payload(scheduled: http)))
        #expect(reset.sourceURL == nil)
    }

    @Test
    func `a reset is pending only before its time`() {
        let time = Date(timeIntervalSince1970: 1000)
        let reset = CodexScheduledReset(scheduledFor: time, sourceURL: nil)
        #expect(reset.isPending(at: time.addingTimeInterval(-1)))
        #expect(!reset.isPending(at: time))
        #expect(!reset.isPending(at: time.addingTimeInterval(1)))
    }
}

@MainActor
struct CodexScheduledResetStoreTests {
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        var requestCount: Int {
            self.lock.withLock { self.value }
        }

        func increment() { self.lock.withLock { self.value += 1 } }
    }

    private static let now = Date(timeIntervalSince1970: 1_792_600_000)
    private static let body = Data("""
    {"data":{"scheduled_reset":{"status":"scheduled","scheduled_for":"2026-10-22T17:00:00.000Z",
     "source":{"url":"https://x.com/example/status/2"}}}}
    """.utf8)

    private func makeStore(codexEnabled: Bool = true) -> UsageStore {
        let settings = testSettingsStore(
            suiteName: "CodexScheduledResetStoreTests",
            userDefaults: InMemoryUserDefaults(),
            config: CodexBarConfig(providers: []),
            keychainAccessPolicy: SettingsStoreKeychainAccessPolicy(
                setDisabled: { _ in }, isExplicitlyDisabled: { true }))
        settings.providerDetectionCompleted = true
        settings.refreshFrequency = .manual
        settings.statusChecksEnabled = false
        let store = UsageStore(
            fetcher: UsageFetcher(environment: [:]),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: [:])
        enableTestProviders(codexEnabled ? [.codex] : [.claude], settings: settings)
        return store
    }

    private func transport(counter: Counter, data: Data = Self.body, fails: Bool = false)
        -> CodexScheduledResetReader.Transport
    {
        { request in
            counter.increment()
            if fails { throw URLError(.notConnectedToInternet) }
            return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
    }

    @Test
    func `a second refresh within thirty minutes sends no request`() async {
        let store = self.makeStore()
        let counter = Counter()
        store.codexScheduledResetTransport = self.transport(counter: counter)
        await store.refreshCodexScheduledReset(now: Self.now)
        await store.refreshCodexScheduledReset(now: Self.now.addingTimeInterval(29 * 60))
        #expect(counter.requestCount == 1)
        await store.refreshCodexScheduledReset(now: Self.now.addingTimeInterval(31 * 60))
        #expect(counter.requestCount == 2)
    }

    @Test
    func `a failed fetch keeps the previous result`() async {
        let store = self.makeStore()
        let counter = Counter()
        store.codexScheduledResetTransport = self.transport(counter: counter)
        await store.refreshCodexScheduledReset(now: Self.now)
        let first = store.codexScheduledReset
        #expect(first != nil)
        store.codexScheduledResetTransport = self.transport(counter: counter, fails: true)
        await store.refreshCodexScheduledReset(now: Self.now.addingTimeInterval(31 * 60))
        #expect(counter.requestCount == 2)
        #expect(store.codexScheduledReset == first)
    }

    @Test
    func `the switch off hides the reset and stops requests`() async {
        let store = self.makeStore()
        let counter = Counter()
        store.codexScheduledResetTransport = self.transport(counter: counter)
        await store.refreshCodexScheduledReset(now: Self.now)
        #expect(store.visibleCodexScheduledReset(now: Self.now) != nil)

        store.settings.codexScheduledResetVisible = false
        #expect(store.visibleCodexScheduledReset(now: Self.now) == nil)
        await store.refreshCodexScheduledReset(now: Self.now.addingTimeInterval(3600))
        #expect(counter.requestCount == 1)
    }

    @Test
    func `nothing is requested without the Codex provider enabled`() async {
        let store = self.makeStore(codexEnabled: false)
        let counter = Counter()
        store.codexScheduledResetTransport = self.transport(counter: counter)
        await store.refreshCodexScheduledReset(now: Self.now)
        #expect(counter.requestCount == 0)
    }

    @Test
    func `a reset that has passed is no longer visible even if still cached`() async {
        let store = self.makeStore()
        store.codexScheduledResetTransport = self.transport(counter: Counter())
        await store.refreshCodexScheduledReset(now: Self.now)
        #expect(store.visibleCodexScheduledReset(now: Self.now) != nil)
        #expect(store.visibleCodexScheduledReset(now: Date(timeIntervalSince1970: 1_792_688_401)) == nil)
    }
}
