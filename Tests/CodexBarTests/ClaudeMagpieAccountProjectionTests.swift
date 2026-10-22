import CodexBarCore
import Foundation
import Testing

struct MagpieAccountProjectionTests {
    private func project(_ json: String) throws -> [MagpieAccountSnapshot] {
        try MagpieAccountProjection.snapshots(from: MagpieQuotasReader.rows(from: Data(json.utf8)))
    }

    @Test
    func `reset credits retain the earliest expiry and tolerate malformed metadata`() throws {
        let rows = try MagpieQuotasReader.rows(from: Data("""
        {"data":[
          {"provider":"codex","resets":{"count":2,"until":"2026-11-09T12:00:00.000Z",
            "each":[{"until":"2026-11-08T12:00:00.123Z"},{"until":"2026-11-06T12:00:00.456Z"}]}},
          {"provider":"codex","resets":{"count":1,"until":"2026-11-09T12:00:00.000Z"}},
          {"provider":"codex","resets":"broken","windows":[{"name":"5 hours","used":12}]},
          {"provider":"claude"},
          {"provider":"codex","resets":{"count":0}},
          {"provider":"codex","resets":{"until":"2026-11-09T12:00:00.000Z"}}
        ]}
        """.utf8))
        #expect(rows.count == 6)
        #expect(rows[0].resetCredits?.count == 2)
        #expect(rows[0].resetCredits?.nextExpiry == Date(timeIntervalSince1970: 1_793_966_400.456))
        #expect(rows[1].resetCredits?.nextExpiry == Date(timeIntervalSince1970: 1_794_225_600))
        #expect(rows[2].resetCredits == nil)
        #expect(rows[2].windows.first?.usedPercent == 12)
        #expect(rows[3...].allSatisfy { $0.resetCredits == nil })
        let accounts = MagpieAccountProjection.snapshots(from: [rows[0]])
        #expect(accounts.first?.resetCredits == rows[0].resetCredits)
    }

    @Test
    func `unlimited flags parse leniently and never project into native usage`() throws {
        let rows = try self.project("""
        {"data":[{"provider":"claude","windows":[
          {"name":"5 hours","used":0,"unlimited":true},
          {"name":"7 days","used":23,"unlimited":false},
          {"name":"Month","used":12,"unlimited":"unexpected"}]}]}
        """)
        let account = try #require(rows.first)
        #expect(account.windows.first?.unlimited == true)
        #expect(account.limitedWindows.map(\.name) == ["7 days", "Month"])
        let usage = try #require(MagpieUsageProjection.usageSnapshot(for: account))
        #expect(usage.primary == nil)
        #expect(usage.secondary?.usedPercent == 23)
        #expect(usage.tertiary?.usedPercent == 12)
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
        let grok = try #require(rows.first { $0.provider.nativeProvider == .grok })
        #expect(grok.provider.displayName == "Grok")
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

    @Test(arguments: [true, false])
    func `an unknown wire id spelling a mapped provider name keeps both cards`(unknownFirst: Bool) throws {
        let unknownRow = #"{"provider":"opencodego","user":"u@example.com","windows":[{"name":"Burst","used":9}]}"#
        let mappedRow = #"{"provider":"opencode-go","user":"k@example.com","windows":[{"name":"5 hours","used":4}]}"#
        let rows = try self.project(unknownFirst
            ? "{\"data\":[\(unknownRow),\(mappedRow)]}"
            : "{\"data\":[\(mappedRow),\(unknownRow)]}")
        #expect(rows.filter { $0.provider.nativeProvider == .opencodego }.count == 1)
        let unknown = rows.filter { $0.provider.nativeProvider == nil }
        #expect(unknown.count == 1)
        #expect(unknown.first?.provider.wireID == "opencodego")
        #expect(unknown.first?.windows.first?.name == "Burst")
    }

    @Test
    func `both grok wire ids without user fields merge into one normal card`() throws {
        let rows = try self.project("""
        {"data":[{"provider":"grok-plugin","windows":[{"name":"7 days","used":1}]},
          {"provider":"grok","windows":[{"name":"7 days","used":2}]}]}
        """)
        let grok = rows.filter { $0.provider.nativeProvider == .grok }
        #expect(grok.count == 1)
        #expect(grok.first?.error == nil)
        #expect(grok.first?.windows.map(\.usedPercent) == [2])
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
    func `endpoint credentials are rejected before transport`() async {
        do {
            _ = try await MagpieQuotasReader.readRows(quotasURL: "http://user:password@localhost:3425/quotas") { _ in
                Issue.record("An endpoint containing credentials must not reach transport")
                throw MagpieQuotasReaderError.invalidURL
            }
            Issue.record("An endpoint containing credentials must fail")
        } catch {
            #expect(error is MagpieQuotasReaderError)
        }
    }

    @Test
    func `reader sends one unauthenticated GET for every provider`() async throws {
        let rows = try await MagpieQuotasReader.readRows(quotasURL: nil) { request in
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            return (
                ClaudeMagpieFixture.quotasData,
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        #expect(Set(rows.map(\.provider)) == ["claude", "codex"])
    }
}
