# P1 SwiftUI App Shell 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 补齐文档中缺失的 SwiftUI App 主工程入口，让当前 Swift Package 不再只有 `MacSvnCore`，而是能构建一个承载 WC、变更、提交、Diff、日志、仓库浏览、分支、合并、AI 等页面入口的 MacSVN 桌面应用骨架。

**架构：** 新增 `MacSvnApp` library target 作为 Presentation 层，依赖 `MacSvnCore` 但不反向污染 Core；新增 `MacSvnDesktopApp` executable target 提供 `@main` SwiftUI App 入口。第一步只建立可测试的路由目录、侧边栏分组和占位详情视图，后续切片再逐页替换为真实 ViewModel 驱动页面。

**技术栈：** Swift 6.1、Swift Package Manager、SwiftUI、Observation、XCTest。

---

## 文件结构

- 修改：`Package.swift`
  - 新增 library product `MacSvnApp`。
  - 新增 executable product `MacSvnDesktopApp`。
  - 新增 target `MacSvnApp`，依赖 `MacSvnCore`。
  - 新增 executable target `MacSvnDesktopApp`，依赖 `MacSvnApp`。
  - 新增 test target `MacSvnAppTests`，依赖 `MacSvnApp`。
- 创建：`Sources/MacSvnApp/App/MacSvnAppRoute.swift`
  - 定义 `MacSvnAppRoute`、`MacSvnAppSection`、`MacSvnSidebarSection`、`MacSvnSidebarModel`。
  - 路由覆盖文档中的主界面：WC、变更、提交、Diff、日志、仓库浏览、分支/标签、合并、Blame、属性、锁、搁置、Git 迁移、团队活动、AI 助手、设置。
- 创建：`Sources/MacSvnApp/App/MacSvnRootView.swift`
  - 定义 `MacSvnRootView`，使用 `NavigationSplitView` 渲染侧边栏与详情占位。
  - 定义可复用的 `MacSvnRoutePlaceholderView` 与 `MacSvnSettingsPlaceholderView`。
- 创建：`Sources/MacSvnDesktopApp/MacSvnDesktopApp.swift`
  - 定义 `@main` App 入口，WindowGroup 标题为 `MacSVN`。
- 创建测试：`Tests/MacSvnAppTests/MacSvnAppRouteTests.swift`
  - 覆盖路由目录、侧边栏分组、默认选中项和稳定命令 ID。
- 修改：`docs/superpowers/plans/2026-07-10-p1-swiftui-app-shell.md`
  - 随任务完成勾选步骤并提交验证记录。

---

## 任务 1：SwiftUI App 路由目录

**文件：**
- 修改：`Package.swift`
- 创建测试：`Tests/MacSvnAppTests/MacSvnAppRouteTests.swift`
- 创建：`Sources/MacSvnApp/App/MacSvnAppRoute.swift`

- [x] **步骤 1：编写失败测试**

先更新 `Package.swift` 增加 `MacSvnAppTests` test target 与待实现的 `MacSvnApp` target，然后创建 `Tests/MacSvnAppTests/MacSvnAppRouteTests.swift`：

