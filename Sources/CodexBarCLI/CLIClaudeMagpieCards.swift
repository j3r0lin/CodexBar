import CodexBarCore
import Foundation

enum CLIClaudeMagpieCards {
    static func fetch(
        quotasURL: String?,
        renderOptions: CLIClaudeSwapCardsRenderOptions,
        transport: @escaping ClaudeMagpieAccountReader.Transport = ClaudeMagpieAccountReader.urlSessionTransport)
        async -> UsageCommandOutput
    {
        var output = UsageCommandOutput()
        do {
            let accounts = try await ClaudeMagpieAccountReader.readAccounts(
                quotasURL: quotasURL,
                now: renderOptions.now,
                transport: transport)
            output.cards = accounts.map { account in
                CLICardsRenderer.makeClaudeSwapCard(account: account, renderOptions: renderOptions)
            }
        } catch {
            let diagnostic = CLIClaudeSwapText.sanitizeDiagnostic(
                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            output.cardFailures.append(CLICardFailure(
                // Provider-specific by design: a magpie read failure is attached to the Claude card lane.
                provider: .claude,
                accountLabel: ClaudeMagpieAccountProjection.sourceLabel,
                message: diagnostic.isEmpty ? "magpie quota read failed." : diagnostic))
            output.exitCode = .failure
        }
        return output
    }
}
