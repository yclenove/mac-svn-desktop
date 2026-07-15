import XCTest
@testable import MacSvnCore

final class SvnCommandBuilderTests: XCTestCase {
    func testVersionUsesQuietFlag() {
        let command = SvnCommandBuilder.version()
        XCTAssertEqual(command.arguments, ["--version", "--quiet"])
    }

    func testStatusUsesXmlAndNonInteractive() {
        let command = SvnCommandBuilder.status()
        XCTAssertEqual(command.arguments, ["status", "-v", "--xml", "--non-interactive"])

        let againstRepo = SvnCommandBuilder.status(verbose: true, showUpdates: true)
        XCTAssertEqual(
            againstRepo.arguments,
            ["status", "-v", "--xml", "--show-updates", "--non-interactive"]
        )

        let includingIgnored = SvnCommandBuilder.status(noIgnore: true)
        XCTAssertEqual(
            includingIgnored.arguments,
            ["status", "-v", "--xml", "--no-ignore", "--non-interactive"]
        )
    }

    func testCommitUsesUtf8EncodingNonInteractiveMessageAndPaths() {
        let command = SvnCommandBuilder.commit(paths: ["src/a.swift", "中文/文件.txt"], message: "修复：登录超时")
        XCTAssertEqual(command.arguments, [
            "commit", "--encoding", "UTF-8", "--non-interactive",
            "-m", "修复：登录超时",
            "src/a.swift", "中文/文件.txt"
        ])
    }

    func testCommitKeepLocksAddsNoUnlock() {
        let command = SvnCommandBuilder.commit(
            paths: ["locked.txt"],
            message: "keep",
            keepLocks: true
        )
        XCTAssertEqual(command.arguments, [
            "commit", "--encoding", "UTF-8", "--non-interactive",
            "-m", "keep",
            "--no-unlock",
            "locked.txt"
        ])
    }

    func testUpdatePostponesConflictsAndCanTargetRevision() {
        let command = SvnCommandBuilder.update(paths: ["src"], revision: Revision(42))
        XCTAssertEqual(command.arguments, [
            "update", "--accept", "postpone", "--non-interactive", "-r", "42", "src"
        ])
    }

