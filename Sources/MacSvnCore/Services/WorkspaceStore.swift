import Foundation

public enum WorkspaceStoreError: Error, Equatable, Sendable {
    case invalidWorkingCopy(path: String)
}

public protocol WorkingCopyInfoProviding: Sendable {
    func info(wc: URL, target: String) async throws -> SvnInfo
}

public actor WorkspaceStore {
    private let store: PersistenceStore<WorkspaceListFile>
    private var cachedRecords: [WorkingCopyRecord] = []

    public init(fileURL: URL) {
        self.store = PersistenceStore(fileURL: fileURL, defaultValue: WorkspaceListFile())
    }

    public func load() throws -> [WorkingCopyRecord] {
        var file = try store.load()
        file.workspaces = file.workspaces.map { record in
            var record = record
            record.isValid = Self.isValidWorkingCopy(URL(fileURLWithPath: record.localPath))
            return record
        }
        cachedRecords = file.workspaces
        try store.save(file)
        return cachedRecords
    }

    public func records() -> [WorkingCopyRecord] {
        cachedRecords
    }

    @discardableResult
    public func addWorkingCopy(
        localPath: URL,
        repoURL: String,
        revision: Revision? = nil,
        username: String? = nil,
        name: String? = nil
    ) throws -> WorkingCopyRecord {
        let resolvedPath = localPath.resolvingSymlinksInPath()
        guard Self.isValidWorkingCopy(resolvedPath) else {
            throw WorkspaceStoreError.invalidWorkingCopy(path: localPath.path)
        }

        var records = try load()
        let now = Self.currentPersistableDate()
        let record = WorkingCopyRecord(
            id: UUID(),
            name: name ?? resolvedPath.lastPathComponent,
            localPath: resolvedPath.path,
            repoURL: repoURL,
            username: username,
            addedAt: now,
            lastOpenedAt: now,
            isValid: true,
            revision: revision
        )

        records.append(record)
        cachedRecords = records
        try store.save(WorkspaceListFile(workspaces: records))
        return record
    }

    @discardableResult
    public func addExistingWorkingCopy(
        localPath: URL,
        infoProvider: any WorkingCopyInfoProviding,
        username: String? = nil,
        name: String? = nil
    ) async throws -> WorkingCopyRecord {
        let resolvedPath = localPath.resolvingSymlinksInPath()
        guard Self.isValidWorkingCopy(resolvedPath) else {
            throw WorkspaceStoreError.invalidWorkingCopy(path: localPath.path)
        }

        let info = try await infoProvider.info(wc: resolvedPath, target: ".")
        return try addWorkingCopy(
            localPath: resolvedPath,
            repoURL: info.url,
            revision: info.revision,
            username: username,
            name: name
        )
    }

    public func removeWorkingCopy(id: UUID) throws {
        var records = try load()
        records.removeAll { $0.id == id }
        cachedRecords = records
        try store.save(WorkspaceListFile(workspaces: records))
    }

    private static func isValidWorkingCopy(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }

        var isMetadataDirectory: ObjCBool = false
        let metadataPath = url.appendingPathComponent(".svn", isDirectory: true).path
        return FileManager.default.fileExists(atPath: metadataPath, isDirectory: &isMetadataDirectory)
            && isMetadataDirectory.boolValue
    }

    private static func currentPersistableDate() -> Date {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    }
}
