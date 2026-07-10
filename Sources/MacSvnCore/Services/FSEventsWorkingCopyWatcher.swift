import Foundation
import CoreServices

/// 工作副本本地文件变更监视（FSEvents），用于菜单栏近实时刷新（FR-EX-03）。
public protocol WorkingCopyChangeWatching: AnyObject, Sendable {
    /// 开始监视给定本地路径；路径变化时回调（可能合并多次事件）。
    func startWatching(paths: [String], onChange: @escaping @Sendable () -> Void)
    func stopWatching()
}

/// 基于 FSEvents 的目录树监视；忽略 `.svn` 元数据噪声由调用方 debounce 消化。
public final class FSEventsWorkingCopyWatcher: WorkingCopyChangeWatching, @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private var onChange: (@Sendable () -> Void)?
    private let latency: CFTimeInterval

    public init(latencySeconds: CFTimeInterval = 0.5) {
        self.latency = latencySeconds
    }

    deinit {
        stopWatching()
    }

    public func startWatching(paths: [String], onChange: @escaping @Sendable () -> Void) {
        stopWatching()
        let normalized = paths
            .map { ($0 as NSString).standardizingPath }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return }

        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSEventsWorkingCopyWatcher>.fromOpaque(info).takeUnretainedValue()
            watcher.onChange?()
        }

        let pathsToWatch = normalized as CFArray
        guard let created = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            pathsToWatch,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        ) else {
            return
        }

        stream = created
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        FSEventStreamStart(created)
    }

    public func stopWatching() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
        onChange = nil
    }
}