    func testUpdateCanIncludeAuthenticationArgumentsWithoutPassword() {
        let command = SvnCommandBuilder.update(
            paths: ["src"],
            revision: Revision(42),
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "update", "--accept", "postpone", "--non-interactive",
            "--username", "u", "--password-from-stdin",
            "-r", "42", "src"
        ])
        XCTAssertFalse(command.arguments.contains("secret"))
    }

    func testUpdateCanSetDepth() {
        let command = SvnCommandBuilder.update(paths: [], revision: nil, setDepth: .files)

        XCTAssertEqual(command.arguments, [
            "update", "--accept", "postpone", "--non-interactive",
            "--set-depth", "files"
        ])
    }

    func testSwitchUsesPostponeNonInteractiveAuthAndUrl() {
        let command = SvnCommandBuilder.switchTo(
            url: "file:///repo/branches/feature-one",
            revision: Revision(8),
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "switch", "--accept", "postpone", "--non-interactive",
            "--username", "u", "--password-from-stdin",
            "-r", "8",
            "file:///repo/branches/feature-one"
        ])
    }

    func testMergeUsesPostponeDryRunRangeAuthAndSource() {
        let command = SvnCommandBuilder.merge(
            source: "file:///repo/branches/feature-one",
            range: RevisionRange(start: Revision(2), end: Revision(5)),
            dryRun: true,
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "merge", "--accept", "postpone", "--non-interactive", "--dry-run",
            "--username", "u", "--password-from-stdin",
            "-r", "2:5",
            "file:///repo/branches/feature-one"
        ])
    }

    func testTwoTreeMergeUsesBothSourcesAndDryRun() {
        let command = SvnCommandBuilder.merge(
            from: "file:///repo/branches/old",
            to: "file:///repo/branches/new",
            dryRun: true,
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "merge", "--accept", "postpone", "--non-interactive", "--dry-run",
            "--username", "u", "--password-from-stdin",
            "file:///repo/branches/old", "file:///repo/branches/new"
        ])
    }

    func testReintegrateMergeUsesModernCompleteMergeWithoutObsoleteFlag() {
        let command = SvnCommandBuilder.mergeReintegrate(
            source: "file:///repo/branches/feature-one",
            dryRun: true,
            authArguments: ["--username", "u"]
        )

        XCTAssertEqual(command.arguments, [
            "merge", "--accept", "postpone", "--non-interactive", "--dry-run",
            "--username", "u", "file:///repo/branches/feature-one"
        ])
        XCTAssertFalse(command.arguments.contains("--reintegrate"))
    }

    func testMergeRevisionUsesSingleChangeRevision() {
        let command = SvnCommandBuilder.mergeRevisionTo(
            source: "file:///repo/trunk",
            revision: Revision(12),
            dryRun: false
        )

        XCTAssertEqual(command.arguments, [
            "merge", "--accept", "postpone", "--non-interactive",
            "-c", "12", "file:///repo/trunk"
        ])
    }

    func testExportCanOmitExternals() {
        let command = SvnCommandBuilder.export(
            url: "file:///repo/trunk",
            to: "/tmp/export",
            revision: Revision(12),
            ignoreExternals: true,
            authArguments: ["--username", "u"]
        )

        XCTAssertEqual(command.arguments, [
            "export", "--non-interactive", "-r", "12", "--ignore-externals",
            "--username", "u", "file:///repo/trunk", "/tmp/export"
        ])
    }

    func testImportUsesUtf8MessageAndAuth() {
        let command = SvnCommandBuilder.import(
            path: "/tmp/project",
            url: "file:///repo/trunk",
            message: "首次导入",
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "import", "--encoding", "UTF-8", "--non-interactive",
            "-m", "首次导入", "--username", "u", "--password-from-stdin",
            "/tmp/project", "file:///repo/trunk"
        ])
    }

    func testRelocateUsesSwitchRelocateAndFromToURLs() {
        let command = SvnCommandBuilder.relocate(
            from: "https://old.example/svn",
            to: "https://new.example/svn",
            workingCopy: "/tmp/wc"
        )

        XCTAssertEqual(command.arguments, [
            "switch", "--relocate", "--non-interactive",
            "https://old.example/svn", "https://new.example/svn", "/tmp/wc"
        ])
    }

    func testResolveUsesAcceptNonInteractiveAndPath() {
        let command = SvnCommandBuilder.resolve(path: "README.txt", accept: .mineFull)

        XCTAssertEqual(command.arguments, [
            "resolve", "--accept", "mine-full", "--non-interactive", "README.txt"
        ])
    }

    func testResolveCanAcceptTreeConflictSides() {
        XCTAssertEqual(
            SvnCommandBuilder.resolve(path: "tree.txt", accept: .mineConflict).arguments,
            ["resolve", "--accept", "mine-conflict", "--non-interactive", "tree.txt"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.resolve(path: "tree.txt", accept: .theirsConflict).arguments,
            ["resolve", "--accept", "theirs-conflict", "--non-interactive", "tree.txt"]
        )
    }

    func testAddUsesNonInteractiveAndPaths() {
        let command = SvnCommandBuilder.add(paths: ["a.txt", "dir/b.txt"])
        XCTAssertEqual(command.arguments, ["add", "--non-interactive", "a.txt", "dir/b.txt"])
    }

    func testChangelistAssignAndRemoveUseDepthAndSelectedPaths() {
        XCTAssertEqual(
            SvnCommandBuilder.assignChangelist(
                name: "release",
                paths: ["Sources", "README.md"],
                depth: .infinity
            ).arguments,
            ["changelist", "release", "--depth", "infinity", "--non-interactive", "Sources", "README.md"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.removeFromChangelists(paths: ["README.md"], depth: .empty).arguments,
            ["changelist", "--remove", "--depth", "empty", "--non-interactive", "README.md"]
        )
    }

    func testWorkingCopyMoveSchedulesWithoutCommitMessage() {
        let command = SvnCommandBuilder.workingCopyMove(source: "old.txt", destination: "new.txt")
        XCTAssertEqual(
            command.arguments,
            ["move", "--non-interactive", "old.txt", "new.txt"]
        )
    }

    func testRenameUsesNonInteractiveSourceAndDestination() {
        let command = SvnCommandBuilder.rename(source: "src/a.txt", destination: "src/b.txt")
        XCTAssertEqual(
            command.arguments,
            ["rename", "--non-interactive", "src/a.txt", "src/b.txt"]
        )
    }

    func testWorkingCopyCopySchedulesWithoutCommitMessage() {
        let command = SvnCommandBuilder.workingCopyCopy(source: "a.txt", destination: "a-copy.txt")
        XCTAssertEqual(
            command.arguments,
            ["copy", "--non-interactive", "a.txt", "a-copy.txt"]
        )
    }

    func testDeleteUsesNonInteractiveAndPaths() {
        let command = SvnCommandBuilder.delete(paths: ["old.txt"])
        XCTAssertEqual(command.arguments, ["delete", "--non-interactive", "old.txt"])
    }

    func testDeleteKeepingLocalPreservesWorkingCopyFile() {
        let command = SvnCommandBuilder.deleteKeepingLocal(paths: ["old.txt", "dir"])
        XCTAssertEqual(
            command.arguments,
            ["delete", "--keep-local", "--non-interactive", "old.txt", "dir"]
        )
    }

    func testRevertCanBeRecursive() {
        let command = SvnCommandBuilder.revert(paths: ["dir"], recursive: true)
        XCTAssertEqual(command.arguments, ["revert", "--non-interactive", "--recursive", "dir"])
    }

    func testCleanupUsesNonInteractive() {
        let command = SvnCommandBuilder.cleanup()
        XCTAssertEqual(command.arguments, ["cleanup", "--non-interactive"])
    }

    func testCleanupCanIncludeBreakLocksVacuumAndExternals() {
        let command = SvnCommandBuilder.cleanup(options: SvnCleanupOptions(
            breakLocks: true,
            vacuumPristines: true,
            includeExternals: true
        ))
        XCTAssertEqual(
            command.arguments,
            [
                "cleanup", "--non-interactive",
                "--break-locks",
                "--vacuum-pristines",
                "--include-externals"
            ]
        )
    }

    func testDiffCanTargetRevisionRange() {
        let command = SvnCommandBuilder.diff(target: "a.txt", r1: Revision(1), r2: Revision(3))
        XCTAssertEqual(command.arguments, ["diff", "--non-interactive", "-r", "1:3", "a.txt"])
    }

    func testDiffAgainstBaseUsesExplicitBaseRevision() {
        let command = SvnCommandBuilder.diffAgainstBase(target: "a.txt")
        XCTAssertEqual(command.arguments, ["diff", "--non-interactive", "-r", "BASE", "a.txt"])
    }

    func testRepositoryDiffUsesPeggedURLsAndAuthenticationArguments() {
        let command = SvnCommandBuilder.repositoryDiff(
            oldURL: "file:///repo/trunk",
            oldRevision: Revision(4),
            newURL: "file:///repo/branches/feature",
            newRevision: Revision(9),
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "diff", "--non-interactive",
            "--username", "u", "--password-from-stdin",
            "--old", "file:///repo/trunk@4",
            "--new", "file:///repo/branches/feature@9"
        ])
    }

    func testDiffBetweenPathsUsesOldAndNew() {
        let command = SvnCommandBuilder.diffBetweenPaths(oldPath: "a.txt", newPath: "b.txt")
        XCTAssertEqual(
            command.arguments,
            ["diff", "--non-interactive", "--old", "a.txt", "--new", "b.txt"]
        )
    }

    func testPatchUsesNonInteractiveAndPatchFile() {
        let command = SvnCommandBuilder.patch(patchFile: "/tmp/shelf.patch")
        XCTAssertEqual(command.arguments, ["patch", "--non-interactive", "/tmp/shelf.patch"])
    }

    func testLogUsesXmlVerboseAndBatch() {
        let command = SvnCommandBuilder.log(target: "trunk", from: Revision(20), batch: 100, verbose: true)
        XCTAssertEqual(command.arguments, ["log", "--xml", "-v", "--non-interactive", "-r", "20:0", "-l", "100", "trunk"])
    }

    func testLogCanIncludeStopOnCopy() {
        let command = SvnCommandBuilder.log(
            target: "branches/feature",
            from: Revision(20),
            batch: 100,
            verbose: true,
            stopOnCopy: true
        )
        XCTAssertEqual(command.arguments, [
            "log", "--xml", "-v", "--stop-on-copy", "--non-interactive",
            "-r", "20:0", "-l", "100", "branches/feature"
        ])
    }

    func testLogCanIncludeAuthenticationArgumentsBeforeTarget() {
        let command = SvnCommandBuilder.log(
            target: "file:///repo/trunk",
            from: Revision(20),
            batch: 50,
            verbose: true,
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "log", "--xml", "-v", "--non-interactive",
            "-r", "20:0",
            "-l", "50",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk"
        ])
    }

    func testLogFromHeadUsesHeadToZeroRangeBatchAndTarget() {
        let command = SvnCommandBuilder.logFromHead(
            target: "file:///repo/trunk",
            batch: 100,
            verbose: false
        )

        XCTAssertEqual(command.arguments, [
            "log", "--xml", "--non-interactive",
            "-r", "HEAD:0",
            "-l", "100",
            "file:///repo/trunk"
        ])
    }

    func testLogFromHeadClampsBatchToSvnLimitRange() {
        let command = SvnCommandBuilder.logFromHead(
            target: "file:///repo/trunk",
            batch: Int.max,
            verbose: false
        )

        XCTAssertEqual(command.arguments, [
            "log", "--xml", "--non-interactive",
            "-r", "HEAD:0",
            "-l", "2147483647",
            "file:///repo/trunk"
        ])
    }

    func testLogFromHeadCanIncludeVerboseAndAuthenticationArgumentsBeforeTarget() {
        let command = SvnCommandBuilder.logFromHead(
            target: "file:///repo/trunk",
            batch: 50,
            verbose: true,
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "log", "--xml", "-v", "--non-interactive",
            "-r", "HEAD:0",
            "-l", "50",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk"
        ])
    }

    func testListUsesXmlDepthAuthAndUrl() {
        let command = SvnCommandBuilder.list(
            url: "file:///repo/trunk",
            depth: .immediates,
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "list", "--xml", "--non-interactive",
            "--depth", "immediates",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk"
        ])
    }

    func testListCanIncludeExternals() {
        let command = SvnCommandBuilder.list(
            url: "file:///repo/trunk",
            depth: .immediates,
            includeExternals: true,
            authArguments: []
        )

        XCTAssertEqual(command.arguments, [
            "list", "--xml", "--non-interactive",
            "--depth", "immediates", "--include-externals",
            "file:///repo/trunk"
        ])
    }

    func testRemoteInfoUsesXmlDepthAuthAndUrl() {
        let command = SvnCommandBuilder.remoteInfo(
            url: "file:///repo/trunk",
            depth: .immediates,
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "info", "--xml", "--non-interactive",
            "--depth", "immediates",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk"
        ])
    }

    func testRemoteInfoCanIncludeExternals() {
        let command = SvnCommandBuilder.remoteInfo(
            url: "file:///repo/trunk",
            depth: .immediates,
            includeExternals: true
        )

        XCTAssertEqual(command.arguments, [
            "info", "--xml", "--non-interactive",
            "--depth", "immediates", "--include-externals",
            "file:///repo/trunk"
        ])
    }

    func testCatUsesRevisionAuthenticationAndUrl() {
        let command = SvnCommandBuilder.cat(
            url: "file:///repo/trunk/README.txt",
            revision: Revision(7),
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "cat", "--non-interactive",
            "-r", "7",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk/README.txt"
        ])
    }

    func testCheckoutUsesDepthAuthenticationUrlAndDestination() {
        let command = SvnCommandBuilder.checkout(
            url: "file:///repo/trunk",
            to: "/tmp/wc",
            depth: .files,
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "checkout", "--non-interactive",
            "--depth", "files",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk", "/tmp/wc"
        ])
    }

    func testCheckoutCanPinRevisionAndIgnoreExternals() {
        let command = SvnCommandBuilder.checkout(
            url: "file:///repo/trunk",
            to: "/tmp/wc",
            depth: .immediates,
            revision: Revision(12),
            ignoreExternals: true
        )
        XCTAssertEqual(command.arguments, [
            "checkout", "--non-interactive",
            "--depth", "immediates",
            "-r", "12",
            "--ignore-externals",
            "file:///repo/trunk", "/tmp/wc"
        ])
    }

    func testUpdateCanIgnoreExternalsWithRevisionAndDepth() {
        let command = SvnCommandBuilder.update(
            paths: ["src"],
            revision: Revision(9),
            setDepth: .files,
            ignoreExternals: true
        )
        XCTAssertEqual(command.arguments, [
            "update", "--accept", "postpone", "--non-interactive",
            "-r", "9",
            "--set-depth", "files",
            "--ignore-externals",
            "src"
        ])
    }

    func testExportUsesRevisionAuthenticationUrlAndDestination() {
        let command = SvnCommandBuilder.export(
            url: "file:///repo/trunk",
            to: "/tmp/export",
            revision: Revision(7),
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "export", "--non-interactive",
            "-r", "7",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk", "/tmp/export"
        ])
        XCTAssertFalse(command.arguments.contains("secret"))
    }

    func testCopyUsesUtf8MessageAuthSourceAndDestination() {
        let command = SvnCommandBuilder.copy(
            source: "file:///repo/trunk",
            destination: "file:///repo/branches/feature-one",
            message: "创建分支：feature-one",
            authArguments: ["--username", "u", "--password-from-stdin"]
        )

        XCTAssertEqual(command.arguments, [
            "copy", "--encoding", "UTF-8", "--non-interactive",
            "-m", "创建分支：feature-one",
            "--username", "u", "--password-from-stdin",
            "file:///repo/trunk", "file:///repo/branches/feature-one"
        ])
    }

    func testRemoteRepositoryWriteCommandsUseUtf8MessageAuthAndUrls() {
        let authArguments = ["--username", "u", "--password-from-stdin"]

        XCTAssertEqual(
            SvnCommandBuilder.mkdir(
                url: "file:///repo/trunk/docs",
                message: "创建目录：docs",
                authArguments: authArguments
            ).arguments,
            [
                "mkdir", "--encoding", "UTF-8", "--non-interactive",
                "-m", "创建目录：docs",
                "--username", "u", "--password-from-stdin",
                "file:///repo/trunk/docs"
            ]
        )
        XCTAssertEqual(
            SvnCommandBuilder.delete(
                url: "file:///repo/trunk/old.txt",
                message: "删除远端文件",
                authArguments: authArguments
            ).arguments,
            [
                "delete", "--encoding", "UTF-8", "--non-interactive",
                "-m", "删除远端文件",
                "--username", "u", "--password-from-stdin",
                "file:///repo/trunk/old.txt"
            ]
        )
        XCTAssertEqual(
            SvnCommandBuilder.move(
                source: "file:///repo/trunk/old.txt",
                destination: "file:///repo/trunk/new.txt",
                message: "移动远端文件",
                authArguments: authArguments
            ).arguments,
            [
                "move", "--encoding", "UTF-8", "--non-interactive",
                "-m", "移动远端文件",
                "--username", "u", "--password-from-stdin",
                "file:///repo/trunk/old.txt", "file:///repo/trunk/new.txt"
            ]
        )
    }

    func testInfoUsesXmlAndNonInteractive() {
        let command = SvnCommandBuilder.info(target: ".")
        XCTAssertEqual(command.arguments, ["info", "--xml", "--non-interactive", "."])
    }

    func testInfoCanTargetRepositoryHead() {
        let command = SvnCommandBuilder.info(target: "src", revisionSpec: "HEAD")
        XCTAssertEqual(command.arguments, ["info", "--xml", "--non-interactive", "-r", "HEAD", "src"])
    }

    func testBlameUsesXmlNonInteractiveAndTarget() {
        let command = SvnCommandBuilder.blame(target: "README.txt")

        XCTAssertEqual(command.arguments, ["blame", "--xml", "--non-interactive", "README.txt"])
    }

    func testBlameCanUseRevisionRange() {
        let command = SvnCommandBuilder.blame(
            target: "README.txt",
            startRevision: Revision(3),
            endRevision: Revision(9)
        )

        XCTAssertEqual(command.arguments, [
            "blame", "--xml", "--non-interactive", "-r", "3:9", "README.txt@9"
        ])
    }

    func testPropertyCommandsUseXmlUtf8AndNonInteractive() {
        XCTAssertEqual(
            SvnCommandBuilder.proplist(target: "README.txt").arguments,
            ["proplist", "--xml", "--verbose", "--non-interactive", "README.txt"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.propget(name: "svn:eol-style", target: "README.txt").arguments,
            ["propget", "--xml", "--non-interactive", "svn:eol-style", "README.txt"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.propset(name: "svn:eol-style", value: "native", target: "README.txt").arguments,
            ["propset", "--encoding", "UTF-8", "--non-interactive", "--", "svn:eol-style", "native", "README.txt"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.propset(name: "custom:reviewer", value: "杨超", target: "README.txt").arguments,
            ["propset", "--non-interactive", "--", "custom:reviewer", "杨超", "README.txt"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.propdel(name: "svn:eol-style", target: "README.txt").arguments,
            ["propdel", "--non-interactive", "svn:eol-style", "README.txt"]
        )
    }

    func testRevisionPropertyCommandsUseRevpropRevisionAuthAndStableValueBoundary() {
        let auth = ["--username", "u", "--password-from-stdin"]

        XCTAssertEqual(
            SvnCommandBuilder.revisionProplist(
                target: "file:///repo",
                revision: Revision(7),
                authArguments: auth
            ).arguments,
            [
                "proplist", "--revprop", "--xml", "--verbose", "--non-interactive",
                "-r", "7", "--username", "u", "--password-from-stdin", "file:///repo"
            ]
        )
        XCTAssertEqual(
            SvnCommandBuilder.revisionPropset(
                name: "svn:log",
                valueFile: "/tmp/revprop-value",
                target: "file:///repo",
                revision: Revision(7),
                authArguments: auth
            ).arguments,
            [
                "propset", "--revprop", "--encoding", "UTF-8", "--non-interactive",
                "-r", "7", "--username", "u", "--password-from-stdin",
                "--file", "/tmp/revprop-value", "--", "svn:log", "file:///repo"
            ]
        )
        XCTAssertEqual(
            SvnCommandBuilder.revisionPropset(
                name: "custom:reviewed",
                valueFile: "/tmp/revprop-value",
                target: "file:///repo",
                revision: Revision(7)
            ).arguments,
            [
                "propset", "--revprop", "--non-interactive", "-r", "7",
                "--file", "/tmp/revprop-value", "--", "custom:reviewed", "file:///repo"
            ]
        )
    }

    func testLockCommandsUseNonInteractiveUtf8MessageForceAndTargets() {
        XCTAssertEqual(
            SvnCommandBuilder.lockStatus(targets: ["README.txt"]).arguments,
            ["status", "--xml", "--show-updates", "--non-interactive", "README.txt"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.lock(paths: ["README.txt"], message: "锁定：编辑中", force: true).arguments,
            ["lock", "--encoding", "UTF-8", "--non-interactive", "--force", "-m", "锁定：编辑中", "README.txt"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.lock(paths: ["README.txt"], message: nil, force: false).arguments,
            ["lock", "--encoding", "UTF-8", "--non-interactive", "README.txt"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.unlock(paths: ["README.txt"], force: true).arguments,
            ["unlock", "--non-interactive", "--force", "README.txt"]
        )
    }

    func testExperimentalShelvingCommandsUseStableArgumentBoundaries() {
        XCTAssertEqual(
            SvnCommandBuilder.experimentalShelve(
                name: "demo",
                paths: ["file.txt"],
                message: "临时搁置",
                keepLocal: true
            ).arguments,
            ["x-shelve", "--keep-local", "--encoding", "UTF-8", "-m", "临时搁置", "--", "demo", "file.txt"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.experimentalUnshelve(name: "demo", version: 2, drop: false).arguments,
            ["x-unshelve", "--", "demo", "2"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.experimentalUnshelve(name: "demo", version: nil, drop: true).arguments,
            ["x-unshelve", "--drop", "--", "demo"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.experimentalShelfList().arguments,
            ["x-shelf-list", "--verbose", "."]
        )
        XCTAssertEqual(
            SvnCommandBuilder.experimentalShelfDiff(name: "demo", version: 3).arguments,
            ["x-shelf-diff", "--", "demo", "3"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.experimentalShelfLog(name: "demo").arguments,
            ["x-shelf-log", "--", "demo"]
        )
        XCTAssertEqual(
            SvnCommandBuilder.experimentalShelfDrop(name: "demo").arguments,
            ["x-shelf-drop", "--", "demo", "."]
        )
    }
}
