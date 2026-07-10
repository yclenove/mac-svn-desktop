import Foundation

public protocol AISVNToolServicing: Sendable {
    func status(wc: URL) async throws -> [FileStatus]
    func diff(wc: URL, target: String, r1: Revision?, r2: Revision?) async throws -> String
    func log(wc: URL, target: String, from: Revision, batch: Int, verbose: Bool) async throws -> [LogEntry]
    func info(wc: URL, target: String) async throws -> SvnInfo
    func list(url: String, depth: SvnDepth, auth: Credential?) async throws -> [RemoteEntry]
    func blame(wc: URL, target: String) async throws -> [BlameLine]
    func cat(url: String, revision: Revision?, sizeLimit: Int, auth: Credential?) async throws -> Data

    // 写工具：仅在用户确认门通过后由 registry.executeConfirmed 调用
    func update(wc: URL, paths: [String], revision: Revision?, setDepth: SvnDepth?, ignoreExternals: Bool) async throws -> UpdateSummary
    func add(wc: URL, paths: [String]) async throws
    func cleanup(wc: URL) async throws
    func commit(wc: URL, paths: [String], message: String, auth: Credential?) async throws -> Revision
    func revert(wc: URL, paths: [String], recursive: Bool) async throws
    func merge(wc: URL, source: String, range: RevisionRange?, dryRun: Bool, auth: Credential?) async throws -> MergeSummary
    func switchTo(wc: URL, url: String, auth: Credential?, allowLocalChanges: Bool) async throws -> UpdateSummary
    func delete(wc: URL, paths: [String]) async throws
    func delete(url: String, message: String, auth: Credential?) async throws -> Revision
    func copy(source: String, destination: String, message: String, auth: Credential?) async throws -> Revision
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

