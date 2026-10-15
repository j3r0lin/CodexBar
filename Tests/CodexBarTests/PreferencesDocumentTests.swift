import AppKit
import CodexBarCore
import Commander
import Testing
@testable import CodexBar
@testable import CodexBarCLI

@MainActor
struct PreferencesDocumentTests {
    private func store(_ suffix: String, defaults: UserDefaults = InMemoryUserDefaults()) -> SettingsStore {
        testSettingsStore(suiteName: "PreferencesDocumentTests-\(suffix)", userDefaults: defaults)
    }

    @Test
    func `portable preferences round trip uses existing defaults without touching config`() throws {
        let source = self.store("source")
        source.refreshFrequency = .fiveMinutes
        source.hidePersonalInfo = true
        source.mergeIcons = false
        source.weeklyProgressWorkDays = nil
        let target = self.store("target")
        target.weeklyProgressWorkDays = 4
        let configBefore = try target.configSnapshot.encodedData()
        let document = try PreferencesDocument(data: source.exportPreferences().encoded())
        try target.importPreferences(document)
        #expect(target.refreshFrequency == .fiveMinutes)
        #expect(target.hidePersonalInfo)
        #expect(!target.mergeIcons)
        #expect(target.weeklyProgressWorkDays == nil)
        #expect(try target.configSnapshot.encodedData() == configBefore)
        #expect(try target.exportPreferences().encoded() == source.exportPreferences().encoded())
    }

    @Test
    func `frontmost icon source survives app and CLI preference transfer`() throws {
        let defaults = InMemoryUserDefaults()
        let source = self.store("icon-source", defaults: defaults)
        source.unifiedIconSource = .frontmostApp
        let appDocument = try PreferencesDocument(data: source.exportPreferences().encoded())
        let cliDocument = try PreferencesDocument(defaults: defaults)
        for document in [appDocument, cliDocument] {
            let target = self.store("icon-target")
            try target.importPreferences(document)
            #expect(target.unifiedIconSource == .frontmostApp)
        }
    }

    @Test(arguments: [false, true])
    func `legacy icon preference import replaces a newer source`(highestUsage: Bool) throws {
        let settings = self.store("legacy-icon-source")
        settings.unifiedIconSource = .frontmostApp
        var document = PreferencesDocument()
        try document.set("menuBarShowsHighestUsage", highestUsage)
        try settings.importPreferences(document)
        #expect(settings.unifiedIconSource == (highestUsage ? .highestUsage : .currentSelection))
    }

    @Test
    func `queued icon preference imports respect latest choice in either format`() throws {
        let defaults = InMemoryUserDefaults()
        let settings = self.store("queued-icon-source", defaults: defaults)
        var current = PreferencesDocument()
        try current.set("unifiedIconSource", "frontmostApp")
        var legacy = PreferencesDocument()
        try legacy.set("menuBarShowsHighestUsage", true)

        try current.queueImport(in: defaults)
        try legacy.queueImport(in: defaults)
        settings.consumePendingPreferencesImport()
        #expect(settings.unifiedIconSource == .highestUsage)

        try legacy.queueImport(in: defaults)
        try current.queueImport(in: defaults)
        settings.consumePendingPreferencesImport()
        #expect(settings.unifiedIconSource == .frontmostApp)
    }

