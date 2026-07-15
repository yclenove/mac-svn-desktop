import Foundation
import XCTest
@testable import MacSvnCore

final class SvnClientConfigurationStoreTests: XCTestCase {
    private var roots: [URL] = []

    override func tearDownWithError() throws {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots.removeAll()
        try super.tearDownWithError()
    }

    func testResolverPrefersOverrideThenEnvironmentThenHomeSubversion() {
        let home = temporaryRoot()
        let override = home.appendingPathComponent("override")
        let environment = home.appendingPathComponent("environment")

        XCTAssertEqual(
            SvnConfigurationDirectoryResolver(
                overrideURL: override,
                environment: ["SVN_CONFIG_DIR": environment.path],
                homeDirectoryURL: home
            ).resolve().path,
            override.path
        )
        XCTAssertEqual(
            SvnConfigurationDirectoryResolver(
                environment: ["SVN_CONFIG_DIR": environment.path],
                homeDirectoryURL: home
            ).resolve().path,
            environment.path
        )
        XCTAssertEqual(
            SvnConfigurationDirectoryResolver(environment: [:], homeDirectoryURL: home).resolve().path,
            home.appendingPathComponent(".subversion", isDirectory: true).path
        )
    }

    func testUpdateCreatesFilesPreservesUnknownContentAndRoundTripsManagedValues() throws {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config")
        let servers = root.appendingPathComponent("servers")
        try Data("# keep config comment\n[auth]\npassword-stores = keychain\n\n[miscellany]\nenable-auto-props = yes\n".utf8).write(to: config)
        try Data("# keep servers comment\n[groups]\ncorp = *.example.com\n".utf8).write(to: servers)
        let store = SvnClientConfigurationStore(directoryURL: root)
        let managed = SvnClientManagedConfiguration(
            globalIgnorePatterns: ["*.o", ".DS_Store", "build"],
            useCommitTimes: true,
            network: SvnNetworkSettings(
                proxy: SvnProxySettings(
                    enabled: true,
                    host: "proxy.example.com",
                    port: 3128,
                    exceptions: ["localhost", "*.internal"],
                    username: "developer"
                ),
                sshExecutablePath: "/Applications/SSH Tool/bin/ssh",
                sshArguments: ["-q", "-o", "IdentityFile=/tmp/key with spaces"]
            )
        )

        try store.update(managed)

        XCTAssertEqual(try store.load(), managed)
        let configText = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(configText.contains("# keep config comment"))
        XCTAssertTrue(configText.contains("[auth]\npassword-stores = keychain"))
        XCTAssertTrue(configText.contains("enable-auto-props = yes"))
        XCTAssertTrue(configText.contains("global-ignores = *.o .DS_Store build"))
        XCTAssertTrue(configText.contains("use-commit-times = yes"))
        XCTAssertTrue(configText.contains("[tunnels]"))
        XCTAssertTrue(configText.contains("ssh = '/Applications/SSH Tool/bin/ssh' -q -o 'IdentityFile=/tmp/key with spaces'"))
        let serversText = try String(contentsOf: servers, encoding: .utf8)
        XCTAssertTrue(serversText.contains("# keep servers comment"))
        XCTAssertTrue(serversText.contains("corp = *.example.com"))
        XCTAssertTrue(serversText.contains("http-proxy-host = proxy.example.com"))
        XCTAssertTrue(serversText.contains("http-proxy-port = 3128"))
        XCTAssertTrue(serversText.contains("http-proxy-exceptions = localhost, *.internal"))
        XCTAssertTrue(serversText.contains("http-proxy-username = developer"))
        let permissions = try FileManager.default.attributesOfItem(atPath: servers.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue ?? -1, 0o600)
    }

    func testUpdateRemovesDisabledProxyAndEmptySSHWithoutTouchingOtherKeys() throws {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config")
        let servers = root.appendingPathComponent("servers")
        try Data("[miscellany]\nglobal-ignores = old\nuse-commit-times = yes\n[tunnels]\nssh = /custom/ssh -q\nother = /other/tunnel\n".utf8).write(to: config)
        try Data("[global]\nhttp-proxy-host = old\nhttp-proxy-port = 80\nhttp-proxy-exceptions = localhost\nhttp-proxy-username = old-user\nhttp-proxy-password = old-secret\nstore-passwords = no\n".utf8).write(to: servers)
        let store = SvnClientConfigurationStore(directoryURL: root)

        try store.update(SvnClientManagedConfiguration(
            globalIgnorePatterns: [],
            useCommitTimes: false,
            network: SvnNetworkSettings()
        ))

        let configText = try String(contentsOf: config, encoding: .utf8)
        XCTAssertTrue(configText.contains("global-ignores ="))
        XCTAssertTrue(configText.contains("use-commit-times = no"))
        XCTAssertFalse(configText.contains("ssh ="))
        XCTAssertTrue(configText.contains("other = /other/tunnel"))
        let serversText = try String(contentsOf: servers, encoding: .utf8)
        XCTAssertFalse(serversText.contains("http-proxy-"))
        XCTAssertFalse(serversText.contains("old-secret"))
        XCTAssertTrue(serversText.contains("store-passwords = no"))
        XCTAssertEqual(try store.load().network, SvnNetworkSettings())
    }

