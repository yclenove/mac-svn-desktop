import Foundation

/// 命令在 inventory 中的类别（主命令矩阵 vs Show Log 右键动作）。
public enum SvnCommandKind: String, Codable, Equatable, Sendable {
    /// inventory §3 命令 #1–46
    case primaryCommand
    /// inventory §5 日志右键 L01–L20
    case logAction
}

/// Tortoise 对标命令稳定 ID（与 inventory `#` / `L#` 对齐）。
///
/// T0 阶段：Catalog 必须齐全可枚举；实现可后续接线，未实现由 Navigator 返回 unimplemented。
public enum SvnCommandID: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    // MARK: - Primary #1–46
    case checkout = "cmd.01.checkout"
    case update = "cmd.02.update"
    case updateToRevision = "cmd.03.updateToRevision"
    case commit = "cmd.04.commit"
    case diff = "cmd.05.diff"
    case diffWithURL = "cmd.06.diffWithURL"
    case showLog = "cmd.07.showLog"
    case checkForModifications = "cmd.08.checkForModifications"
    case revisionGraph = "cmd.09.revisionGraph"
    case repoBrowser = "cmd.10.repoBrowser"
    case editConflicts = "cmd.11.editConflicts"
    case resolved = "cmd.12.resolved"
    case rename = "cmd.13.rename"
    case delete = "cmd.14.delete"
    case deleteKeepLocal = "cmd.15.deleteKeepLocal"
    case deleteUnversioned = "cmd.16.deleteUnversioned"
    case revert = "cmd.17.revert"
    case cleanup = "cmd.18.cleanup"
    case getLock = "cmd.19.getLock"
    case releaseLock = "cmd.20.releaseLock"
    case breakLock = "cmd.21.breakLock"
    case branchTag = "cmd.22.branchTag"
    case switchBranch = "cmd.23.switch"
    case merge = "cmd.24.merge"
    case mergeReintegrate = "cmd.25.mergeReintegrate"
    case export = "cmd.26.export"
    case relocate = "cmd.27.relocate"
    case createRepositoryHere = "cmd.28.createRepositoryHere"
    case add = "cmd.29.add"
    case importToRepository = "cmd.30.import"
    case blame = "cmd.31.blame"
    case addToIgnoreList = "cmd.32.addToIgnoreList"
    case createPatch = "cmd.33.createPatch"
    case applyPatch = "cmd.34.applyPatch"
    case properties = "cmd.35.properties"
    case copyMove = "cmd.36.copyMove"
    case shelve = "cmd.37.shelve"
    case changeLists = "cmd.38.changeLists"
    case externals = "cmd.39.externals"
    case compareRevisions = "cmd.40.compareRevisions"
    case saveRevisionOpen = "cmd.41.saveRevisionOpen"
    case mergeRevisionTo = "cmd.42.mergeRevisionTo"
    case importInPlace = "cmd.43.importInPlace"
    case removeFromVersionControl = "cmd.44.removeFromVersionControl"
    case repairMoveCopy = "cmd.45.repairMoveCopy"
    case repairFilenameCaseConflict = "cmd.46.repairFilenameCaseConflict"

    // MARK: - Log actions L01–L20
    case logCompareWithWorkingCopy = "log.L01.compareWithWorkingCopy"
    case logCompareWithPrevious = "log.L02.compareWithPrevious"
    case logCompareAndBlame = "log.L03.compareAndBlame"
    case logShowUnifiedDiff = "log.L04.showUnifiedDiff"
    case logSaveRevisionTo = "log.L05.saveRevisionTo"
    case logOpen = "log.L06.open"
    case logBlame = "log.L07.blame"
    case logBrowseRepository = "log.L08.browseRepository"
    case logCreateBranchTagFromRevision = "log.L09.createBranchTagFromRevision"
    case logUpdateItemToRevision = "log.L10.updateItemToRevision"
    case logRevertToThisRevision = "log.L11.revertToThisRevision"
    case logRevertChangesFromThisRevision = "log.L12.revertChangesFromThisRevision"
    case logMergeRevisionTo = "log.L13.mergeRevisionTo"
    case logCheckoutOrExport = "log.L14.checkoutOrExport"
    case logEditAuthorOrMessage = "log.L15.editAuthorOrMessage"
    case logShowRevisionProperties = "log.L16.showRevisionProperties"
    case logCopyToClipboard = "log.L17.copyToClipboard"
    case logFilterStatisticsOffline = "log.L18.filterStatisticsOffline"
    case logActionsColumnIcons = "log.L19.actionsColumnIcons"
    case logFetchStrategy = "log.L20.fetchStrategy"
}

