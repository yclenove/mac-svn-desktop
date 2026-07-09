import Foundation

public protocol AISVNToolServicing: Sendable {
    func status(wc: URL) async throws -> [FileStatus]
    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String
    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry]
    func info(wc: URL, target: String) async throws -> SvnInfo
    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry]
    func blame(wc: URL, target: String) async throws -> [BlameLine]
    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data
}

public protocol AIToolAuditing: Sendable {
    func append(_ record: AISVNToolAuditRecord) async
}

public actor InMemoryAIToolAuditStore: AIToolAuditing {
    private var storedRecords: [AISVNToolAuditRecord] = []

    public init() {}

    public func append(_ record: AISVNToolAuditRecord) {
        storedRecords.append(record)
    }

    public func records(sessionID: String) -> [AISVNToolAuditRecord] {
        storedRecords.filter { $0.sessionID == sessionID }
    }
}

public struct AISVNToolRegistry: Sendable {
    private let service: any AISVNToolServicing
    private let auditStore: any AIToolAuditing

    public init(service: any AISVNToolServicing, auditStore: any AIToolAuditing) {
        self.service = service
        self.auditStore = auditStore
    }

    public func availableToolNames() -> [String] {
        AISVNToolName.allCases.map(\.rawValue)
    }

    public func handle(_ call: AISVNToolCall, sessionID: String) async throws -> AISVNToolDecision {
        guard let toolName = AISVNToolName(rawValue: call.name) else {
            let error = AISVNToolError.forbiddenTool(call.name)
            await audit(
                call: call,
                sessionID: sessionID,
                risk: nil,
                outcome: .failed,
                summary: String(describing: error)
            )
            throw error
        }

        do {
            switch toolName.risk {
            case .readOnly:
                let result = try await executeReadOnly(toolName, arguments: call.arguments)
                await audit(
                    call: call,
                    sessionID: sessionID,
                    risk: toolName.risk,
                    outcome: .completed,
                    summary: result.content
                )
                return .completed(result)
            case .lowRiskWrite, .highRiskWrite:
                let confirmation = try makeConfirmation(toolName, arguments: call.arguments)
                await audit(
                    call: call,
                    sessionID: sessionID,
                    risk: toolName.risk,
                    outcome: .confirmationRequired,
                    summary: confirmation.commandPreview
                )
                return .confirmationRequired(confirmation)
            }
        } catch {
            await audit(
                call: call,
                sessionID: sessionID,
                risk: toolName.risk,
                outcome: .failed,
                summary: String(describing: error)
            )
            throw error
        }
    }

    private func executeReadOnly(
        _ toolName: AISVNToolName,
        arguments: [String: String]
    ) async throws -> AISVNToolResult {
        switch toolName {
        case .svnStatus:
            let wc = try wcArgument(arguments)
            let statuses = try await service.status(wc: wc)
            return AISVNToolResult(
                content: statuses.map(formatStatus).joined(separator: "\n"),
                metadata: ["count": String(statuses.count)]
            )
        case .svnDiff:
            let wc = try wcArgument(arguments)
            let target = arguments["target"] ?? "."
            let diff = try await service.diff(
                wc: wc,
                target: target,
                r1: revisionArgument(arguments["r1"]),
                r2: revisionArgument(arguments["r2"])
            )
            return AISVNToolResult(content: diff, metadata: ["target": target])
        case .svnLog:
            let wc = try wcArgument(arguments)
            let target = arguments["target"] ?? "."
            let entries = try await service.log(
                wc: wc,
                target: target,
                from: revisionArgument(arguments["from"]) ?? Revision(0),
                batch: intArgument(arguments["batch"]) ?? 100,
                verbose: boolArgument(arguments["verbose"]) ?? true
            )
            return AISVNToolResult(
                content: entries.map(formatLogEntry).joined(separator: "\n"),
                metadata: ["count": String(entries.count)]
            )
        case .svnInfo:
            let wc = try wcArgument(arguments)
            let target = arguments["target"] ?? "."
            let info = try await service.info(wc: wc, target: target)
            let revision = info.revision.map { "r\($0.value)" } ?? "r?"
            return AISVNToolResult(
                content: "\(info.path) \(info.url) \(revision)",
                metadata: ["target": target]
            )
        case .svnList:
            let url = try requiredArgument("url", arguments: arguments)
            let entries = try await service.list(
                url: url,
                depth: SvnDepth(rawValue: arguments["depth"] ?? "") ?? .immediates,
                auth: nil
            )
            return AISVNToolResult(
                content: entries.map(formatRemoteEntry).joined(separator: "\n"),
                metadata: ["count": String(entries.count)]
            )
        case .svnBlame:
            let wc = try wcArgument(arguments)
            let target = try requiredArgument("target", arguments: arguments)
            let lines = try await service.blame(wc: wc, target: target)
            return AISVNToolResult(
                content: lines.map(formatBlameLine).joined(separator: "\n"),
                metadata: ["count": String(lines.count)]
            )
        case .svnCat:
            let url = try requiredArgument("url", arguments: arguments)
            let data = try await service.cat(
                url: url,
                revision: revisionArgument(arguments["revision"]),
                sizeLimit: intArgument(arguments["sizeLimit"]) ?? 5 * 1024 * 1024,
                auth: nil
            )
            return AISVNToolResult(
                content: String(decoding: data, as: UTF8.self),
                metadata: ["bytes": String(data.count)]
            )
        case .svnUpdate, .svnAdd, .svnCleanup, .svnCommit, .svnRevert, .svnMerge, .svnSwitch, .svnDelete, .svnCopy:
            throw AISVNToolError.invalidArgument(name: "tool", value: toolName.rawValue)
        }
    }