    func testUpdateCanonicalizesDuplicateProxyKeysAndRoundTripsPassword() throws {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data().write(to: root.appendingPathComponent("config"))
        let servers = root.appendingPathComponent("servers")
        try Data("""
        [global]
        http-proxy-host = old.example.com
        HTTP-PROXY-HOST = stale.example.com
        http-proxy-password = old-secret
        HTTP-PROXY-PASSWORD = stale-secret
        store-passwords = no
        """.utf8).write(to: servers)
        let store = SvnClientConfigurationStore(directoryURL: root)
        let managed = SvnClientManagedConfiguration(
            network: SvnNetworkSettings(proxy: SvnProxySettings(
                enabled: true,
                host: "proxy.example.com",
                port: 3128,
                username: "developer"
            )),
            proxyPassword: "new-secret"
        )

        try store.update(managed)

        let text = try String(contentsOf: servers, encoding: .utf8)
        XCTAssertEqual(text.lowercased().components(separatedBy: "http-proxy-host =").count - 1, 1)
        XCTAssertEqual(text.lowercased().components(separatedBy: "http-proxy-password =").count - 1, 1)
        XCTAssertTrue(text.contains("http-proxy-host = proxy.example.com"))
        XCTAssertTrue(text.contains("http-proxy-password = new-secret"))
        XCTAssertFalse(text.contains("old-secret"))
        XCTAssertFalse(text.contains("stale-secret"))
        XCTAssertTrue(text.contains("store-passwords = no"))
        XCTAssertEqual(try store.load(), managed)
        let permissions = try FileManager.default.attributesOfItem(atPath: servers.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue ?? -1, 0o600)
    }

    func testEnsureFilesExistCreatesEmptyFilesWithoutOverwritingExistingContent() throws {
        let root = temporaryRoot()
        let store = SvnClientConfigurationStore(directoryURL: root)

        try store.ensureFilesExist()

        XCTAssertEqual(try Data(contentsOf: store.configFileURL), Data())
        XCTAssertEqual(try Data(contentsOf: store.serversFileURL), Data())
        try Data("# external edit\n".utf8).write(to: store.configFileURL)

        try store.ensureFilesExist()

        XCTAssertEqual(
            try String(contentsOf: store.configFileURL, encoding: .utf8),
            "# external edit\n"
        )
        let permissions = try FileManager.default.attributesOfItem(
            atPath: store.serversFileURL.path
        )[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue ?? -1, 0o600)
    }

    func testLoadMissingFilesReturnsSubversionDefaultsWithoutCreatingFiles() throws {
        let root = temporaryRoot()
        let store = SvnClientConfigurationStore(directoryURL: root)

        XCTAssertEqual(try store.load(), SvnClientManagedConfiguration())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.configFileURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.serversFileURL.path))
    }

    func testInvalidManagedValuesFailBeforeEitherFileIsChanged() throws {
        let root = temporaryRoot()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let config = root.appendingPathComponent("config")
        let servers = root.appendingPathComponent("servers")
        let originalConfig = Data("[miscellany]\nglobal-ignores = keep\n".utf8)
        let originalServers = Data("[global]\nstore-passwords = no\n".utf8)
        try originalConfig.write(to: config)
        try originalServers.write(to: servers)
        let store = SvnClientConfigurationStore(directoryURL: root)
        let invalidValues = [
            SvnClientManagedConfiguration(globalIgnorePatterns: ["bad pattern"], useCommitTimes: false),
            SvnClientManagedConfiguration(
                network: SvnNetworkSettings(proxy: SvnProxySettings(enabled: true, host: "proxy", port: 0))
            ),
            SvnClientManagedConfiguration(
                network: SvnNetworkSettings(sshExecutablePath: "/usr/bin/ssh\nmalicious")
            ),
        ]

        for invalid in invalidValues {
            XCTAssertThrowsError(try store.update(invalid))
            XCTAssertEqual(try Data(contentsOf: config), originalConfig)
            XCTAssertEqual(try Data(contentsOf: servers), originalServers)
        }
    }

    private func temporaryRoot() -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SvnClientConfig-\(UUID().uuidString)", isDirectory: true)
        roots.append(root)
        return root
    }
}
