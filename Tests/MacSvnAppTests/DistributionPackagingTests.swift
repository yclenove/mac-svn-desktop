import Darwin
import Foundation
import XCTest

final class DistributionPackagingTests: XCTestCase {
    func testReleaseBuilderProducesUniversalXcodeAppAndRunsAllVerifiers() throws {
        let source = try Self.readRepoSource(at: "scripts/build-release-app.sh")

        XCTAssertTrue(source.contains("-configuration Release"))
        XCTAssertTrue(source.contains("-destination generic/platform=macOS"))
        XCTAssertTrue(source.contains("RELEASE_ARCHS=\"arm64 x86_64\""))
        XCTAssertTrue(source.contains("Release（${RELEASE_ARCHS}）"))
        XCTAssertTrue(source.contains("ARCHS=\"$RELEASE_ARCHS\""))
        XCTAssertTrue(source.contains("ONLY_ACTIVE_ARCH=NO"))
        XCTAssertTrue(source.contains("verify-release-app.sh"))
        XCTAssertTrue(source.contains("smoke-test-macos-app.sh"))
    }

    func testReleaseVerifierRequiresExtensionsArchitecturesSignatureAndPortableDependencies() throws {
        let source = try Self.readRepoSource(at: "scripts/verify-release-app.sh")
        let dependencies = try Self.readRepoSource(at: "scripts/verify-mach-o-dependencies.sh")

        XCTAssertTrue(source.contains("verify-macos-app.sh"))
        XCTAssertTrue(source.contains("verify-finder-sync-appex.sh"))
        XCTAssertTrue(source.contains("verify-quicklook-appex.sh"))
        XCTAssertTrue(source.contains("verify-mach-o-dependencies.sh"))
        XCTAssertTrue(source.contains("codesign --verify --deep --strict"))
        XCTAssertTrue(dependencies.contains("lipo \"$binary\" -verify_arch \"$arch\""))
        XCTAssertTrue(dependencies.contains("arm64 x86_64"))
        XCTAssertTrue(dependencies.contains("otool -L"))
        XCTAssertTrue(dependencies.contains("[[ \"$dependency_line\" == *: ]] && continue"))
        XCTAssertTrue(dependencies.contains("compatibility version"))
        XCTAssertTrue(dependencies.contains("offset"))
        XCTAssertTrue(dependencies.contains("resolve_embedded_dependency"))
        XCTAssertTrue(dependencies.contains("inherited_rpaths"))
        XCTAssertTrue(dependencies.contains("依赖无法解析到应用包内"))
        XCTAssertTrue(dependencies.contains("依赖越过应用包边界"))
        XCTAssertTrue(dependencies.contains("不允许的动态依赖"))
    }

    func testLaunchSmokeUsesFoundationIsolationAndBoundedProcessCleanup() throws {
        let source = try Self.readRepoSource(at: "scripts/smoke-test-macos-app.sh")

        XCTAssertTrue(source.contains("mktemp -d"))
        XCTAssertTrue(source.contains("HOME=\"$SMOKE_HOME\""))
        XCTAssertTrue(source.contains("CFFIXED_USER_HOME=\"$SMOKE_HOME\""))
        XCTAssertTrue(source.contains("NSHomeDirectory"))
        XCTAssertTrue(source.contains("TMPDIR=\"$SMOKE_TMP\""))
        XCTAssertTrue(source.contains("PATH=/usr/bin:/bin"))
        XCTAssertTrue(source.contains("kill -0 \"$APP_PID\""))
        XCTAssertTrue(source.contains("APP_PGID"))
        XCTAssertTrue(source.contains("pgrep -g"))
        XCTAssertTrue(source.contains("kill -KILL \"-$APP_PGID\""))
        XCTAssertTrue(source.contains("TERMINATION_GRACE_SECONDS"))
        XCTAssertTrue(source.contains("启动稳定性冒烟通过"))
    }

