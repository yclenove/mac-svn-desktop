import Foundation
import AppKit
import MacSvnCore

/// 认证失败时弹出用户名/密码对话框；密码经 `--password-from-stdin` 传递（由 AuthArguments 组装）。
public struct MacSvnInteractiveCredentialProvider: CredentialProviding, @unchecked Sendable {
    public init() {}

    public func credential(for wc: URL) async throws -> Credential? {
        await MainActor.run {
            let alert = NSAlert()
            alert.messageText = "需要 Subversion 凭据"
            alert.informativeText = "访问失败：\(wc.path)\n将使用 --username 与 --password-from-stdin（密码不进入 argv）。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")

            let usernameField = NSTextField(frame: NSRect(x: 0, y: 28, width: 280, height: 24))
            usernameField.placeholderString = "用户名"
            let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            passwordField.placeholderString = "密码"
            let stack = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 56))
            stack.addSubview(usernameField)
            stack.addSubview(passwordField)
            alert.accessoryView = stack

            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else {
                return nil
            }

            let username = usernameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let password = passwordField.stringValue
            guard !username.isEmpty else {
                return nil
            }
            return Credential(username: username, password: password)
        }
    }
}
