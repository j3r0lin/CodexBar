import CodexBarCore
import Foundation
import Testing
@testable import CodexBarCLI

struct CLICardsClaudeMagpieTests {
    private let renderOptions = CLIClaudeSwapCardsRenderOptions(
        status: nil,
        useColor: false,
        resetStyle: .countdown,
        weeklyWorkDays: nil,
        now: Date(timeIntervalSince1970: 1_791_000_000))

    @Test
    func `magpie accounts render one card each with the active account marked`() async {
        let output = await CLIClaudeMagpieCards.fetch(
            quotasURL: nil,
            renderOptions: self.renderOptions,
            transport: ClaudeMagpieFixture.transport())

        #expect(output.cards.count == 3)
        #expect(output.cards.filter(\.isActive).map(\.accountLine) == ["second@example.com"])
        #expect(output.cards.allSatisfy { $0.provider == .claude && $0.sourceLabel == "magpie" })
        #expect(output.cardFailures.isEmpty)
        #expect(output.exitCode == .success)
    }

    @Test
    func `an unreachable gateway fails without ambient cards`() async {
        let output = await CLIClaudeMagpieCards.fetch(
            quotasURL: nil,
            renderOptions: self.renderOptions,
            transport: ClaudeMagpieFixture.transport(status: 502))

        #expect(output.cards.isEmpty)
        #expect(output.cardFailures.map(\.provider) == [.claude])
        #expect(output.exitCode == .failure)
    }
}
