import CodexBarCore
import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

private actor RequestedProcessIDs {
    private(set) var pids: Set<Int32> = []

    func record(_ requested: [Int32]) {
        self.pids.formUnion(requested)
    }
}

private let sessionProcessOutput = """
301 1 Mon Jul 6 09:03:00 2026 /usr/local/bin/claude -p hi
302 1 Tue Jul 7 09:03:00 2026 /usr/local/bin/codex exec
"""

@MainActor
struct AgentSessionsStoreRouteTests {
    private func scannedStore(
        excluded: Set<AgentSession.Provider>,
        requested: RequestedProcessIDs) async -> AgentSessionsStore
    {
        let settings = testSettingsStore(suiteName: "AgentSessionsStoreRouteTests-\(UUID().uuidString)")
        settings.agentSessionsEnabled = true
        let scanner = LocalAgentSessionScanner(
            processOutputProvider: { _ in sessionProcessOutput },
            cwdProvider: { pids, _ in
                await requested.record(pids)
                return Dictionary(uniqueKeysWithValues: pids.map { ($0, "/repo") })
            })
        let store = AgentSessionsStore(settings: settings, localScanner: scanner)
        store.excludedProviders = { excluded }
        store.start()
        for _ in 0..<2000 where store.schedulerState.hasLocalImmediateTask || store.lastUpdatedAt == nil {
            await Task.yield()
        }
        return store
    }

    @Test
    func `local scan makes no reads for excluded providers`() async {
        let requested = RequestedProcessIDs()
        let store = await self.scannedStore(excluded: [.claude, .codex], requested: requested)
        #expect(store.localSessions.isEmpty)
        #expect(await requested.pids.isEmpty)
        store.stop()
    }

    @Test
    func `local scan is unchanged when nothing is excluded`() async {
        let requested = RequestedProcessIDs()
        let store = await self.scannedStore(excluded: [], requested: requested)
        #expect(Set(store.localSessions.compactMap(\.pid)) == [301, 302])
        store.stop()
    }
}
