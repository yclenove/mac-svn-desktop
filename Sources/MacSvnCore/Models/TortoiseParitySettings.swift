import Foundation

public enum AppLanguage: String, Codable, CaseIterable, Equatable, Sendable {
    case system
    case simplifiedChinese
    case english

    public var displayName: String {
        switch self {
        case .system:
            return "跟随系统"
        case .simplifiedChinese:
            return "简体中文"
        case .english:
            return "English"
        }
    }

    public var localeIdentifier: String? {
        switch self {
        case .system:
            return nil
        case .simplifiedChinese:
            return "zh-Hans"
        case .english:
            return "en"
        }
    }
}

public struct GeneralSettings: Codable, Equatable, Sendable {
    public var language: AppLanguage
    public var checkForUpdatesAutomatically: Bool
    /// Apply locally changed `svn:externals` definitions while updating a working copy.
    public var applyLocalExternalsPropertyChanges: Bool

    public init(
        language: AppLanguage = .system,
        checkForUpdatesAutomatically: Bool = true,
        applyLocalExternalsPropertyChanges: Bool = false
    ) {
        self.language = language
        self.checkForUpdatesAutomatically = checkForUpdatesAutomatically
        self.applyLocalExternalsPropertyChanges = applyLocalExternalsPropertyChanges
    }
}

public struct DialogSettings: Codable, Equatable, Sendable {
    public var logFontName: String?
    public var logFontSize: Double
    public var useShortDateFormat: Bool
    public var doubleClickLogToComparePrevious: Bool
    public var useTrashWhenReverting: Bool
    public var defaultCheckoutPath: String
    public var defaultCheckoutURL: String
    public var recurseIntoUnversionedFolders: Bool
    public var enableCommitAutoCompletion: Bool
    public var autoCompletionTimeoutSeconds: Int
    public var commitMessageHistoryLimit: Int
    public var selectCommitItemsAutomatically: Bool
    public var reopenCommitAfterSuccessWithRemainingItems: Bool
    public var contactRepositoryOnChangesOpen: Bool
    public var showLockDialogBeforeLocking: Bool
    public var preFetchRepositoryDirectories: Bool
    public var showRepositoryExternals: Bool

    public init(
        logFontName: String? = nil,
        logFontSize: Double = 12,
        useShortDateFormat: Bool = false,
        doubleClickLogToComparePrevious: Bool = false,
        useTrashWhenReverting: Bool = true,
        defaultCheckoutPath: String = "",
        defaultCheckoutURL: String = "",
        recurseIntoUnversionedFolders: Bool = true,
        enableCommitAutoCompletion: Bool = true,
        autoCompletionTimeoutSeconds: Int = 5,
        commitMessageHistoryLimit: Int = 25,
        selectCommitItemsAutomatically: Bool = true,
        reopenCommitAfterSuccessWithRemainingItems: Bool = false,
        contactRepositoryOnChangesOpen: Bool = false,
        showLockDialogBeforeLocking: Bool = true,
        preFetchRepositoryDirectories: Bool = false,
        showRepositoryExternals: Bool = false
    ) {
        self.logFontName = logFontName
        self.logFontSize = logFontSize
        self.useShortDateFormat = useShortDateFormat
        self.doubleClickLogToComparePrevious = doubleClickLogToComparePrevious
        self.useTrashWhenReverting = useTrashWhenReverting
        self.defaultCheckoutPath = defaultCheckoutPath
        self.defaultCheckoutURL = defaultCheckoutURL
        self.recurseIntoUnversionedFolders = recurseIntoUnversionedFolders
        self.enableCommitAutoCompletion = enableCommitAutoCompletion
        self.autoCompletionTimeoutSeconds = autoCompletionTimeoutSeconds
        self.commitMessageHistoryLimit = commitMessageHistoryLimit
        self.selectCommitItemsAutomatically = selectCommitItemsAutomatically
        self.reopenCommitAfterSuccessWithRemainingItems = reopenCommitAfterSuccessWithRemainingItems
        self.contactRepositoryOnChangesOpen = contactRepositoryOnChangesOpen
        self.showLockDialogBeforeLocking = showLockDialogBeforeLocking
        self.preFetchRepositoryDirectories = preFetchRepositoryDirectories
        self.showRepositoryExternals = showRepositoryExternals
    }

