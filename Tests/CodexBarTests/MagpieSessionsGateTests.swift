import Foundation
import Testing
@testable import CodexBarCLI
@testable import CodexBarCore

private actor RequestedPIDs {
    private(set) var pids: Set<Int32> = []

    func record(_ requested: [Int32]) {
        self.pids.formUnion(requested)
    }
}

struct MagpieSessionsGateTests {
    private static let processes = """
    301 1 Mon Jul 6 09:03:00 2026 /usr/local/bin/claude -p hi
    302 1 Tue Jul 7 09:03:00 2026 /usr/local/bin/codex exec
    """

    private static func scanner(recording pids: RequestedPIDs) -> LocalAgentSessionScanner {
        LocalAgentSessionScanner(
            processOutputProvider: { _ in Self.processes },
            cwdProvider: { requested, _ in
                await pids.record(requested)
                return Dictionary(uniqueKeysWithValues: requested.map { ($0, "/repo") })
            })
    }

    @Test
    func `sessions scan skips providers magpie owns`() async {
        let pids = RequestedPIDs()
        let source = CLIMagpieSource(
            transport: ClaudeMagpieFixture.transport(data: Data("""
            {"data":[{"provider":"codex","windows":[{"name":"5 hours","used":1}]}]}
            """.utf8)),
            ownedWireIDs: [])
        let sessions = await CodexBarCLI.scanNativeSessions(
            config: CodexBarConfig(providers: [], magpie: MagpieSourceConfig(enabled: true)),
            scanner: Self.scanner(recording: pids),
            source: source)
        // Codex is owned by a row; Claude is forbidden by the family rule while the switch is on.
        #expect(sessions.isEmpty)
        let requested = await pids.pids
        #expect(requested.isEmpty)
    }

    @Test
    func `sessions scan keeps native providers when the switch is off`() async {
        let pids = RequestedPIDs()
        let sessions = await CodexBarCLI.scanNativeSessions(
            config: CodexBarConfig(providers: []),
            scanner: Self.scanner(recording: pids))
        #expect(Set(sessions.compactMap(\.pid)) == [301, 302])
    }
}
