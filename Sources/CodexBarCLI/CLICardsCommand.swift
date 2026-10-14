import CodexBarCore
import Commander
import Foundation

struct CardsOptions: CommanderParsable {
    @OptionGroup
    var logging: CLILoggingOptions

    @OptionGroup
    var fetch: CLIUsageFetchOptions

    @Flag(name: .long("brief"), help: "Compact table layout instead of the card grid")
    var brief: Bool = false
}

extension CodexBarCLI {
    static func runCards(_ values: ParsedValues) async {
        let output = CLIOutputPreferences.from(values: values)
        let config = Self.loadConfig(output: output)
        let provider = Self.decodeProvider(from: values, config: config)
        let providerList = provider.asList
        let setup = Self.usageFetchSetup(values: values, providers: providerList, output: output, cardsLayout: true)
        let command = setup.command
        let tokenContext = setup.tokenContext(config: config, output: output)
        let brief = values.flags.contains("brief")
        // Provider-specific by design: claude-swap cards need Claude's integration configuration and subprocess.
        let claudeConfig = config.providerConfig(for: .claude)
        var cards: [CLICardModel] = []
        var failures: [CLICardFailure] = []
        var exitCode: ExitCode = .success

        for provider in providerList {
            let status = setup.includeStatus ? await Self.fetchStatus(for: provider) : nil
            let claudeMagpieEligible = CLIClaudeSwapCards.isEligible(
                provider: provider,
                integrationEnabled: claudeConfig?.claudeMagpieEnabled == true,
                hasExplicitAccountSelection: setup.tokenSelection.usesOverride,
                sourceModeOverride: command.sourceModeOverride)
            if claudeMagpieEligible {
                // magpie owns Claude accounts, so the ambient credential fetch and claude-swap never run.
                let result = await CLIClaudeMagpieCards.fetch(
                    quotasURL: claudeConfig?.sanitizedClaudeMagpieQuotasURL,
                    renderOptions: CLIClaudeSwapCardsRenderOptions(
                        status: status,
                        useColor: command.useColor,
                        resetStyle: command.resetStyle,
                        weeklyWorkDays: command.weeklyWorkDays,
                        now: Date()))
                if result.exitCode != .success {
                    exitCode = result.exitCode
                }
                cards.append(contentsOf: result.cards)
                failures.append(contentsOf: result.cardFailures)
                continue
            }
            let claudeSwapEligible = CLIClaudeSwapCards.isEligible(
                provider: provider,
                integrationEnabled: claudeConfig?.claudeSwapEnabled == true,
                hasExplicitAccountSelection: setup.tokenSelection.usesOverride,
                sourceModeOverride: command.sourceModeOverride)
            let result = await CLIClaudeSwapCards.fetch(
                eligible: claudeSwapEligible,
                executablePath: CLIClaudeSwapCards.executablePath(from: claudeConfig),
                showSingleAccount: claudeConfig?.claudeSwapShowSingleAccount == true,
                renderOptions: CLIClaudeSwapCardsRenderOptions(
                    status: status,
                    useColor: command.useColor,
                    resetStyle: command.resetStyle,
                    weeklyWorkDays: command.weeklyWorkDays,
                    now: Date()),
                ambientFetch: {
                    await ProviderInteractionContext.$current.withValue(.background) {
                        await Self.fetchUsageOutputs(
                            provider: provider,
                            status: status,
                            tokenContext: tokenContext,
                            command: command)
                    }
                })
            if result.exitCode != .success {
                exitCode = result.exitCode
            }
            cards.append(contentsOf: result.cards)
            failures.append(contentsOf: result.cardFailures)
        }

        let rendered: String
        let enhanced = CLITerminalCapabilities.supportsEnhancedCards(useColor: command.useColor)
        if brief {
            let rows = CLICardsBriefRenderer.makeRows(cards: cards)
            rendered = CLICardsBriefRenderer.render(
                rows: rows,
                failures: failures,
                terminalWidth: CLICardsRenderer.terminalColumnCount(),
                useColor: command.useColor,
                enhanced: enhanced)
        } else {
            rendered = CLICardsRenderer.render(
                cards: cards,
                failures: failures,
                terminalWidth: CLICardsRenderer.terminalColumnCount(),
                useColor: command.useColor,
                enhanced: enhanced)
        }
        if !rendered.isEmpty {
            print(rendered)
        }

        Self.exit(code: exitCode, output: output, kind: exitCode == .success ? .runtime : .provider)
    }
}