/// 单条命令的元数据（展示名、inventory 编号、扩展菜单等）。
public struct SvnCommandDescriptor: Equatable, Sendable {
    public let id: SvnCommandID
    /// inventory 中的编号：主命令 1…46，日志动作 1…20（配合 `kind` 解读）
    public let inventoryNumber: Int
    public let kind: SvnCommandKind
    public let displayName: String
    /// 对应小乌龟 Shift 扩展菜单（🔷）
    public let isExtendedMenu: Bool
    public let keywords: [String]

    public init(
        id: SvnCommandID,
        inventoryNumber: Int,
        kind: SvnCommandKind,
        displayName: String,
        isExtendedMenu: Bool = false,
        keywords: [String] = []
    ) {
        self.id = id
        self.inventoryNumber = inventoryNumber
        self.kind = kind
        self.displayName = displayName
        self.isExtendedMenu = isExtendedMenu
        self.keywords = keywords
    }

    /// 稳定 inventory 键，例如 `cmd.08` / `log.L03`。
    public var inventoryKey: String {
        switch kind {
        case .primaryCommand:
            return String(format: "cmd.%02d", inventoryNumber)
        case .logAction:
            return String(format: "log.L%02d", inventoryNumber)
        }
    }
}

/// Tortoise 对标命令目录：全量可枚举、可按 ID / inventory 键查询。
public enum SvnCommandCatalog: Sendable {
    /// 主命令数量（inventory #1–46）。
    public static let primaryCommandCount = 46
    /// 日志右键动作数量（inventory L01–L20）。
    public static let logActionCount = 20

    public static var all: [SvnCommandDescriptor] { descriptors }

    public static var primaryCommands: [SvnCommandDescriptor] {
        descriptors.filter { $0.kind == .primaryCommand }
    }

    public static var logActions: [SvnCommandDescriptor] {
        descriptors.filter { $0.kind == .logAction }
    }

    public static var extendedMenuCommands: [SvnCommandDescriptor] {
        descriptors.filter(\.isExtendedMenu)
    }

    public static func descriptor(for id: SvnCommandID) -> SvnCommandDescriptor? {
        byID[id]
    }

    public static func descriptor(inventoryKey: String) -> SvnCommandDescriptor? {
        byInventoryKey[inventoryKey]
    }

    public static func primary(number: Int) -> SvnCommandDescriptor? {
        guard (1...primaryCommandCount).contains(number) else { return nil }
        return byInventoryKey[String(format: "cmd.%02d", number)]
    }

    public static func logAction(number: Int) -> SvnCommandDescriptor? {
        guard (1...logActionCount).contains(number) else { return nil }
        return byInventoryKey[String(format: "log.L%02d", number)]
    }

    /// Wave T1 日常命令子集：CFM 右键与 ⌘K 必须可到达（对齐已交付 #2–5,#7–8,#13–14,#17–18,#29,#32,#36,#45）。
    public static let dailyCFMCommandIDs: [SvnCommandID] = [
        .update,
        .commit,
        .diff,
        .diffWithURL,
        .showLog,
        .checkForModifications,
        .add,
        .delete,
        .revert,
        .cleanup,
        .rename,
        .addToIgnoreList,
        .copyMove,
        .repairMoveCopy,
        .editConflicts,
        .resolved,
        .getLock,
        .releaseLock,
        .breakLock,
        .branchTag,
        .switchBranch,
        .merge,
        .blame,
        .compareRevisions,
        .properties,
        .repairFilenameCaseConflict,
        .revisionGraph,
        .changeLists,
        .externals
    ]