    @Test
    func `missing keys preserve existing preferences and legacy defaults`() throws {
        let defaults = InMemoryUserDefaults()
        defaults.set("twoMinutes", forKey: "refreshFrequency")
        defaults.set(true, forKey: "mergeIconsStacked")
        let settings = self.store("migration", defaults: defaults)
        settings.unifiedIconSource = .frontmostApp
        let document =
            try PreferencesDocument(data: Data(#"{"version":1,"preferences":{"hidePersonalInfo":true}}"#.utf8))
        try settings.importPreferences(document)
        #expect(settings.refreshFrequency == .twoMinutes)
        #expect(settings.mergeIconsStacked)
        #expect(settings.hidePersonalInfo)
        #expect(settings.unifiedIconSource == .frontmostApp)
    }

    @Test
    func `allowlist excludes secrets paths login consent and device identity`() throws {
        let defaults = InMemoryUserDefaults()
        for key in [
            "apiKey",
            "hooks",
            "launchAtLogin",
            "terminalApp",
            "jetbrainsIDEBasePath",
            "adaptiveActivityScanConsent",
            "iCloudSyncDeviceID",
            "iCloudSyncEnabled",
            "debugMenuEnabled",
        ] {
            defaults.set("PRIVATE-SENTINEL", forKey: key)
            let json = "{\"version\":1,\"preferences\":{\"\(key)\":\"PRIVATE-SENTINEL\"}}"
            #expect(throws: (any Error).self) { try PreferencesDocument(data: Data(json.utf8)) }
        }
        let json = try #require(String(data: PreferencesDocument(defaults: defaults).encoded(), encoding: .utf8))
        #expect(!json.contains("PRIVATE-SENTINEL"))
        #expect(!json.contains("launchAtLogin"))
    }

    @Test
    func `older exports with switcher settings still import`() throws {
        let settings = self.store("legacy-shortcuts")
        let json = #"{"version":1,"preferences":{"hidePersonalInfo":true,"switcherShowsIcons":false,"#
            + #""switcherShortcuts":{"next":"shift+right"}}}"#
        try settings.importPreferences(PreferencesDocument(data: Data(json.utf8)))
        #expect(settings.hidePersonalInfo)
        let exported = try String(bytes: settings.exportPreferences().encoded(), encoding: .utf8)
        #expect(exported?.contains("switcherShortcuts") == false)
        #expect(exported?.contains("switcherShowsIcons") == false)
    }

    @Test(arguments: [
        #"{"version":2,"preferences":{}}"#,
        #"{"version":1,"preferences":{"hidePersonalInfo":"true"}}"#,
        #"{"version":1,"preferences":{"weeklyProgressWorkDays":9}}"#,
        #"{"version":1,"preferences":{"refreshFrequency":"tomorrow"}}"#,
        #"{"version":1,"preferences":{"unifiedIconSource":"unknown"}}"#,
    ])
    func `invalid documents reject before any setters`(_ json: String) throws {
        #expect(throws: (any Error).self) { try PreferencesDocument(data: Data(json.utf8)) }
    }

    @Test
    func `queued CLI imports merge and are consumed through setters`() throws {
        let defaults = InMemoryUserDefaults()
        let settings = self.store("queued", defaults: defaults)
        var first = PreferencesDocument()
        try first.set("hidePersonalInfo", true)
        try first.queueImport(in: defaults)
        var second = PreferencesDocument()
        try second.set("mergeIcons", false)
        try second.queueImport(in: defaults)
        #expect(!settings.hidePersonalInfo)
        let pendingExport = try PreferencesDocument(defaults: defaults)
        #expect(try pendingExport.value("hidePersonalInfo", as: Bool.self) == true)
        settings.consumePendingPreferencesImport()
        #expect(settings.hidePersonalInfo)
        #expect(!settings.mergeIcons)
        #expect(defaults.data(forKey: PreferencesDocument.pendingImportKey) == nil)
        #expect(defaults.bool(forKey: "hidePersonalInfo"))
    }

    @Test
    func `overview import marks the selection edited for local active providers`() throws {
        let settings = self.store("overview")
        let active = settings.orderedProviders().filter { settings.providerEnablement[$0] ?? false }
            .compactMap(\.firstPartyProvider)
        try #require(!active.isEmpty)
        var document = PreferencesDocument()
        try document.set("mergedOverviewSelectedProviders", [String]())
        try settings.importPreferences(document)
        #expect(settings.resolvedMergedOverviewProviders(activeProviders: active).isEmpty)
        #expect(settings.userDefaults.stringArray(forKey: SettingsStore.mergedOverviewSelectionEditedActiveProvidersKey)
            == active.map(\.rawValue).sorted())
    }

    @Test
    func `imports preserve activity scan consent`() throws {
        let settings = self.store("consent")
        settings.adaptiveActivityScanConsent = .declined
        var document = PreferencesDocument()
        try document.set("refreshFrequency", "adaptiveAgentAware")
        try settings.importPreferences(document)
        #expect(settings.adaptiveActivityScanConsent == .declined)
        #expect(!settings.adaptiveActivityScanningEnabled)
    }

    @Test
    func `CLI preferences options expose file and alternate defaults domain`() throws {
        let parser = CommandParser(signature: CommandSignature.describe(ConfigPreferencesOptions()).flattened())
        let parsed = try parser.parse(arguments: [
            "--file",
            "/synthetic/preferences.json",
            "--defaults-domain",
            "fixture",
            "--json",
        ])
        #expect(parsed.options["file"] == ["/synthetic/preferences.json"])
        #expect(parsed.options["defaultsDomain"] == ["fixture"])
        #expect(CodexBarCLI._decodeFormatForTesting(from: parsed) == .json)
    }
}
