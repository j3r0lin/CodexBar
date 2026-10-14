import CodexBarCore
import Foundation
import Testing

struct ClaudeMagpieAccountProjectionTests {
    @Test
    func `only Claude rows become account cards with the last served account first`() throws {
        let accounts = try ClaudeMagpieAccountProjection.accountSnapshots(from: ClaudeMagpieFixture.quotasData)

        #expect(accounts.map(\.accountEmail) == ["second@example.com", "first@example.com", "third@example.com"])
        #expect(accounts.map(\.isActive) == [true, false, false])
        #expect(accounts.allSatisfy { $0.provider == .claude && !$0.canActivate })
    }

    @Test
    func `windows map to session weekly and model scoped lanes`() throws {
        let accounts = try ClaudeMagpieAccountProjection.accountSnapshots(from: ClaudeMagpieFixture.quotasData)
        let first = try #require(accounts.first { $0.accountEmail == "first@example.com" })
        let snapshot = try #require(first.snapshot)

        #expect(snapshot.primary?.usedPercent == 12)
        #expect(snapshot.primary?.windowMinutes == 300)
        #expect(snapshot.primary?.resetsAt == ISO8601DateFormatter().date(from: "2026-10-14T13:10:00Z"))
        #expect(snapshot.secondary?.usedPercent == 76)
        #expect(snapshot.secondary?.windowMinutes == 10080)
        let scoped = try #require(snapshot.extraRateWindows)
        #expect(scoped.count == 1)
        #expect(scoped.first?.title.contains("Fable") == true)
        #expect(scoped.first?.window.usedPercent == 4)
        let readAt = try #require(ISO8601DateFormatter().date(from: "2026-10-14T08:44:16Z"))
        #expect(abs(snapshot.updatedAt.timeIntervalSince(readAt)) < 1)
    }

    @Test
    func `a window without a reset time is still shown`() throws {
        let accounts = try ClaudeMagpieAccountProjection.accountSnapshots(from: ClaudeMagpieFixture.quotasData)
        let second = try #require(accounts.first { $0.accountEmail == "second@example.com" })

        #expect(second.snapshot?.primary?.usedPercent == 0)
        #expect(second.snapshot?.primary?.resetsAt == nil)
        #expect(second.error == nil)
    }

    @Test
    func `an account without known windows has no usage and reports it`() throws {
        let accounts = try ClaudeMagpieAccountProjection.accountSnapshots(from: ClaudeMagpieFixture.quotasData)
        let third = try #require(accounts.first { $0.accountEmail == "third@example.com" })

        #expect(third.snapshot == nil)
        #expect(third.error != nil)
    }

    @Test
    func `identity is the lowercased email and the alias wins the label`() throws {
        let accounts = try ClaudeMagpieAccountProjection.accountSnapshots(from: ClaudeMagpieFixture.quotasData)
        let first = try #require(accounts.first { $0.accountEmail == "first@example.com" })
        let second = try #require(accounts.first { $0.accountEmail == "second@example.com" })

        #expect(first.id == ProviderAccountIdentity(source: "magpie", opaqueID: "claude:first@example.com"))
        #expect(first.displayLabel == "main")
        #expect(second.displayLabel == "second@example.com")
    }

    @Test
    func `shared emails are told apart by organization`() throws {
        let json = """
        {"data":[
          {"provider":"claude","user":"Shared@Example.com · Org A","windows":[{"name":"5 hours","used":1}]},
          {"provider":"claude","user":"shared@example.com · Org B","windows":[{"name":"5 hours","used":2}]}
        ]}
        """
        let accounts = try ClaudeMagpieAccountProjection.accountSnapshots(from: Data(json.utf8))

        #expect(Set(accounts.map(\.id)).count == 2)
        #expect(Set(accounts.map(\.displayLabel)) == ["Shared@Example.com · Org A", "shared@example.com · Org B"])
        #expect(accounts.first?.isActive == true)
    }

    @Test
    func `a malformed row does not discard its siblings`() throws {
        let json = """
        {"data":[{"user":"missing-provider@example.com"},
                 {"provider":"claude","user":"ok@example.com","windows":[{"name":"7 days","used":"x"},
                                                                       {"name":"7 days","used":30}]}]}
        """
        let accounts = try ClaudeMagpieAccountProjection.accountSnapshots(from: Data(json.utf8))

        #expect(accounts.count == 1)
        #expect(accounts.first?.snapshot?.secondary?.usedPercent == 30)
    }

    @Test
    func `a response without a data array is rejected`() {
        #expect(throws: ClaudeMagpieQuotasParserError.self) {
            try ClaudeMagpieAccountProjection.accountSnapshots(from: Data(#"{"error":"nope"}"#.utf8))
        }
    }
}

struct ClaudeMagpieAccountReaderTests {
    @Test
    func `reader requests the default local endpoint when no URL is configured`() async throws {
        let requested = RequestedURL()
        let accounts = try await ClaudeMagpieAccountReader.readAccounts(quotasURL: "") { request in
            await requested.set(request.url)
            return try await ClaudeMagpieFixture.transport()(request)
        }

        #expect(await requested.url?.absoluteString == ClaudeMagpieAccountReader.defaultQuotasURL)
        #expect(accounts.count == 3)
    }

    @Test
    func `HTTP errors fail the read`() async {
        await #expect(throws: ClaudeMagpieAccountReaderError.self) {
            try await ClaudeMagpieAccountReader.readAccounts(
                quotasURL: nil,
                transport: ClaudeMagpieFixture.transport(status: 503))
        }
    }

    @Test
    func `non http URLs are rejected without a request`() async {
        await #expect(throws: ClaudeMagpieAccountReaderError.self) {
            try await ClaudeMagpieAccountReader.readAccounts(quotasURL: "file:///etc/hosts") { _ in
                Issue.record("transport must not run")
                throw CancellationError()
            }
        }
    }
}

private actor RequestedURL {
    var url: URL?

    func set(_ url: URL?) {
        self.url = url
    }
}
