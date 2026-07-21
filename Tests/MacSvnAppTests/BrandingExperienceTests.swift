import XCTest
import MacSvnCore
@testable import MacSvnApp

final class BrandingExperienceTests: XCTestCase {
    func testProductBrandingExposesStableIconAndProjectMetadata() {
        XCTAssertEqual(ProductBranding.iconResourceName, "SVNStudio.icns")
        XCTAssertEqual(ProductBranding.aboutWindowID, "about")
        XCTAssertEqual(
            ProductBranding.sourceRepositoryURL.absoluteString,
            "https://github.com/yclenove/mac-svn-desktop"
        )
    }

    func testPackagedAndXcodeAppsEmbedTheDeclaredIcon() throws {
        let info = try Self.readRepoSource(at: "Packaging/SVNStudio/Info.plist")
        let buildScript = try Self.readRepoSource(at: "scripts/build-macos-app.sh")
        let verifier = try Self.readRepoSource(at: "scripts/verify-macos-app.sh")
        let project = try Self.readRepoSource(at: "MacSVN.xcodeproj/project.pbxproj")
        let iconURL = Self.repoRoot.appendingPathComponent("Packaging/SVNStudio/SVNStudio.icns")

        XCTAssertTrue(info.contains("<key>CFBundleIconFile</key>"))
        XCTAssertTrue(info.contains("<string>SVNStudio.icns</string>"))
        XCTAssertTrue(buildScript.contains("Packaging/SVNStudio/SVNStudio.icns"))
        XCTAssertTrue(verifier.contains("Contents/Resources/SVNStudio.icns"))
        XCTAssertTrue(verifier.contains("cmp -s \"$APP_ICON\""))
        XCTAssertTrue(project.contains("SVNStudio.icns in Resources"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path))
    }

    func testApplicationProvidesBrandedAboutCommandAndPanel() throws {
        let application = try Self.readRepoSource(
            at: "Sources/MacSvnDesktopApp/MacSvnDesktopApp.swift"
        )
        let about = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnAboutView.swift"
        )

        XCTAssertTrue(application.contains("CommandGroup(replacing: .appInfo)"))
        XCTAssertTrue(application.contains("MacSvnAboutView"))
        XCTAssertTrue(application.contains("@Environment(\\.openWindow)"))
        XCTAssertTrue(
            application.contains(
                "Window(LocalizedStringKey(ProductBranding.aboutWindowTitle), id: ProductBranding.aboutWindowID)"
            )
        )
        XCTAssertTrue(application.contains("openWindow(id: ProductBranding.aboutWindowID)"))
        XCTAssertFalse(application.contains(".sheet(isPresented: $showAbout)"))
        XCTAssertTrue(about.contains("NSApp.applicationIconImage"))
        XCTAssertTrue(about.contains("ProductBranding.sourceRepositoryURL"))
        XCTAssertTrue(about.contains("CFBundleShortVersionString"))
        XCTAssertTrue(about.contains("CFBundleVersion"))
    }

    func testEmptyWorkspaceHasDirectPrimaryAndRecoveryActions() throws {
        let source = try Self.readRepoSource(
            at: "Sources/MacSvnApp/Features/MacSvnWorkingCopyShellView.swift"
        )

        XCTAssertTrue(source.contains("MacSvnWelcomeView"))
        XCTAssertTrue(source.contains("添加第一个工作副本"))
        XCTAssertTrue(source.contains("workspaceController.presentAddPanel()"))
        XCTAssertTrue(source.contains("navigator.selectMode(.settings)"))
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
}
