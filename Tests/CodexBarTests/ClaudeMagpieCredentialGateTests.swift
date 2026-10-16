import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLIMagpieTests {
    @Test(arguments: [UsageProvider.claude, .codex, .kimi, .opencodego])
    func `managed providers do not resolve configured token accounts or import cookies`(
        provider: UsageProvider) async throws
    {
        let context = try TokenAccountCLIContext(
            selection: TokenAccountCLISelection(label: nil, index: nil, allAccounts: true),
            config: CodexBarConfig(providers: [ProviderConfig(id: provider.instanceID)],
                                  magpie: MagpieSourceConfig(enabled: true)),
            verbose: false,
            baseEnvironment: [:])
        #expect(try context.resolvedAccounts(for: provider).isEmpty)
        let result = await CodexBarCLI.refreshCookie(
            descriptor: ProviderDescriptorRegistry.descriptor(for: provider),
            tokenContext: context,
            browserDetection: BrowserDetection(cacheTTL: 0))
        #expect(result.status == .skipped)
    }

    @Test
    func `legacy enabled migration writes only the unified config`() throws {
        let data = Data(#"{"version":1,"providers":[{"id":"claude","claudeMagpieEnabled":true,"claudeMagpieQuotasURL":"http://localhost:3425/v1/magpie/quotas"}]}"#.utf8)
        let config = try CodexBarConfig.decode(from: data)
        #expect(config.magpie?.enabled == true)
        #expect(config.magpie?.quotasURL == "http://localhost:3425/v1/magpie/quotas")
        let encoded = String(decoding: try config.encodedData(), as: UTF8.self)
        #expect(!encoded.contains("claudeMagpieEnabled"))
        #expect(!encoded.contains("claudeMagpieQuotasURL"))
    }

    @Test
    func `legacy disabled configuration does not enable unified ownership`() throws {
        let data = Data(#"{"version":1,"providers":[{"id":"claude","claudeMagpieEnabled":false}]}"#.utf8)
        #expect(try CodexBarConfig.decode(from: data).magpie?.enabled != true)
    }
}
