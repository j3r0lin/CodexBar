import AppKit
import CodexBarCore
import Testing
@testable import CodexBar

@MainActor
@Suite(.serialized)
struct StatusMenuSwitcherTrackingTests {
    @Test
    func `switcher rebuild scheduler runs during menu tracking exactly once`() {
        var runCount = 0
        ProviderSwitcherTrackingRunLoopScheduler.schedule {
            runCount += 1
        }

        CFRunLoopRunInMode(
            CFRunLoopMode(RunLoop.Mode.eventTracking.rawValue as CFString),
            0.1,
            true)
        #expect(runCount == 1)

        CFRunLoopRunInMode(.defaultMode, 0.1, true)
        #expect(runCount == 1)
    }

    private func makeSettings() -> SettingsStore {
        let suite = "StatusMenuSwitcherTrackingTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }
}