    func testNotarizationPreservesIdentityEntitlementsAndPublishesOnlyAfterGatekeeper() throws {
        let signer = try Self.readRepoSource(at: "scripts/sign-and-notarize.sh")
        let prereqs = try Self.readRepoSource(at: "scripts/verify-signing-prereqs.sh")

        XCTAssertTrue(signer.contains("Packaging/FinderSync/SVNStudioFinderSync.entitlements"))
        XCTAssertTrue(signer.contains("verify-release-app.sh"))
        XCTAssertTrue(signer.contains("--output-format json"))
        XCTAssertTrue(signer.contains("Accepted"))
        XCTAssertTrue(signer.contains("SVNStudio-notary-submission.zip"))
        XCTAssertTrue(signer.contains("stapler staple"))
        XCTAssertTrue(signer.contains("Authority=Developer ID Application:"))
        XCTAssertTrue(signer.contains("TeamIdentifier"))
        XCTAssertTrue(signer.contains("STAGING_DIR"))
        XCTAssertTrue(signer.contains("FINAL_APP"))
        XCTAssertTrue(signer.contains("INPUT_APP_CANONICAL"))
        XCTAssertTrue(signer.contains("FINAL_APP_CANONICAL"))
        XCTAssertTrue(signer.contains("mv \"$STAGED_APP\" \"$FINAL_APP\""))
        XCTAssertTrue(signer.contains("FINAL_ZIP_TEMP"))
        XCTAssertTrue(signer.contains("mv \"$FINAL_ZIP_TEMP\" \"$FINAL_ZIP\""))
        XCTAssertTrue(signer.contains("重新打包已 staple 的最终分发 ZIP"))
        XCTAssertTrue(prereqs.contains("Developer ID Application:"))
        XCTAssertTrue(prereqs.contains("当前钥匙串未匹配到签名身份"))
        XCTAssertFalse(prereqs.contains("仍可继续"))

        let inputVerification = try XCTUnwrap(signer.range(of: "==> 校验输入 Release 应用"))
        let prepareOutput = try XCTUnwrap(signer.range(of: "==> 准备发布工作目录"))
        let gatekeeper = try XCTUnwrap(signer.range(of: "==> Gatekeeper 评估（本机）"))
        let finalApp = try XCTUnwrap(signer.range(of: "==> 发布已通过闸门的最终应用"))
        let finalArchive = try XCTUnwrap(signer.range(of: "==> 重新打包已 staple 的最终分发 ZIP"))
        XCTAssertLessThan(inputVerification.lowerBound, prepareOutput.lowerBound)
        XCTAssertLessThan(gatekeeper.lowerBound, finalApp.lowerBound)
        XCTAssertLessThan(finalApp.lowerBound, finalArchive.lowerBound)

        let collisionRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("SigningPathCollision-\(UUID().uuidString)")
        let distributionDirectory = collisionRoot.appendingPathComponent("release")
        let existingFinalApp = distributionDirectory.appendingPathComponent("SVNStudio.app")
        defer { try? FileManager.default.removeItem(at: collisionRoot) }
        try FileManager.default.createDirectory(at: existingFinalApp, withIntermediateDirectories: true)
        var environment = ProcessInfo.processInfo.environment
        environment["SVNSTUDIO_DRY_RUN"] = "1"
        environment["SVNSTUDIO_APP_PATH"] = distributionDirectory
            .appendingPathComponent("./SVNStudio.app/").path
        environment["SVNSTUDIO_DIST_DIR"] = distributionDirectory.path
        environment["SVNSTUDIO_SIGN_IDENTITY"] = "Developer ID Application: Example (TEAMID)"
        let collision = try Self.runProcess(
            Self.repoRoot.appendingPathComponent("scripts/sign-and-notarize.sh").path,
            arguments: [],
            environment: environment
        )
        XCTAssertNotEqual(collision.status, 0)
        XCTAssertTrue(collision.output.contains("输入应用不能与最终发布路径相同"), collision.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: existingFinalApp.path))
    }

    func testLaunchSmokeForceTerminatesAnUnresponsiveProcessTree() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("DistributionPackagingTests-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Fake.app")
        let executableDirectory = app.appendingPathComponent("Contents/MacOS")
        let executable = executableDirectory.appendingPathComponent("FakeApp")
        let smokeHome = root.appendingPathComponent("home")
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: smokeHome, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CFBundleExecutable": "FakeApp"],
            format: .xml,
            options: 0
        )
        try plist.write(to: app.appendingPathComponent("Contents/Info.plist"))
        try """
        #!/bin/bash
        trap '' TERM
        /bin/bash -c 'trap "" TERM; exec /bin/sleep 300' &
        child=$!
        printf '%s\\n%s\\n' "$$" "$child" > "$CFFIXED_USER_HOME/pids"
        wait "$child"
        """.write(to: executable, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let process = Process()
        process.executableURL = Self.repoRoot.appendingPathComponent("scripts/smoke-test-macos-app.sh")
        process.arguments = [app.path]
        var environment = ProcessInfo.processInfo.environment
        environment["SVNSTUDIO_SMOKE_HOME"] = smokeHome.path
        environment["SVNSTUDIO_SMOKE_STABILITY_SECONDS"] = "1"
        environment["SVNSTUDIO_SMOKE_TERMINATION_GRACE_SECONDS"] = "1"
        process.environment = environment
        process.standardOutput = Pipe()
        let errorPipe = Pipe()
        process.standardError = errorPipe

        let startedAt = Date()
        try process.run()
        process.waitUntilExit()

        let elapsed = Date().timeIntervalSince(startedAt)
        let errorOutput = String(
            data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        XCTAssertEqual(process.terminationStatus, 0)
        XCTAssertGreaterThan(elapsed, 1.8)
        XCTAssertLessThan(elapsed, 5)
        XCTAssertTrue(errorOutput.contains("升级 SIGKILL"), errorOutput)
        let pids = try String(
            contentsOf: smokeHome.appendingPathComponent("pids"),
            encoding: .utf8
        )
        .split(separator: "\n")
        .compactMap { pid_t($0) }
        XCTAssertEqual(pids.count, 2)
        for pid in pids {
            for _ in 0..<100 where kill(pid, 0) == 0 {
                usleep(10_000)
            }
            XCTAssertNotEqual(kill(pid, 0), 0, "冒烟结束后仍残留进程 \(pid)")
        }
    }

    func testMachODependencyVerifierInheritsRunpathsAndRejectsMissingLibraries() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("MachODependencyTests-\(UUID().uuidString)")
        let app = root.appendingPathComponent("Fixture With Spaces.app")
        let executableDirectory = app.appendingPathComponent("Contents/MacOS")
        let frameworksDirectory = app.appendingPathComponent("Contents/Frameworks With Spaces")
        let childSource = root.appendingPathComponent("child.c")
        let parentSource = root.appendingPathComponent("parent.c")
        let mainSource = root.appendingPathComponent("main.c")
        let childLibrary = frameworksDirectory.appendingPathComponent("libChild Space.dylib")
        let parentLibrary = frameworksDirectory.appendingPathComponent("libParent Space.dylib")
        let executable = executableDirectory.appendingPathComponent("Fixture")
        defer { try? fileManager.removeItem(at: root) }

        try fileManager.createDirectory(at: executableDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: frameworksDirectory, withIntermediateDirectories: true)
        try "int child_value(void) { return 1; }\n"
            .write(to: childSource, atomically: true, encoding: .utf8)
        try "extern int child_value(void); int parent_value(void) { return child_value(); }\n"
            .write(to: parentSource, atomically: true, encoding: .utf8)
        try "extern int parent_value(void); int main(void) { return parent_value() == 1 ? 0 : 1; }\n"
            .write(to: mainSource, atomically: true, encoding: .utf8)

        try Self.runChecked("/usr/bin/xcrun", arguments: [
            "clang", "-arch", "x86_64", "-arch", "arm64", "-dynamiclib",
            childSource.path, "-Wl,-install_name,@rpath/libChild Space.dylib", "-o", childLibrary.path,
        ])
        try Self.runChecked("/usr/bin/xcrun", arguments: [
            "clang", "-arch", "x86_64", "-arch", "arm64", "-dynamiclib",
            parentSource.path, childLibrary.path,
            "-Wl,-install_name,@rpath/libParent Space.dylib", "-o", parentLibrary.path,
        ])
        try Self.runChecked("/usr/bin/xcrun", arguments: [
            "clang", "-arch", "x86_64", "-arch", "arm64",
            mainSource.path, parentLibrary.path,
            "-Wl,-rpath,@executable_path/../Frameworks With Spaces", "-o", executable.path,
        ])

        let verifier = Self.repoRoot.appendingPathComponent("scripts/verify-mach-o-dependencies.sh")
        let valid = try Self.runProcess(verifier.path, arguments: [
            app.path, executable.path, executableDirectory.path, "继承 rpath 夹具",
        ])
        XCTAssertEqual(valid.status, 0, valid.output)

        try fileManager.removeItem(at: childLibrary)
        let invalid = try Self.runProcess(verifier.path, arguments: [
            app.path, executable.path, executableDirectory.path, "缺失依赖夹具",
        ])
        XCTAssertNotEqual(invalid.status, 0)
        XCTAssertTrue(invalid.output.contains("依赖无法解析到应用包内"), invalid.output)
    }

    func testDistributionScriptsParseWithSystemBash() throws {
        let scripts = [
            "scripts/build-release-app.sh",
            "scripts/verify-release-app.sh",
            "scripts/verify-mach-o-dependencies.sh",
            "scripts/smoke-test-macos-app.sh",
            "scripts/sign-and-notarize.sh",
            "scripts/verify-signing-prereqs.sh",
        ].map { Self.repoRoot.appendingPathComponent($0).path }
        let result = try Self.runProcess("/bin/bash", arguments: ["-n"] + scripts)
        XCTAssertEqual(result.status, 0, result.output)
    }

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static func readRepoSource(at path: String) throws -> String {
        try String(
            contentsOf: repoRoot.appendingPathComponent(path),
            encoding: .utf8
        )
    }

    private static func runChecked(_ executable: String, arguments: [String]) throws {
        let result = try runProcess(executable, arguments: arguments)
        guard result.status == 0 else {
            throw NSError(
                domain: "DistributionPackagingTests",
                code: Int(result.status),
                userInfo: [NSLocalizedDescriptionKey: result.output]
            )
        }
    }

    private static func runProcess(
        _ executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) throws -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(
            data: pipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        return (process.terminationStatus, output)
    }
}
