import CodexBarCore
import Foundation

extension UsageStore {
    /// The tracker's CDN caches for a minute; Codex announces resets rarely, so this is plenty.
    static let codexScheduledResetMinInterval: TimeInterval = 30 * 60

    /// The reset to show now: gated at render time so a reset that has just passed disappears even
    /// before the next fetch.
    func visibleCodexScheduledReset(now: Date) -> CodexScheduledReset? {
        guard self.settings.codexScheduledResetVisible,
              let reset = self.codexScheduledReset, reset.isPending(at: now)
        else { return nil }
        return reset
    }

    /// Starts a background fetch without delaying the provider refresh that triggered it.
    func scheduleCodexScheduledResetRefresh(now: Date = Date()) {
        guard self.shouldFetchCodexScheduledReset(now: now), self.codexScheduledResetTask == nil else { return }
        self.codexScheduledResetTask = Task { @MainActor [weak self] in
            await self?.refreshCodexScheduledReset(now: now)
            self?.codexScheduledResetTask = nil
        }
    }

    func refreshCodexScheduledReset(now: Date = Date()) async {
        guard self.shouldFetchCodexScheduledReset(now: now) else { return }
        // A failed attempt waits out the interval too, so an unreachable service is not retried every refresh.
        self.codexScheduledResetLastAttemptAt = now
        do {
            self.codexScheduledReset = try await CodexScheduledResetReader.read(
                transport: self.codexScheduledResetTransport)
        } catch {
            // Keep the previous result: this is a courtesy badge, not worth an error in the UI.
        }
    }

    private func shouldFetchCodexScheduledReset(now: Date) -> Bool {
        guard self.settings.codexScheduledResetVisible,
              // Provider-specific by design: the tracker only reports Codex resets.
              self.enabledProvidersForDisplay().contains(UsageProvider.codex.instanceID)
        else { return false }
        if let last = self.codexScheduledResetLastAttemptAt,
           now.timeIntervalSince(last) < Self.codexScheduledResetMinInterval
        {
            return false
        }
        return true
    }
}
