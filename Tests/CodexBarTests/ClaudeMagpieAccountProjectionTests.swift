import CodexBarCore
import Foundation
import Testing

struct MagpieAccountProjectionTests {
    private func project(_ json: String) throws -> [MagpieAccountSnapshot] {
        MagpieAccountProjection.snapshots(from: try MagpieQuotasReader.rows(from: Data(json.utf8)))
    }

    @Test
    func `all providers and unknown windows survive malformed siblings`() throws {
        let rows = try self.project("""
        {"data":[{"provider":"claude","user":"one@example.com","windows":[{"name":"5 hours","used":12}]},
          {"provider":"future-provider","user":"two@example.com","windows":[{"name":"Custom","used":9}]},
          {"user":"broken"}, {"provider":"grok-plugin","windows":[{"name":"7 days","used":4}]}]}
        """)
        #expect(rows.count == 3)
        let unknown = try #require(rows.first { $0.provider.wireID == "future-provider" })
        #expect(unknown.provider.nativeProvider == nil)
        #expect(unknown.provider.displayName == "future-provider")
        #expect(unknown.provider.instanceID.rawValue.hasPrefix("magpie-"))
        #expect(unknown.windows.first?.name == "Custom")
        #expect(unknown.windows.first?.duration == nil)
        #expect(rows.first { $0.provider.wireID == "grok-plugin" }?.provider.nativeProvider == nil)
    }

    @Test
    func `identity survives alias and order changes and includes organization and provider`() throws {
        let original = try self.project("""
        {"data":[{"provider":"claude","user":"ONE@example.com · Org A","alias":"first"},
          {"provider":"claude","user":"one@example.com · Org B"},
          {"provider":"codex","user":"one@example.com · Org A"}]}
        """)
        let reordered = try self.project("""
        {"data":[{"provider":"codex","user":"one@example.com · Org A"},
          {"provider":"claude","user":"one@example.com · Org B"},
          {"provider":"claude","user":"one@example.com · Org A","alias":"renamed"}]}
        """)
        #expect(Set(original.map(\.id)).count == 3)
        #expect(Set(original.map(\.id)) == Set(reordered.map(\.id)))
        #expect(original.allSatisfy { !$0.id.opaqueID.contains("@") })
    }

    @Test(arguments: ["kimi-code", "opencode-go"])
    func `a sole anonymous provider has stable normal quota identity`(wireID: String) throws {
        let json = "{\"data\":[{\"provider\":\"\(wireID)\",\"windows\":[{\"name\":\"7 days\",\"used\":8}]}]}"
        let first = try #require(self.project(json).first)
        let second = try #require(self.project(json).first)
        #expect(first.id == second.id)
        #expect(first.error == nil)
        #expect(first.accountEmail == nil)
        #expect(first.displayLabel == first.provider.displayName)
        #expect(first.windows.count == 1)
    }

    @Test
    func `ambiguous anonymous rows remain distinct error rows`() throws {
        let rows = try self.project("""
        {"data":[{"provider":"kimi-code","windows":[{"name":"5 hours","used":1}]},
          {"provider":"kimi-code","windows":[{"name":"5 hours","used":2}]}]}
        """)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { $0.error != nil })
        #expect(Set(rows.map(\.id)).count == 2)
    }

    @Test
    func `mixed identified and anonymous rows leave the anonymous row in error`() throws {
        let rows = try self.project("""
        {"data":[{"provider":"codex","user":"one@example.com"},{"provider":"codex"}]}
        """)
        #expect(rows.first { $0.accountEmail == nil }?.error != nil)
        #expect(rows.first { $0.accountEmail != nil }?.error == nil)
    }

    @Test
    func `empty windows have no local error and preserve upstream errors`() throws {
        let rows = try self.project("""
        {"data":[{"provider":"opencode-zen-free","windows":[]},
          {"provider":"other","error":"upstream unavailable","windows":[]}]}
        """)
        #expect(rows.first?.error == nil)
        #expect(rows.last?.error == "upstream unavailable")
    }

    @Test
    func `weekly and monthly names never default to the session lane`() throws {
        let rows = try self.project("""
        {"data":[{"provider":"kimi-code","windows":[{"name":"5 hours","used":3},
          {"name":"7 days","used":6},{"name":"Month","used":9}]}]}
        """)
        let account = try #require(rows.first)
        let usage = try #require(MagpieUsageProjection.usageSnapshot(for: account))
        #expect(usage.primary?.usedPercent == 6)
        #expect(usage.secondary?.usedPercent == 3)
        #expect(usage.tertiary?.windowMinutes == nil)
        #expect(account.windows.last?.semantics == .monthly)
        #expect(usage.providerCost == nil)
        #expect(usage.codexResetCredits == nil)
    }

    @Test
    func `reader sends one unauthenticated GET for every provider`() async throws {
        let rows = try await MagpieQuotasReader.readRows(quotasURL: nil) { request in
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            return (ClaudeMagpieFixture.quotasData,
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(Set(rows.map(\.provider)) == ["claude", "codex"])
    }
}