    private func audit(
        call: AISVNToolCall,
        sessionID: String,
        risk: AISVNToolRisk?,
        outcome: AISVNToolAuditOutcome,
        summary: String?
    ) async {
        await auditStore.append(AISVNToolAuditRecord(
            sessionID: sessionID,
            toolName: call.name,
            risk: risk,
            arguments: call.arguments,
            outcome: outcome,
            summary: summary
        ))
    }

    private func makeConfirmation(
        _ toolName: AISVNToolName,
        arguments: [String: String]
    ) throws -> AISVNToolConfirmation {
        let impactPaths = pathsArgument(arguments["paths"])
        let command: String

        switch toolName {
        case .svnUpdate:
            _ = try requiredArgument("wc", arguments: arguments)
            command = "svn update \(impactPaths.joined(separator: " "))".trimmingCharacters(in: .whitespaces)
        case .svnAdd:
            _ = try requiredArgument("wc", arguments: arguments)
            command = "svn add \(impactPaths.joined(separator: " "))".trimmingCharacters(in: .whitespaces)
        case .svnCleanup:
            _ = try requiredArgument("wc", arguments: arguments)
            command = "svn cleanup"
        case .svnCommit:
            _ = try requiredArgument("wc", arguments: arguments)
            let message = arguments["message"] ?? ""
            command = "svn commit \(impactPaths.joined(separator: " ")) -m \"\(message)\""
                .trimmingCharacters(in: .whitespaces)
        case .svnRevert:
            _ = try requiredArgument("wc", arguments: arguments)
            command = "svn revert \(impactPaths.joined(separator: " "))".trimmingCharacters(in: .whitespaces)
        case .svnMerge:
            _ = try requiredArgument("wc", arguments: arguments)
            let source = try requiredArgument("source", arguments: arguments)
            let range = arguments["range"].map { "-r \($0) " } ?? ""
            command = "svn merge \(range)\(source)"
        case .svnSwitch:
            _ = try requiredArgument("wc", arguments: arguments)
            let url = try requiredArgument("url", arguments: arguments)
            command = "svn switch \(url)"
        case .svnDelete:
            if let url = arguments["url"]?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
                command = "svn delete \(url)"
            } else {
                _ = try requiredArgument("wc", arguments: arguments)
                command = "svn delete \(impactPaths.joined(separator: " "))".trimmingCharacters(in: .whitespaces)
            }
        case .svnCopy:
            let source = try requiredArgument("source", arguments: arguments)
            let destination = try requiredArgument("destination", arguments: arguments)
            command = "svn copy \(source) \(destination)"
        case .svnStatus, .svnLog, .svnDiff, .svnInfo, .svnList, .svnBlame, .svnCat:
            throw AISVNToolError.invalidArgument(name: "tool", value: toolName.rawValue)
        }

        return AISVNToolConfirmation(
            toolName: toolName.rawValue,
            risk: toolName.risk,
            commandPreview: command,
            impactPaths: impactPaths,
            warning: warning(for: toolName.risk)
        )
    }

    private func wcArgument(_ arguments: [String: String]) throws -> URL {
        URL(fileURLWithPath: try requiredArgument("wc", arguments: arguments))
    }

    private func requiredArgument(_ name: String, arguments: [String: String]) throws -> String {
        guard let value = arguments[name]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            throw AISVNToolError.missingArgument(name)
        }
        return value
    }

    private func revisionArgument(_ value: String?) -> Revision? {
        guard let value, let revision = Int(value) else {
            return nil
        }
        return Revision(revision)
    }

    private func intArgument(_ value: String?) -> Int? {
        guard let value else {
            return nil
        }
        return Int(value)
    }

    private func boolArgument(_ value: String?) -> Bool? {
        guard let value else {
            return nil
        }
        return Bool(value)
    }

    private func pathsArgument(_ value: String?) -> [String] {
        guard let value else {
            return []
        }

        return value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func warning(for risk: AISVNToolRisk) -> String {
        switch risk {
        case .readOnly:
            return ""
        case .lowRiskWrite:
            return "需要确认后执行。"
        case .highRiskWrite:
            return "高危写操作，需要确认影响范围后执行。"
        }
    }

    private func formatStatus(_ status: FileStatus) -> String {
        "\(status.path) \(status.itemStatus.rawValue)"
    }

    private func formatLogEntry(_ entry: LogEntry) -> String {
        "r\(entry.revision.value) \(entry.author): \(entry.message)"
    }

    private func formatRemoteEntry(_ entry: RemoteEntry) -> String {
        "\(entry.path) \(entry.name)"
    }

    private func formatBlameLine(_ line: BlameLine) -> String {
        let revision = line.revision.map { "r\($0.value)" } ?? "r?"
        return "\(line.lineNumber) \(revision) \(line.author ?? "-")"
    }
}

extension SvnService: AISVNToolServicing {}
