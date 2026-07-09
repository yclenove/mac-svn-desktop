# P1 Working Copy Backend 实现计划

> **面向 AI 代理的工作者：** 必需子技能：使用 superpowers:subagent-driven-development（推荐）或 superpowers:executing-plans 逐任务实现此计划。步骤使用复选框（`- [ ]`）语法来跟踪进度。

**目标：** 补齐 P1 后端的工作副本日常命令：`add/delete/revert/cleanup/diff/log`，并实现 `svn log --xml -v` 解析。

**架构：** 继续保持 `SvnCliBackend` 很薄：`SvnCommandBuilder` 负责参数顺序，parser 负责结构化输出，backend 负责运行命令和错误映射。新增 log 模型与 parser 不依赖真实进程，后端测试使用记录型 runner 验证命令和解析。

**技术栈：** Swift 6.1、Swift Package Manager、XCTest、Foundation `XMLParser`。

---

## 文件结构

- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
  增加 `LogEntry`、`ChangedPath`、`ChangedPathAction`。
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
  增加 `add/delete/revert/cleanup/diff/log` 命令构造。
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
  增加 P1 剩余后端协议方法。
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
  实现 P1 剩余后端方法。
- 创建：`Sources/MacSvnCore/Parsers/LogXMLParser.swift`
  解析 `svn log --xml -v`。
- 测试：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
  覆盖新增命令参数。
- 测试：`Tests/MacSvnCoreTests/LogXMLParserTests.swift`
  覆盖 revision/author/date/message/changed paths。
- 测试：`Tests/MacSvnCoreTests/SvnCliBackendWorkingCopyTests.swift`
  覆盖后端方法调用、工作目录、stdout 解析、错误沿用。

## 任务 1：命令构造与 log parser

**文件：**
- 修改：`Sources/MacSvnCore/Models/SvnModels.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCommandBuilder.swift`
- 创建：`Sources/MacSvnCore/Parsers/LogXMLParser.swift`
- 测试：`Tests/MacSvnCoreTests/SvnCommandBuilderTests.swift`
- 测试：`Tests/MacSvnCoreTests/LogXMLParserTests.swift`

- [ ] **步骤 1：编写失败测试**

在 `SvnCommandBuilderTests` 增加新增命令断言：`add`、`delete`、`revert`、`cleanup`、`diff`、`log`。创建 `LogXMLParserTests`，用包含中文说明和 copyfrom 信息的 XML 验证 `LogEntry`。

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnCommandBuilderTests && swift test --filter LogXMLParserTests`
预期：FAIL 或编译失败，提示新增 API 未定义。

- [ ] **步骤 3：实现最少代码**

增加模型、命令构造和 `LogXMLParser`。日期按 SVN UTC ISO8601 解析；非法 XML 抛 `SvnError.parse`。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter SvnCommandBuilderTests && swift test --filter LogXMLParserTests`
预期：PASS。

- [ ] **步骤 5：Commit**

```bash
git add Sources/MacSvnCore Tests/MacSvnCoreTests docs/superpowers/plans/2026-07-09-p1-working-copy-backend.md
git commit -m "feat: add P1 working copy command parsers"
```

## 任务 2：SvnCliBackend P1 剩余方法

**文件：**
- 修改：`Sources/MacSvnCore/Backend/SvnBackend.swift`
- 修改：`Sources/MacSvnCore/Backend/SvnCliBackend.swift`
- 测试：`Tests/MacSvnCoreTests/SvnCliBackendWorkingCopyTests.swift`

- [ ] **步骤 1：编写失败测试**

创建 `SvnCliBackendWorkingCopyTests`，用记录型 runner 验证：
- `add/delete/revert/cleanup` 使用 WC 作为 `currentDirectory`，成功时不解析 stdout；
- `diff` 返回 UTF-8 diff 文本；
- `log` 运行 `log --xml -v -l <batch>` 并解析 `LogEntry`。

- [ ] **步骤 2：运行测试验证失败**

运行：`swift test --filter SvnCliBackendWorkingCopyTests`
预期：FAIL 或编译失败，提示 backend 方法未定义。

- [ ] **步骤 3：实现最少代码**

扩展 `SvnBackend` 与 `SvnCliBackend`。所有方法复用统一 `run`，非零 exit code 仍由 `SvnErrorMapper` 分类。

- [ ] **步骤 4：运行测试验证通过**

运行：`swift test --filter SvnCliBackendWorkingCopyTests`
预期：PASS。

- [ ] **步骤 5：运行全部测试并 Commit**

运行：`swift test`
预期：全部 PASS。

```bash
git add Sources/MacSvnCore Tests/MacSvnCoreTests
git commit -m "feat: add P1 working copy backend methods"
```
