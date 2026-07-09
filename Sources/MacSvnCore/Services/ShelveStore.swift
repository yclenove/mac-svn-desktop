import Foundation

public actor ShelveStore {
    private static let maximumSafetySnapshots = 20

    private let rootDirectory: URL
    private let store: PersistenceStore<ShelveListFile>

    public init(rootDirectory: URL) {
        self.rootDirectory = rootDirectory
        self.store = PersistenceStore(
            fileURL: rootDirectory.appendingPathComponent("index.json"),
            defaultValue: ShelveListFile()
        )
    }

    public func load() throws -> [ShelveSnapshot] {
        try store.load().snapshots
    }

    @discardableResult
    public func createSnapshot(
        wc: URL,
        name: String,
        paths: [String],
        patchText: String,
        kind: ShelveKind
    ) async throws -> ShelveSnapshot {
        let id = UUID()
        let patchRelativePath = "\(kind.rawValue)/\(id.uuidString).patch"
        let patchURL = rootDirectory.appendingPathComponent(patchRelativePath)
        try FileManager.default.createDirectory(
            at: patchURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try patchText.write(to: patchURL, atomically: true, encoding: .utf8)

        let snapshot = ShelveSnapshot(
            id: id,
            wcPath: wc.path,
            name: name,
            paths: paths,
            patchRelativePath: patchRelativePath,
            createdAt: Self.currentPersistableDate(),
            kind: kind
        )

        var snapshots = try load()
        snapshots.append(snapshot)
        snapshots = try pruneSafetySnapshots(in: snapshots)
        try store.save(ShelveListFile(snapshots: snapshots))
        return snapshot
    }

    public func preview(_ snapshot: ShelveSnapshot) async throws -> String {
        let data = try Data(contentsOf: rootDirectory.appendingPathComponent(snapshot.patchRelativePath))
        return String(decoding: data, as: UTF8.self)
    }

    public func patchFileURL(for snapshot: ShelveSnapshot) -> URL {
        rootDirectory.appendingPathComponent(snapshot.patchRelativePath)
    }

    public func delete(_ snapshot: ShelveSnapshot) async throws {
        var snapshots = try load()
        snapshots.removeAll { $0.id == snapshot.id }
        try store.save(ShelveListFile(snapshots: snapshots))
        try? FileManager.default.removeItem(at: patchFileURL(for: snapshot))
    }

    private func pruneSafetySnapshots(in snapshots: [ShelveSnapshot]) throws -> [ShelveSnapshot] {
        let safetySnapshots = snapshots.filter { $0.kind == .safety }
        let overflow = safetySnapshots.count - Self.maximumSafetySnapshots
        guard overflow > 0 else {
            return snapshots
        }

        let removedSafetyIDs = Set(safetySnapshots.prefix(overflow).map(\.id))
        for snapshot in safetySnapshots where removedSafetyIDs.contains(snapshot.id) {
            try? FileManager.default.removeItem(at: patchFileURL(for: snapshot))
        }

        return snapshots.filter { !removedSafetyIDs.contains($0.id) }
    }

    private static func currentPersistableDate() -> Date {
        Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
    }
}
