import Foundation

/// 执行 Catalog 命令时的可选参数（T0 先覆盖常用字段，后续波次扩展）。
public struct SvnCommandOptions: Equatable, Sendable {
    public var revision: Revision?
    public var url: String?
    public var message: String?
    /// 预留扩展键值（避免过早膨胀强类型字段）。
    public var extras: [String: String]

    public init(
        revision: Revision? = nil,
        url: String? = nil,
        message: String? = nil,
        extras: [String: String] = [:]
    ) {
        self.revision = revision
        self.url = url
        self.message = message
        self.extras = extras
    }
}

/// Core 侧可表达的执行结果（不含 App 路由类型，便于单测与后续服务层复用）。
public enum SvnCommandDispatchKind: Equatable, Sendable {
    /// 已映射到应用内导航/工作区动作（由 App Navigator 解释具体 Route）。
    case navigable
    /// T0 允许：Catalog 有 ID，但业务尚未接线。
    case unimplemented
}
