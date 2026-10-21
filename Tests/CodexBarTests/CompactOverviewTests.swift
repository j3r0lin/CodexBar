import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CompactOverviewTests {
    private static func settings(_ defaults: InMemoryUserDefaults) -> SettingsStore {
        ProviderUsageItemVisibilityTests.settings(
            defaults: defaults,
            configStore: testConfigStore(suiteName: "CompactOverviewTests-\(UUID().uuidString)"))
    }

    private static func model(provider: UsageProvider = .zai) throws -> UsageMenuCardView.Model {
        try UsageMenuCardView.Model(
            provider: provider,
            providerName: "Example provider",
            email: "",
            subtitleText: "Updated just now",
            subtitleStyle: .info,
            planText: nil,
            metrics: [.init(
                id: "primary",
                title: "Weekly",
                percent: 25,
                percentStyle: .used,
                resetText: "Resets in 2d",
                detailText: "Example detail",
                detailLeftText: nil,
                detailRightText: nil,
                pacePercent: nil,
                paceOnTop: true)],
            usageNotes: [],
            providerDetails: [ProviderDetailSection(
                title: "Account balance", rows: [.init(label: "Balance", value: "$12.00")])],
            openAIAPIUsage: nil,
            inlineUsageDashboard: nil,
            providerCost: nil,
            tokenUsage: nil,
            placeholder: nil,
            progressColor: .blue)
    }
}
