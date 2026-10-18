import CodexBarCore
import Commander
import Foundation

extension CodexBarCLI {
    /// Scans local sessions of the providers read natively. Providers magpie owns (and the Claude
    /// family while the switch is on) are excluded from the scan itself and reported on stderr.
    static func scanNativeSessions(
        config: CodexBarConfig,
        scanner: LocalAgentSessionScanner = LocalAgentSessionScanner(),
        source: CLIMagpieSource = CLIMagpieSource()) async -> [AgentSession]
    {
        var excluded = Set<AgentSession.Provider>()
        for provider in AgentSession.Provider.allCases {
            guard let usageProvider = UsageProvider(rawValue: provider.rawValue) else { continue }
            let route = await source.route(for: usageProvider, configuration: config.magpie)
            if !route.isNative { excluded.insert(provider) }
        }
        if !excluded.isEmpty {
            let names = excluded.map(\.rawValue).sorted().joined(separator: ", ")
            Self.writeStderr("Skipping sessions for providers owned by magpie: \(names)\n")
        }
        return await scanner.scan(excludedProviders: excluded)
    }

    static func runSessions(_ values: ParsedValues) async {
        let config = Self.loadConfig(output: CLIOutputPreferences.from(values: values))
        let sessions = await Self.scanNativeSessions(config: config)
        if let jsonVersion = Self.sessionsJSONProtocolVersion(from: values) {
            Self.printJSON(
                Self.sessionsForJSON(sessions, includePiFamily: jsonVersion == 2),
                pretty: values.flags.contains("pretty"))
        } else {
            print(Self.renderSessionsTable(sessions))
        }
    }

    static func sessionsJSONProtocolVersion(from values: ParsedValues) -> Int? {
        if values.flags.contains("jsonV2") {
            return 2
        }
        if values.flags.contains("jsonShortcut") {
            return 1
        }
        return nil
    }

    static func sessionsForJSON(_ sessions: [AgentSession], includePiFamily: Bool) -> [AgentSession] {
        guard !includePiFamily else { return sessions }
        // Provider-specific by design: the legacy sessions JSON contract includes only native Codex/Claude scans.
        return sessions.filter { $0.provider == .codex || $0.provider == .claude }
    }

    static func runSessionsFocus(_ values: ParsedValues) async {
        guard let sessionID = values.positional.first, !sessionID.isEmpty else {
            writeStderr("Missing session id.\n")
            platformExit(1)
        }
        let config = Self.loadConfig(output: CLIOutputPreferences.from(values: values))
        let sessions = await Self.scanNativeSessions(config: config)
        guard let session = sessions.first(where: { $0.id == sessionID }) else {
            Self.writeStderr("Unknown session: \(sessionID)\n")
            Self.platformExit(1)
        }

        #if os(macOS)
        let result = await MainActor.run {
            SessionWindowFocuser.focus(session)
        }
        switch result {
        case .focused, .activatedApplicationOnly:
            Self.platformExit(0)
        case .failed:
            Self.writeStderr("Could not focus session: \(sessionID)\n")
            Self.platformExit(2)
        }
        #else
        Self.writeStderr("Session focus is only available on macOS.\n")
        Self.platformExit(2)
        #endif
    }

    static func renderSessionsTable(_ sessions: [AgentSession], now: Date = Date()) -> String {
        guard !sessions.isEmpty else { return "No agent sessions found." }
        let rows = sessions.map { session in
            [
                session.state == .active ? "active" : "idle",
                session.provider.rawValue,
                session.dialect?.rawValue ?? "—",
                session.source.rawValue,
                session.projectName ?? "—",
                Self.sessionAge(session, now: now),
                session.id,
            ]
        }
        let headers = ["STATE", "PROVIDER", "DIALECT", "SOURCE", "PROJECT", "ACTIVITY", "ID"]
        let widths = headers.indices.map { index in
            ([headers[index]] + rows.map { $0[index] }).map(\ .count).max() ?? headers[index].count
        }
        let render: ([String]) -> String = { columns in
            columns.indices.map { index in
                columns[index].padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }.joined(separator: "  ")
        }
        return ([render(headers)] + rows.map(render)).joined(separator: "\n")
    }

    private static func sessionAge(_ session: AgentSession, now: Date) -> String {
        guard let date = session.lastActivityAt ?? session.startedAt else { return "now" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 {
            return "\(seconds)s"
        }
        if seconds < 3600 {
            return "\(seconds / 60)m"
        }
        if seconds < 86400 {
            return "\(seconds / 3600)h"
        }
        return "\(seconds / 86400)d"
    }
}

struct SessionsOptions: CommanderParsable {
    @Flag(name: .long("json"), help: "Emit legacy JSON compatible with older clients")
    var jsonShortcut: Bool = false

    @Flag(name: .long("json-v2"), help: "Emit complete JSON, including Pi-family sessions")
    var jsonV2: Bool = false

    @Flag(name: .long("pretty"), help: "Pretty-print JSON output")
    var pretty: Bool = false
}

struct SessionsFocusOptions: CommanderParsable {
    @Argument(help: "Session identifier")
    var id: String = ""
}