    /// 用户确认门通过后真实执行写工具，并写入审计（FR-AI-04 / NFR-13）。
    public func executeConfirmed(
        toolName rawName: String,
        arguments: [String: String],
        sessionID: String
    ) async throws -> AISVNToolResult {
        guard let toolName = AISVNToolName(rawValue: rawName) else {
            let error = AISVNToolError.forbiddenTool(rawName)
            await audit(
                call: AISVNToolCall(name: rawName, arguments: arguments),
                sessionID: sessionID,
                risk: nil,
                outcome: .failed,
                summary: String(describing: error)
            )
            throw error
        }

        guard toolName.risk == .lowRiskWrite || toolName.risk == .highRiskWrite else {
            throw AISVNToolError.invalidArgument(name: "tool", value: rawName)
        }

        let call = AISVNToolCall(name: rawName, arguments: arguments)
        do {
            let result = try await executeWrite(toolName, arguments: arguments)
            await audit(
                call: call,
                sessionID: sessionID,
                risk: toolName.risk,
                outcome: .completed,
                summary: result.content
            )
            return result
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

    private func executeWrite(
        _ toolName: AISVNToolName,
        arguments: [String: String]
    ) async throws -> AISVNToolResult {
        switch toolName {
        case .svnUpdate:
            let wc = try wcArgument(arguments)
            let paths = pathsArgument(arguments["paths"])
            let summary = try await service.update(
                wc: wc,
                paths: paths,
                revision: revisionArgument(arguments["revision"]),
                setDepth: nil,
                ignoreExternals: arguments["ignoreExternals"] == "true"
            )
            return AISVNToolResult(
                content: "update 完成：updated=\(summary.updated) conflicted=\(summary.conflicted)",
                metadata: ["conflicted": String(summary.conflicted)]
            )
        case .svnAdd:
            let wc = try wcArgument(arguments)
            let paths = pathsArgument(arguments["paths"])
            guard !paths.isEmpty else {
                throw AISVNToolError.missingArgument("paths")
            }
            try await service.add(wc: wc, paths: paths)
            return AISVNToolResult(content: "add 完成：\(paths.joined(separator: ", "))")
        case .svnCleanup:
            let wc = try wcArgument(arguments)
            try await service.cleanup(wc: wc)
            return AISVNToolResult(content: "cleanup 完成：\(wc.path)")
        case .svnCommit:
            let wc = try wcArgument(arguments)
            let paths = pathsArgument(arguments["paths"])
            let message = try requiredArgument("message", arguments: arguments)
            let revision = try await service.commit(wc: wc, paths: paths, message: message, auth: nil)
            return AISVNToolResult(
                content: "commit 完成：r\(revision.value)",
                metadata: ["revision": String(revision.value)]
            )
        case .svnRevert:
            let wc = try wcArgument(arguments)
            let paths = pathsArgument(arguments["paths"])
            guard !paths.isEmpty else {
                throw AISVNToolError.missingArgument("paths")
            }
            try await service.revert(wc: wc, paths: paths, recursive: boolArgument(arguments["recursive"]) ?? false)
            return AISVNToolResult(content: "revert 完成：\(paths.joined(separator: ", "))")
        case .svnMerge:
            let wc = try wcArgument(arguments)
            let source = try requiredArgument("source", arguments: arguments)
            let summary = try await service.merge(
                wc: wc,
                source: source,
                range: revisionRangeArgument(arguments["range"]),
                dryRun: boolArgument(arguments["dryRun"]) ?? false,
                auth: nil
            )
            return AISVNToolResult(
                content: "merge 完成：conflicts=\(summary.conflicted)",
                metadata: ["conflicts": String(summary.conflicted)]
            )
        case .svnSwitch:
            let wc = try wcArgument(arguments)
            let url = try requiredArgument("url", arguments: arguments)
            let summary = try await service.switchTo(
                wc: wc,
                url: url,
                auth: nil,
                allowLocalChanges: boolArgument(arguments["allowLocalChanges"]) ?? false
            )
            return AISVNToolResult(
                content: "switch 完成：updated=\(summary.updated)",
                metadata: ["updated": String(summary.updated)]
            )
        case .svnDelete:
            if let url = arguments["url"]?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty {
                let message = arguments["message"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? arguments["message"]!
                    : "AI tool delete"
                let revision = try await service.delete(url: url, message: message, auth: nil)
                return AISVNToolResult(
                    content: "remote delete 完成：r\(revision.value)",
                    metadata: ["revision": String(revision.value)]
                )
            }
            let wc = try wcArgument(arguments)
            let paths = pathsArgument(arguments["paths"])
            guard !paths.isEmpty else {
                throw AISVNToolError.missingArgument("paths")
            }
            try await service.delete(wc: wc, paths: paths)
            return AISVNToolResult(content: "delete 完成：\(paths.joined(separator: ", "))")
        case .svnCopy:
            let source = try requiredArgument("source", arguments: arguments)
            let destination = try requiredArgument("destination", arguments: arguments)
            let message = arguments["message"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? arguments["message"]!
                : "AI tool copy"
            let revision = try await service.copy(
                source: source,
                destination: destination,
                message: message,
                auth: nil
            )
            return AISVNToolResult(
                content: "copy 完成：r\(revision.value)",
                metadata: ["revision": String(revision.value)]
            )
        case .svnStatus, .svnLog, .svnDiff, .svnInfo, .svnList, .svnBlame, .svnCat:
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

    /// 解析 `N:M` 或单 revision 字符串为 RevisionRange。
    private func revisionRangeArgument(_ value: String?) -> RevisionRange? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let colon = trimmed.firstIndex(of: ":") {
            let startText = String(trimmed[..<colon])
            let endText = String(trimmed[trimmed.index(after: colon)...])
            guard let start = Int(startText), let end = Int(endText) else { return nil }
            return RevisionRange(start: Revision(start), end: Revision(end))
        }
        guard let single = Int(trimmed) else { return nil }
        return RevisionRange(start: Revision(single), end: Revision(single))
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