    private enum CodingKeys: String, CodingKey {
        case logFontName
        case logFontSize
        case useShortDateFormat
        case doubleClickLogToComparePrevious
        case useTrashWhenReverting
        case defaultCheckoutPath
        case defaultCheckoutURL
        case recurseIntoUnversionedFolders
        case enableCommitAutoCompletion
        case autoCompletionTimeoutSeconds
        case commitMessageHistoryLimit
        case selectCommitItemsAutomatically
        case reopenCommitAfterSuccessWithRemainingItems
        case contactRepositoryOnChangesOpen
        case showLockDialogBeforeLocking
        case preFetchRepositoryDirectories
        case showRepositoryExternals
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            logFontName: try container.decodeIfPresent(String.self, forKey: .logFontName),
            logFontSize: try container.decodeIfPresent(Double.self, forKey: .logFontSize) ?? 12,
            useShortDateFormat: try container.decodeIfPresent(Bool.self, forKey: .useShortDateFormat) ?? false,
            doubleClickLogToComparePrevious: try container.decodeIfPresent(Bool.self, forKey: .doubleClickLogToComparePrevious) ?? false,
            useTrashWhenReverting: try container.decodeIfPresent(Bool.self, forKey: .useTrashWhenReverting) ?? true,
            defaultCheckoutPath: try container.decodeIfPresent(String.self, forKey: .defaultCheckoutPath) ?? "",
            defaultCheckoutURL: try container.decodeIfPresent(String.self, forKey: .defaultCheckoutURL) ?? "",
            recurseIntoUnversionedFolders: try container.decodeIfPresent(Bool.self, forKey: .recurseIntoUnversionedFolders) ?? true,
            enableCommitAutoCompletion: try container.decodeIfPresent(Bool.self, forKey: .enableCommitAutoCompletion) ?? true,
            autoCompletionTimeoutSeconds: try container.decodeIfPresent(Int.self, forKey: .autoCompletionTimeoutSeconds) ?? 5,
            commitMessageHistoryLimit: try container.decodeIfPresent(Int.self, forKey: .commitMessageHistoryLimit) ?? 25,
            selectCommitItemsAutomatically: try container.decodeIfPresent(Bool.self, forKey: .selectCommitItemsAutomatically) ?? true,
            reopenCommitAfterSuccessWithRemainingItems: try container.decodeIfPresent(Bool.self, forKey: .reopenCommitAfterSuccessWithRemainingItems) ?? false,
            contactRepositoryOnChangesOpen: try container.decodeIfPresent(Bool.self, forKey: .contactRepositoryOnChangesOpen) ?? false,
            showLockDialogBeforeLocking: try container.decodeIfPresent(Bool.self, forKey: .showLockDialogBeforeLocking) ?? true,
            preFetchRepositoryDirectories: try container.decodeIfPresent(Bool.self, forKey: .preFetchRepositoryDirectories) ?? false,
            showRepositoryExternals: try container.decodeIfPresent(Bool.self, forKey: .showRepositoryExternals) ?? false
        )
    }
}

public enum AppAppearance: String, Codable, CaseIterable, Equatable, Sendable {
    case light
    case dark
}

public struct AdaptiveColour: Codable, Equatable, Hashable, Sendable {
    public let lightHex: String
    public let darkHex: String

    public static let fallback = AdaptiveColour(normalizedLightHex: "#000000", normalizedDarkHex: "#FFFFFF")

    public init(
        lightHex: String,
        darkHex: String,
        fallback: AdaptiveColour = .fallback
    ) {
        self.lightHex = Self.normalizedHex(lightHex) ?? fallback.lightHex
        self.darkHex = Self.normalizedHex(darkHex) ?? fallback.darkHex
    }

    public func hex(for appearance: AppAppearance) -> String {
        switch appearance {
        case .light:
            return lightHex
        case .dark:
            return darkHex
        }
    }

    private init(normalizedLightHex: String, normalizedDarkHex: String) {
        lightHex = normalizedLightHex
        darkHex = normalizedDarkHex
    }

    private static func normalizedHex(_ value: String) -> String? {
        var candidate = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if candidate.hasPrefix("#") {
            candidate.removeFirst()
        }
        guard candidate.count == 6 || candidate.count == 8 else {
            return nil
        }
        let hexadecimalDigits = CharacterSet(charactersIn: "0123456789ABCDEF")
        guard candidate.unicodeScalars.allSatisfy({ hexadecimalDigits.contains($0) }) else {
            return nil
        }
        return "#\(candidate)"
    }

