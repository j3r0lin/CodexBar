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
    func `parallel CLI collection keeps magpie ownership and does no native IO`() async throws {
        let context = try Self.makeContext(
            providers: [.claude, .codex],
            data: Data("""
            {"data":[{"provider":"claude","windows":[{"name":"5 hours","used":1}]},
              {"provider":"codex","windows":[{"name":"5 hours","used":1}]}]}
            """.utf8))
        let command = Self.makeCommand()
        let intercept: @Sendable (NativeProviderIOTestBoundary.Kind) throws -> Void = { kind in
            Issue.record("Native IO crossed the magpie route: \(kind.rawValue)")
            throw CancellationError()
        }
        let output = await NativeProviderIOTestBoundary.$intercept.withValue(intercept) {
            await CodexBarCLI.collectUsageOutputs(providers: [.claude, .codex]) { provider in
                await CodexBarCLI.fetchUsageOutputs(
                    provider: provider, status: nil, tokenContext: context, command: command)
            }
        }
        #expect(output.exitCode == .success)
        #expect(output.payload.map(\.provider) == ["claude", "codex"])
        #expect(output.payload.allSatisfy { $0.source == "magpie" })
        #expect(output.payload.allSatisfy { $0.usage != nil })
    }

    @Test
    func `parallel CLI collection suspends claude platform without native IO`() async throws {
        let context = try Self.makeContext(
            providers: [.claudeplatform],
            data: Data(#"{"data":[{"provider":"claude","windows":[{"name":"5 hours","used":1}]}]}"#.utf8))
        let command = Self.makeCommand()
        let intercept: @Sendable (NativeProviderIOTestBoundary.Kind) throws -> Void = { kind in
            Issue.record("Native IO crossed the magpie route: \(kind.rawValue)")
            throw CancellationError()
        }
        let output = await NativeProviderIOTestBoundary.$intercept.withValue(intercept) {
            await CodexBarCLI.collectUsageOutputs(providers: [.claudeplatform]) { provider in
                await CodexBarCLI.fetchUsageOutputs(
                    provider: provider, status: nil, tokenContext: context, command: command)
            }
        }
        #expect(output.exitCode == .failure)
        #expect(output.payload.count == 1)
        #expect(output.payload.first?.source == "magpie")
        #expect(
            output.payload.first?.error?.message
                == ProviderSourceRoute.suspendedMessage(for: .claudeplatform))
    }

    @Test
    func `provider all expansion keeps the claude family off native reads`() async throws {
        let expansion = ProviderSelection.all.asList
        #expect(expansion.contains(.claude))
        #expect(expansion.contains(.claudeplatform))
        let family = expansion.filter { ProviderSourceRoute.switchOnNativeForbidden.contains($0) }
        #expect(Set(family) == [.claude, .claudeplatform])
        // Claude rows exist but Claude Platform has none: one owned provider, one suspended.
        let context = try Self.makeContext(
            providers: family,
            data: Data(#"{"data":[{"provider":"claude","windows":[{"name":"5 hours","used":1}]}]}"#.utf8))
        let command = Self.makeCommand()
        let intercept: @Sendable (NativeProviderIOTestBoundary.Kind) throws -> Void = { kind in
            Issue.record("Native IO crossed the magpie route: \(kind.rawValue)")
            throw CancellationError()
        }
        let output = await NativeProviderIOTestBoundary.$intercept.withValue(intercept) {
            await CodexBarCLI.collectUsageOutputs(providers: family) { provider in
                await CodexBarCLI.fetchUsageOutputs(
                    provider: provider, status: nil, tokenContext: context, command: command)
            }
        }
        #expect(output.payload.map(\.provider) == family.map(\.rawValue))
        #expect(output.payload.allSatisfy { $0.source == "magpie" })
        #expect(output.payload.first { $0.provider == "claude" }?.usage != nil)
        #expect(
            output.payload.first { $0.provider == "claudeplatform" }?.error?.message
                == ProviderSourceRoute.suspendedMessage(for: .claudeplatform))
    }

    @Test
    func `CLI keeps claude off native reads when magpie returns no claude rows`() async throws {
        let context = try Self.makeContext(
            providers: [.claude],
            data: Data(#"{"data":[]}"#.utf8))
        let command = Self.makeCommand()
        let intercept: @Sendable (NativeProviderIOTestBoundary.Kind) throws -> Void = { kind in
            Issue.record("Native IO crossed the magpie route: \(kind.rawValue)")
            throw CancellationError()
        }
        let output = await NativeProviderIOTestBoundary.$intercept.withValue(intercept) {
            await CodexBarCLI.fetchUsageOutputs(
                provider: .claude, status: nil, tokenContext: context, command: command)
        }
        #expect(output.exitCode == .failure)
        #expect(output.payload.count == 1)
        #expect(output.payload.first?.source == "magpie")
        #expect(
            output.payload.first?.error?.message
                == ProviderSourceRoute.suspendedMessage(for: .claude))
    }

    @Test
    func `CLI reports claude rows without windows as an empty result`() async throws {
        let context = try Self.makeContext(
            providers: [.claude],
            data: Data(#"{"data":[{"provider":"claude","user":"a@example.com","windows":[]}]}"#.utf8))
        let intercept: @Sendable (NativeProviderIOTestBoundary.Kind) throws -> Void = { kind in
            Issue.record("Native IO crossed the magpie route: \(kind.rawValue)")
            throw CancellationError()
        }
        let output = await NativeProviderIOTestBoundary.$intercept.withValue(intercept) {
            await CodexBarCLI.fetchUsageOutputs(
                provider: .claude, status: nil, tokenContext: context, command: Self.makeCommand())
        }
        #expect(output.exitCode == .success)
        #expect(output.payload.isEmpty)
    }

    @Test
    func `CLI shows the upstream error of claude rows without usage`() async throws {
        let context = try Self.makeContext(
            providers: [.claude],
            data: Data(#"{"data":[{"provider":"claude","user":"a@example.com","windows":[],"error":"token expired"}]}"#.utf8))
        let intercept: @Sendable (NativeProviderIOTestBoundary.Kind) throws -> Void = { kind in
            Issue.record("Native IO crossed the magpie route: \(kind.rawValue)")
            throw CancellationError()
        }
        let output = await NativeProviderIOTestBoundary.$intercept.withValue(intercept) {
            await CodexBarCLI.fetchUsageOutputs(
                provider: .claude, status: nil, tokenContext: context, command: Self.makeCommand())
        }
        #expect(output.exitCode == .failure)
        #expect(output.payload.count == 1)
        #expect(output.payload.first?.source == "magpie")
        #expect(output.payload.first?.error?.message == "token expired")
    }

    @Test(arguments: ["codex", "claude"])
    func `serve cost leaves magpie owned and claude family providers out`(provider: String) async throws {
        let source = CLIMagpieSource(transport: ClaudeMagpieFixture.transport(data: Data("""
        {"data":[{"provider":"codex","windows":[{"name":"5 hours","used":1}]},
          {"provider":"claude","windows":[{"name":"5 hours","used":1}]}]}
        """.utf8)))
        let context = ServeCostContext(
            period: .rolling(days: 30),
            now: Date(),
            calendar: Calendar(identifier: .gregorian),
            config: CodexBarConfig(
                providers: [ProviderConfig(id: UsageProvider.codex.instanceID),
                            ProviderConfig(id: UsageProvider.claude.instanceID)],
                magpie: MagpieSourceConfig(enabled: true)),
            collection: ServeCostCollectionContext(
                configFingerprint: "magpie-serve-cost",
                providerTimeout: nil,
                requestDeadline: nil,
                now: { ContinuousClock().now },
                providerOperations: CLIServeOperationCoordinator()))
        let response = await CodexBarCLI.serveCost(provider: provider, context: context, magpieSource: source)
        #expect(response.status == .ok)
        let rows = try #require(JSONSerialization.jsonObject(with: response.body) as? [Any])
        #expect(rows.isEmpty)
    }

    private static func makeContext(
        providers: [UsageProvider],
        data: Data) throws -> TokenAccountCLIContext
    {
        try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: true),
            config: CodexBarConfig(
                providers: providers.map { ProviderConfig(id: $0.instanceID) },
                magpie: MagpieSourceConfig(enabled: true)),
            verbose: false,
            baseEnvironment: [:],
            magpieSource: CLIMagpieSource(transport: ClaudeMagpieFixture.transport(data: data)))
    }

    private static func makeCommand() -> UsageCommandContext {
        let browserDetection = BrowserDetection(cacheTTL: 0)
        return UsageCommandContext(
            format: .json,
            includeCredits: false,
            sourceModeOverride: nil,
            antigravityPlanDebug: false,
            augmentDebug: false,
            webDebugDumpHTML: false,
            webTimeout: 5,
            verbose: false,
            useColor: false,
            resetStyle: .countdown,
            weeklyWorkDays: nil,
            jsonOnly: true,
            includeAllCodexAccounts: false,
            fetcher: UsageFetcher(),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
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
    func `both grok wire ids in one response produce one cli entry`() async throws {
        let source = CLIMagpieSource(
            transport: ClaudeMagpieFixture.transport(data: Data("""
            {"data":[{"provider":"grok-plugin","user":"g@example.com","windows":[{"name":"7 days","used":1}]},
              {"provider":"grok","user":"g@example.com","windows":[{"name":"7 days","used":2}]}]}
            """.utf8)))
        let context = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: true),
            config: CodexBarConfig(providers: [], magpie: MagpieSourceConfig(enabled: true)),
            verbose: false,
            baseEnvironment: [:],
            magpieSource: source)
        let browserDetection = BrowserDetection(cacheTTL: 0)
        let command = UsageCommandContext(
            format: .json,
            includeCredits: false,
            sourceModeOverride: nil,
            antigravityPlanDebug: false,
            augmentDebug: false,
            webDebugDumpHTML: false,
            webTimeout: 5,
            verbose: false,
            useColor: false,
            resetStyle: .countdown,
            weeklyWorkDays: nil,
            jsonOnly: true,
            includeAllCodexAccounts: false,
            fetcher: UsageFetcher(),
            claudeFetcher: ClaudeUsageFetcher(browserDetection: browserDetection),
            browserDetection: browserDetection)
        let output = await CodexBarCLI.fetchMagpieUsageIfOwned(
            provider: .grok, status: nil, tokenContext: context, command: command)
        #expect(output?.payload.count == 1)
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
