import Foundation

/// 对齐 TortoiseSVN：多路径更新非原子，需先钉住仓库 HEAD 再统一 `-r`，避免 mixed-rev。
public enum UpdateRevisionPolicy: Sendable {
    /// 未显式指定 revision，且路径 ≥ 2 时，应先查询仓库 HEAD 再统一更新。
    public static func shouldPinRepositoryHead(paths: [String], revision: Revision?) -> Bool {
        revision == nil && paths.count >= 2
    }

    /// 用于查询 HEAD 的 info 目标：优先第一条路径，否则工作副本根。
    public static func headProbeTarget(paths: [String]) -> String {
        paths.first(where: { !$0.isEmpty && $0 != "." }) ?? "."
    }
}