    private enum CodingKeys: String, CodingKey {
        case lightHex
        case darkHex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            lightHex: try container.decodeIfPresent(String.self, forKey: .lightHex) ?? "",
            darkHex: try container.decodeIfPresent(String.self, forKey: .darkHex) ?? ""
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(lightHex, forKey: .lightHex)
        try container.encode(darkHex, forKey: .darkHex)
    }
}

public enum ChangeColourRole: String, Codable, CaseIterable, Equatable, Sendable {
    case modified
    case added
    case deleted
    case merged
    case conflicted
}

public struct ChangeColourPalette: Codable, Equatable, Sendable {
    public var modified: AdaptiveColour
    public var added: AdaptiveColour
    public var deleted: AdaptiveColour
    public var merged: AdaptiveColour
    public var conflicted: AdaptiveColour

    public init(
        modified: AdaptiveColour = AdaptiveColour(lightHex: "#9A6700", darkHex: "#D29922"),
        added: AdaptiveColour = AdaptiveColour(lightHex: "#1A7F37", darkHex: "#3FB950"),
        deleted: AdaptiveColour = AdaptiveColour(lightHex: "#CF222E", darkHex: "#F85149"),
        merged: AdaptiveColour = AdaptiveColour(lightHex: "#0969DA", darkHex: "#58A6FF"),
        conflicted: AdaptiveColour = AdaptiveColour(lightHex: "#8250DF", darkHex: "#BC8CFF")
    ) {
        self.modified = modified
        self.added = added
        self.deleted = deleted
        self.merged = merged
        self.conflicted = conflicted
    }

    public func colour(for role: ChangeColourRole) -> AdaptiveColour {
        switch role {
        case .modified:
            return modified
        case .added:
            return added
        case .deleted:
            return deleted
        case .merged:
            return merged
        case .conflicted:
            return conflicted
        }
    }

    public func hex(for role: ChangeColourRole, appearance: AppAppearance) -> String {
        colour(for: role).hex(for: appearance)
    }

    public func role(for itemStatus: ItemStatus) -> ChangeColourRole? {
        switch itemStatus {
        case .modified:
            return .modified
        case .added:
            return .added
        case .deleted, .missing, .replaced:
            return .deleted
        case .conflicted, .obstructed:
            return .conflicted
        case .unversioned, .normal, .ignored, .external, .incomplete, .none:
            return nil
        }
    }

    public func hex(forItemStatus itemStatus: ItemStatus, appearance: AppAppearance) -> String? {
        role(for: itemStatus).map { hex(for: $0, appearance: appearance) }
    }

    public func role(for kind: UnifiedDiffLineKind) -> ChangeColourRole? {
        switch kind {
        case .addition: return .added
        case .deletion: return .deleted
        case .metadata, .hunk, .context, .noNewlineMarker: return nil
        }
    }

    public func role(for kind: SideBySideDiffCellKind) -> ChangeColourRole? {
        switch kind {
        case .addition: return .added
        case .deletion: return .deleted
        case .modified: return .modified
        case .context: return nil
        }
    }

    public func role(for action: ChangedPathAction) -> ChangeColourRole? {
        switch action {
        case .added: return .added
        case .modified: return .modified
        case .deleted, .replaced: return .deleted
        case .unknown: return nil
        }
    }

    public func role(for action: MergeAction) -> ChangeColourRole? {
        switch action {
        case .added: return .added
        case .updated: return .modified
        case .deleted, .replaced: return .deleted
        case .conflicted: return .conflicted
        case .merged: return .merged
        case .existed, .unknown: return nil
        }
    }
}

public struct SvnProxySettings: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var host: String
    public var port: Int
    public var exceptions: [String]
    public var username: String

    public init(
        enabled: Bool = false,
        host: String = "",
        port: Int = 8080,
        exceptions: [String] = [],
        username: String = ""
    ) {
        self.enabled = enabled
        self.host = host
        self.port = port
        self.exceptions = exceptions
        self.username = username
    }
}

public struct SvnNetworkSettings: Codable, Equatable, Sendable {
    public var proxy: SvnProxySettings
    public var sshExecutablePath: String?
    public var sshArguments: [String]

    public init(
        proxy: SvnProxySettings = SvnProxySettings(),
        sshExecutablePath: String? = nil,
        sshArguments: [String] = []
    ) {
        self.proxy = proxy
        self.sshExecutablePath = sshExecutablePath
        self.sshArguments = sshArguments
    }
}