    public static var dailyCFMCommands: [SvnCommandDescriptor] {
        dailyCFMCommandIDs.compactMap { descriptor(for: $0) }
    }

    /// 按标题 / keywords / inventoryKey 模糊匹配日常子集（供 ⌘K）。
    public static func searchDailyCFM(query: String, limit: Int = 20) -> [SvnCommandDescriptor] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let tokens = trimmed.lowercased().split(separator: " ").map(String.init)
        let scored: [(SvnCommandDescriptor, Int)] = dailyCFMCommands.compactMap { descriptor in
            let haystack = (
                [descriptor.displayName, descriptor.inventoryKey] + descriptor.keywords
            ).joined(separator: " ").lowercased()
            guard tokens.allSatisfy({ haystack.contains($0) }) else { return nil }
            var score = tokens.reduce(0) { $0 + $1.count }
            if haystack.hasPrefix(trimmed.lowercased()) { score += 50 }
            if descriptor.displayName.lowercased() == trimmed.lowercased() { score += 100 }
            return (descriptor, score)
        }
        return Array(
            scored.sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.displayName.localizedCaseInsensitiveCompare(rhs.0.displayName) == .orderedAscending
            }
            .prefix(max(1, limit))
            .map(\.0)
        )
    }

    // MARK: - Private table

    private static let byID: [SvnCommandID: SvnCommandDescriptor] = {
        Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
    }()

    private static let byInventoryKey: [String: SvnCommandDescriptor] = {
        Dictionary(uniqueKeysWithValues: descriptors.map { ($0.inventoryKey, $0) })
    }()

    private static let descriptors: [SvnCommandDescriptor] = {
        let primary: [(SvnCommandID, Int, String, Bool, [String])] = [
            (.checkout, 1, "检出", false, ["checkout", "co"]),
            (.update, 2, "更新", false, ["update", "up"]),
            (.updateToRevision, 3, "更新到修订", false, ["update to revision"]),
            (.commit, 4, "提交", false, ["commit", "ci"]),
            (.diff, 5, "比较差异", false, ["diff"]),
            (.diffWithURL, 6, "与 URL 比较", true, ["diff with url"]),
            (.showLog, 7, "显示日志", false, ["log", "history"]),
            (.checkForModifications, 8, "检查修改", false, ["cfm", "status", "check for modifications"]),
            (.revisionGraph, 9, "修订图", false, ["revision graph"]),
            (.repoBrowser, 10, "仓库浏览器", false, ["repo browser"]),
            (.editConflicts, 11, "编辑冲突", false, ["conflict", "merge"]),
            (.resolved, 12, "标记为已解决", false, ["resolved"]),
            (.rename, 13, "重命名", false, ["rename"]),
            (.delete, 14, "删除", false, ["delete", "remove"]),
            (.deleteKeepLocal, 15, "删除（保留本地）", true, ["delete keep local"]),
            (.deleteUnversioned, 16, "删除未版本项", true, ["delete unversioned"]),
            (.revert, 17, "还原", false, ["revert"]),
            (.cleanup, 18, "清理", false, ["cleanup"]),
            (.getLock, 19, "获取锁", false, ["lock"]),
            (.releaseLock, 20, "释放锁", false, ["unlock"]),
            (.breakLock, 21, "打断锁", true, ["break lock"]),
            (.branchTag, 22, "分支/标签", false, ["branch", "tag", "copy"]),
            (.switchBranch, 23, "切换", false, ["switch"]),
            (.merge, 24, "合并", false, ["merge"]),
            (.mergeReintegrate, 25, "重新整合合并", true, ["reintegrate"]),
            (.export, 26, "导出", false, ["export"]),
            (.relocate, 27, "重新定位", false, ["relocate"]),
            (.createRepositoryHere, 28, "在此创建仓库", false, ["svnadmin", "create repository"]),
            (.add, 29, "添加", false, ["add"]),
            (.importToRepository, 30, "导入", false, ["import"]),
            (.blame, 31, "追溯", false, ["blame", "annotate"]),
            (.addToIgnoreList, 32, "添加到忽略列表", false, ["ignore"]),
            (.createPatch, 33, "创建补丁", false, ["create patch"]),
            (.applyPatch, 34, "应用补丁", false, ["apply patch"]),
            (.properties, 35, "属性", false, ["properties", "props"]),
            (.copyMove, 36, "复制/移动", false, ["copy", "move"]),
            (.shelve, 37, "搁置", false, ["shelve", "unshelve"]),
            (.changeLists, 38, "变更列表", false, ["changelist"]),
            (.externals, 39, "外部定义", false, ["externals"]),
            (.compareRevisions, 40, "比较修订 / Blame 差异", false, ["compare revisions", "blame differences"]),
            (.saveRevisionOpen, 41, "另存修订 / 打开", false, ["save revision", "open"]),
            (.mergeRevisionTo, 42, "合并修订到…", false, ["merge revision to"]),
            (.importInPlace, 43, "就地导入", false, ["import in place"]),
            (.removeFromVersionControl, 44, "从版本控制移除", false, ["unversion", "remove from version control"]),
            (.repairMoveCopy, 45, "修复移动/复制", false, ["repair move", "repair copy"]),
            (.repairFilenameCaseConflict, 46, "修复文件名大小写冲突", false, ["case conflict"])
        ]

        let log: [(SvnCommandID, Int, String, Bool, [String])] = [
            (.logCompareWithWorkingCopy, 1, "与工作副本比较", false, ["compare with working copy"]),
            (.logCompareWithPrevious, 2, "与上一修订比较", false, ["compare with previous"]),
            (.logCompareAndBlame, 3, "比较并追溯", false, ["compare and blame"]),
            (.logShowUnifiedDiff, 4, "显示统一 Diff", false, ["unified diff"]),
            (.logSaveRevisionTo, 5, "另存修订到…", false, ["save revision to"]),
            (.logOpen, 6, "打开 / 打开方式", false, ["open", "open with"]),
            (.logBlame, 7, "追溯…", false, ["blame"]),
            (.logBrowseRepository, 8, "浏览仓库", false, ["browse repository"]),
            (.logCreateBranchTagFromRevision, 9, "从修订创建分支/标签", false, ["branch from revision"]),
            (.logUpdateItemToRevision, 10, "更新项到修订", false, ["update to revision"]),
            (.logRevertToThisRevision, 11, "还原到此修订", false, ["revert to this revision"]),
            (.logRevertChangesFromThisRevision, 12, "撤销此修订的更改", false, ["revert changes from this revision"]),
            (.logMergeRevisionTo, 13, "合并修订到…", false, ["merge revision to"]),
            (.logCheckoutOrExport, 14, "检出… / 导出…", false, ["checkout", "export"]),
            (.logEditAuthorOrMessage, 15, "编辑作者 / 日志说明", false, ["edit author", "edit log message"]),
            (.logShowRevisionProperties, 16, "显示修订属性", false, ["revision properties"]),
            (.logCopyToClipboard, 17, "复制到剪贴板", false, ["copy to clipboard"]),
            (.logFilterStatisticsOffline, 18, "过滤 / 统计 / 离线", false, ["filter", "statistics", "offline"]),
            (.logActionsColumnIcons, 19, "动作列图标", false, ["actions column"]),
            (.logFetchStrategy, 20, "日志拉取策略", false, ["stop-on-copy", "next 100", "show all"])
        ]

        let primaryDescriptors = primary.map {
            SvnCommandDescriptor(
                id: $0.0,
                inventoryNumber: $0.1,
                kind: .primaryCommand,
                displayName: $0.2,
                isExtendedMenu: $0.3,
                keywords: $0.4
            )
        }
        let logDescriptors = log.map {
            SvnCommandDescriptor(
                id: $0.0,
                inventoryNumber: $0.1,
                kind: .logAction,
                displayName: $0.2,
                isExtendedMenu: $0.3,
                keywords: $0.4
            )
        }
        return primaryDescriptors + logDescriptors
    }()
}