```swift
import XCTest
@testable import MacSvnApp

final class MacSvnAppRouteTests: XCTestCase {
    func testRouteCatalogCoversDocumentedPrimarySurfaces() {
        let routes = MacSvnAppRoute.allCases

        XCTAssertEqual(routes.first, .workspace)
        XCTAssertEqual(routes.last, .settings)
        XCTAssertEqual(Set(routes), [
            .workspace,
            .changes,
            .commit,
            .diff,
            .log,
            .repositoryBrowser,
            .branches,
            .merge,
            .blame,
            .properties,
            .locks,
            .shelve,
            .gitMigration,
            .teamActivity,
            .aiAssistant,
            .settings
        ])
        XCTAssertEqual(routes.map(\.title), [
            "工作副本",
            "变更",
            "提交",
            "Diff",
            "日志",
            "仓库浏览器",
            "分支与标签",
            "冲突合并",
            "Blame",
            "属性",
            "锁定",
            "本地搁置",
            "Git 迁移",
            "团队动态",
            "AI 助手",
            "设置"
        ])
    }

    func testSidebarModelGroupsRoutesInWorkflowOrder() {
        let model = MacSvnSidebarModel(routes: MacSvnAppRoute.allCases)

        XCTAssertEqual(model.defaultSelection, .workspace)
        XCTAssertEqual(model.sections.map(\.section), [
            .dailyWork,
            .repository,
            .conflictResolution,
            .advancedSVN,
            .automation,
            .settings
        ])
        XCTAssertEqual(model.sections[0].routes, [.workspace, .changes, .commit, .diff, .log])
        XCTAssertEqual(model.sections[1].routes, [.repositoryBrowser, .branches])
        XCTAssertEqual(model.sections[2].routes, [.merge])
        XCTAssertEqual(model.sections[3].routes, [.blame, .properties, .locks, .shelve])
        XCTAssertEqual(model.sections[4].routes, [.gitMigration, .teamActivity, .aiAssistant])
        XCTAssertEqual(model.sections[5].routes, [.settings])
    }

    func testRoutesExposeStableCommandIDsAndSidebarSymbols() {
        XCTAssertEqual(MacSvnAppRoute.workspace.commandID, "workspace")
        XCTAssertEqual(MacSvnAppRoute.repositoryBrowser.commandID, "repository-browser")
        XCTAssertEqual(MacSvnAppRoute.gitMigration.commandID, "git-migration")
        XCTAssertEqual(MacSvnAppRoute.aiAssistant.commandID, "ai-assistant")

        for route in MacSvnAppRoute.allCases {
            XCTAssertFalse(route.systemImage.isEmpty, "\(route) should have an SF Symbol name")
            XCTAssertFalse(route.subtitle.isEmpty, "\(route) should have a placeholder subtitle")
        }
    }
}
```

- [x] **步骤 2：运行测试验证失败**

```bash
swift test --filter MacSvnAppRouteTests
```

预期：编译失败，提示 `MacSvnAppRoute` / `MacSvnSidebarModel` 等类型不存在。

- [x] **步骤 3：实现最少路由目录**

创建 `Sources/MacSvnApp/App/MacSvnAppRoute.swift`：

```swift
import Foundation

public enum MacSvnAppSection: String, CaseIterable, Identifiable, Sendable {
    case dailyWork
    case repository
    case conflictResolution
    case advancedSVN
    case automation
    case settings

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .dailyWork:
            "日常工作"
        case .repository:
            "仓库"
        case .conflictResolution:
            "冲突"
        case .advancedSVN:
            "高级 SVN"
        case .automation:
            "自动化"
        case .settings:
            "配置"
        }
    }
}
```

继续在同一文件定义 `MacSvnAppRoute`：

```swift
public enum MacSvnAppRoute: String, CaseIterable, Identifiable, Hashable, Sendable {
    case workspace
    case changes
    case commit
    case diff
    case log
    case repositoryBrowser
    case branches
    case merge
    case blame
    case properties
    case locks
    case shelve
    case gitMigration
    case teamActivity
    case aiAssistant
    case settings

    public var id: String { rawValue }

    public var commandID: String {
        switch self {
        case .repositoryBrowser:
            "repository-browser"
        case .gitMigration:
            "git-migration"
        case .teamActivity:
            "team-activity"
        case .aiAssistant:
            "ai-assistant"
        default:
            rawValue
        }
    }
}
```

为每个 route 补齐 `title`、`subtitle`、`systemImage`、`section`，严格匹配步骤 1 测试中的中文标题。创建 `MacSvnSidebarSection` 与 `MacSvnSidebarModel`：

```swift
public struct MacSvnSidebarSection: Equatable, Identifiable, Sendable {
    public var id: MacSvnAppSection { section }
    public let section: MacSvnAppSection
    public let routes: [MacSvnAppRoute]
}

public struct MacSvnSidebarModel: Equatable, Sendable {
    public let sections: [MacSvnSidebarSection]
    public let defaultSelection: MacSvnAppRoute

    public init(routes: [MacSvnAppRoute] = MacSvnAppRoute.allCases) {
        let grouped = Dictionary(grouping: routes, by: \.section)
        sections = MacSvnAppSection.allCases.compactMap { section in
            let sectionRoutes = routes.filter { route in
                grouped[section, default: []].contains(route)
            }
            guard !sectionRoutes.isEmpty else {
                return nil
            }
            return MacSvnSidebarSection(section: section, routes: sectionRoutes)
        }
        defaultSelection = routes.first ?? .workspace
    }
}
```

- [x] **步骤 4：运行目标测试验证通过**

```bash
swift test --filter MacSvnAppRouteTests
```

预期：`MacSvnAppRouteTests` 全部 PASS。

- [x] **步骤 5：Commit**

