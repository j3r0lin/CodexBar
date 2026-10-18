import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIMagpieTests {
    @Test(arguments: [UsageProvider.claude, .codex, .grok, .kimi, .opencodego])
    func `managed providers do not import cookies`(
        provider: UsageProvider) async throws
    {
        let context = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: true),
            config: CodexBarConfig(
                providers: [ProviderConfig(id: provider.instanceID)],
                magpie: MagpieSourceConfig(enabled: true)),
            verbose: false,
            baseEnvironment: [:],
            magpieSource: CLIMagpieSource(transport: ClaudeMagpieFixture.transport(data: Data("""
            {"data":[{"provider":"claude","windows":[]},{"provider":"codex","windows":[]},
              {"provider":"grok-plugin","windows":[]},{"provider":"kimi-code","windows":[]},
              {"provider":"opencode-go","windows":[]}]}
            """.utf8))))
        let result = await CodexBarCLI.refreshCookie(
            descriptor: ProviderDescriptorRegistry.descriptor(for: provider),
            tokenContext: context,
            browserDetection: BrowserDetection(cacheTTL: 0))
        #expect(result.status == .skipped)
    }

    @Test
    func `provider and account consumers share one discovery request`() async throws {
        let counter = MagpieRequestCounter()
        let source = CLIMagpieSource { request in
            await counter.record()
            return (
                ClaudeMagpieFixture.quotasData,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let configuration = MagpieSourceConfig(enabled: true)
        async let claude = source.route(for: .claude, configuration: configuration)
        async let codex = source.route(for: .codex, configuration: configuration)
        async let kimi = source.route(for: .kimi, configuration: configuration)
        let routes = await [claude, codex, kimi]
        #expect(!routes[0].isNative)
        #expect(!routes[1].isNative)
        #expect(routes[2].isNative)
        _ = try await source.rows(quotasURL: nil)
        let requestCount = await counter.count
        #expect(requestCount == 1)
    }

    @Test(
        arguments: [UsageProvider.claude, .codex, .grok, .kimi, .opencodego],
        ["enabling", "firstFailure", "laterFailure", "disappeared"])
    func `routed CLI consumers skip native construction across discovery outcomes`(
        provider: UsageProvider,
        state: String) async throws
    {
        let allProviders = Data("""
        {"data":[{"provider":"claude","windows":[]},{"provider":"codex","windows":[]},
          {"provider":"grok-plugin","windows":[]},{"provider":"kimi-code","windows":[]},
          {"provider":"opencode-go","windows":[]}]}
        """.utf8)
        let failing = state == "firstFailure" || state == "laterFailure"
        let previouslyOwned: Set<String> = state == "laterFailure" || state == "disappeared"
            ? ["claude", "codex", "grok-plugin", "kimi-code", "opencode-go"]
            : []
        let source = CLIMagpieSource(
            transport: ClaudeMagpieFixture.transport(
                data: state == "disappeared" ? Data(#"{"data":[]}"#.utf8) : allProviders,
                status: failing ? 503 : 200),
            ownedWireIDs: previouslyOwned)
        let context = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: false),
            config: CodexBarConfig(providers: [], magpie: MagpieSourceConfig(enabled: true)),
            verbose: false,
            baseEnvironment: [:],
            magpieSource: source)
        let intercept: @Sendable (NativeProviderIOTestBoundary.Kind) throws -> Void = { _ in
            Issue.record("Native IO crossed the magpie route")
            throw CancellationError()
        }
        await NativeProviderIOTestBoundary.$intercept.withValue(intercept) {
            _ = await CodexBarCLI.fetchRoutedProviderUsage(provider: provider, tokenContext: context) {
                Issue.record("Native context construction crossed the magpie route")
                return ProviderFetchOutcome(result: .failure(UsageError.noRateLimitsFound), attempts: [])
            }
        }
    }

    @Test
    func `CLI keeps persisted ownership when provider disappears`() async {
        let source = CLIMagpieSource(
            transport: ClaudeMagpieFixture.transport(data: Data(#"{"data":[]}"#.utf8)),
            ownedWireIDs: ["codex"])
        let route = await source.route(for: .codex, configuration: MagpieSourceConfig(enabled: true))
        #expect(!route.isNative)
    }

    @Test(arguments: ["grok", "grok-plugin"])
    func `grok routes to magpie under either wire id`(wireID: String) async {
        let source = CLIMagpieSource(
            transport: ClaudeMagpieFixture.transport(data: Data("""
            {"data":[{"provider":"\(wireID)","windows":[]}]}
            """.utf8)))
        let route = await source.route(for: .grok, configuration: MagpieSourceConfig(enabled: true))
        #expect(!route.isNative, "\(wireID)")
    }

    @Test(arguments: ["grok", "grok-plugin"])
    func `grok stays owned when persisted under either wire id`(wireID: String) async {
        let source = CLIMagpieSource(
            transport: ClaudeMagpieFixture.transport(data: Data(#"{"data":[]}"#.utf8)),
            ownedWireIDs: [wireID])
        let route = await source.route(for: .grok, configuration: MagpieSourceConfig(enabled: true))
        #expect(!route.isNative, "\(wireID)")
    }

    @Test
    func `legacy enabled migration writes only the unified config`() throws {
        let data = Data(
            #"{"version":1,"providers":[{"id":"claude","claudeMagpieEnabled":true,"claudeMagpieQuotasURL":"http://localhost:3425/v1/magpie/quotas"}]}"#
                .utf8)
        let config = try CodexBarConfig.decode(from: data)
        #expect(config.magpie?.enabled == true)
        #expect(config.magpie?.quotasURL == "http://localhost:3425/v1/magpie/quotas")
        let encoded = try #require(String(bytes: config.encodedData(), encoding: .utf8))
        #expect(!encoded.contains("claudeMagpieEnabled"))
        #expect(!encoded.contains("claudeMagpieQuotasURL"))
    }

    @Test
    func `legacy disabled configuration does not enable unified ownership`() throws {
        let data = Data(#"{"version":1,"providers":[{"id":"claude","claudeMagpieEnabled":false}]}"#.utf8)
        #expect(try CodexBarConfig.decode(from: data).magpie?.enabled != true)
    }
}

private actor MagpieRequestCounter {
    private(set) var count = 0

    func record() {
        self.count += 1
    }
}
