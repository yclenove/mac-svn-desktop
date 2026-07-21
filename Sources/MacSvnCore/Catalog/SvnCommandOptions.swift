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