```bash
git add Package.swift Sources/MacSvnApp/App/MacSvnAppRoute.swift Tests/MacSvnAppTests/MacSvnAppRouteTests.swift docs/superpowers/plans/2026-07-10-p1-swiftui-app-shell.md
git diff --cached --check
git commit -m "feat: add P1 SwiftUI app route shell"
```

---

## 任务 2：SwiftUI Root View 与 App 入口

**文件：**
- 创建：`Sources/MacSvnApp/App/MacSvnRootView.swift`
- 创建：`Sources/MacSvnDesktopApp/MacSvnDesktopApp.swift`

- [x] **步骤 1：实现 Root View**

创建 `Sources/MacSvnApp/App/MacSvnRootView.swift`，最少包含：

```swift
import SwiftUI

public struct MacSvnRootView: View {
    private let sidebarModel: MacSvnSidebarModel
    @State private var selection: MacSvnAppRoute

    public init(sidebarModel: MacSvnSidebarModel = MacSvnSidebarModel()) {
        self.sidebarModel = sidebarModel
        _selection = State(initialValue: sidebarModel.defaultSelection)
    }

    public var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(sidebarModel.sections) { section in
                    Section(section.section.title) {
                        ForEach(section.routes) { route in
                            Label(route.title, systemImage: route.systemImage)
                                .tag(route)
                        }
                    }
                }
            }
            .navigationTitle("MacSVN")
        } detail: {
            MacSvnRoutePlaceholderView(route: selection)
        }
    }
}
```

同文件定义 `MacSvnRoutePlaceholderView`，展示 route 的 `title`、`subtitle` 与 `systemImage`；只用占位说明，不描述快捷键或内部实现细节。

- [x] **步骤 2：实现 App executable 入口**

创建 `Sources/MacSvnDesktopApp/MacSvnDesktopApp.swift`：

```swift
import SwiftUI
import MacSvnApp

@main
struct MacSvnDesktopApplication: App {
    var body: some Scene {
        WindowGroup("MacSVN") {
            MacSvnRootView()
                .frame(minWidth: 980, minHeight: 640)
        }

        Settings {
            MacSvnSettingsPlaceholderView()
        }
    }
}
```

- [x] **步骤 3：运行 App target 构建验证**

```bash
swift build --product MacSvnDesktopApp
```

预期：构建通过。

- [x] **步骤 4：运行 App 路由测试验证未回归**

```bash
swift test --filter MacSvnAppRouteTests
```

预期：`MacSvnAppRouteTests` 全部 PASS。

- [x] **步骤 5：Commit**

```bash
git add Sources/MacSvnApp/App/MacSvnRootView.swift Sources/MacSvnDesktopApp/MacSvnDesktopApp.swift docs/superpowers/plans/2026-07-10-p1-swiftui-app-shell.md
git diff --cached --check
git commit -m "feat: add P1 SwiftUI app entry point"
```

---

## 任务 3：目标验证与计划收尾

**文件：**
- 修改：`docs/superpowers/plans/2026-07-10-p1-swiftui-app-shell.md`

- [ ] **步骤 1：运行 App Shell 目标集合**

```bash
swift test --filter MacSvnAppRouteTests
swift build --product MacSvnDesktopApp
```

预期：目标测试与 App target 构建 PASS。

- [ ] **步骤 2：运行全量验证**

```bash
swift test
```

预期：全部 XCTest PASS。

- [ ] **步骤 3：运行空白检查**

```bash
git diff --check
```

预期：无输出、退出码 0。

- [ ] **步骤 4：更新计划勾选并提交验证记录**

将本计划完成步骤勾选为 `[x]`，提交：

```bash
git add docs/superpowers/plans/2026-07-10-p1-swiftui-app-shell.md
git diff --cached --check
git commit -m "docs: complete P1 SwiftUI app shell verification"
```

## 自检

- 覆盖 `docs/03-high-level-design.md` 中 L4 Presentation 层的工程入口缺口：新增 SwiftUI App target 和 Root View。
- 覆盖 `README.md` 目录规划中的 `MacSvnDesktop/ SwiftUI App 主工程` 的最小可构建形态。
- 保持层次依赖单向：`MacSvnApp -> MacSvnCore`，Core 不依赖 App。
- 不实现真实页面细节、文件选择器、拖拽、菜单栏、FinderSync、QuickLook extension、签名公证或 Sparkle；这些继续拆为后续 UI/系统集成切片。
