import CodexBarCore
import Foundation

enum CLIClaudeMagpieCards {
    static func fetch(
        quotasURL: String?,
        renderOptions: CLIClaudeSwapCardsRenderOptions,
        transport: @escaping MagpieQuotasReader.Transport = MagpieQuotasReader.urlSessionTransport)
        async -> UsageCommandOutput
    {
        var output = UsageCommandOutput()
        do {
            let rows = try await MagpieQuotasReader.readRows(quotasURL: quotasURL, transport: transport)
            // Provider-specific by design: this legacy cards command renders only Claude account cards.
            let accounts = MagpieUsageProjection.providerAccountSnapshots(
                for: .claude, in: MagpieAccountProjection.snapshots(from: rows), now: renderOptions.now)
            output.cards = accounts.map { account in
                CLICardsRenderer.makeClaudeSwapCard(account: account, renderOptions: renderOptions)
            }
        } catch {
            let diagnostic = CLIClaudeSwapText.sanitizeDiagnostic(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            output.cardFailures.append(CLICardFailure(
                // Provider-specific by design: a magpie read failure is attached to the Claude card lane.
                provider: .claude,
                accountLabel: MagpieAccountProjection.sourceLabel,
                message: diagnostic.isEmpty ? "magpie quota read failed." : diagnostic))
            output.exitCode = .failure
        }
        return output
    }
}
