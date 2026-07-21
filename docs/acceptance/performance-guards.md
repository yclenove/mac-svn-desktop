# UI 性能门禁（AttributeGraph）

| 项 | 内容 |
|----|------|
| 日期 | 2026-07-10 |
| 关联 | Tortoise 完美 Loop **T0.1**、`DiffPerformanceLimits` |

## 强制规则

1. `MacSvnWorkingCopyWorkspaceView` **禁止** `VSplitView` / `HSplitView`（用 `HStack`/`VStack` + `frame`）。
2. 嵌入 Diff（`embedded: true`）**禁止**按行 `ForEach` 渲染；单块 `Text` + `DiffPerformanceLimits.truncatedDisplayText`。
3. `rawDiff.count > DiffPerformanceLimits.maxParseCharacterCount` 时 **跳过** `parseLines` / `parseSideBySideRows`。
4. 非嵌入按行渲染行数不得超过 `maxPerLineSwiftUIRowCount`。

## 自动化

- `DiffPerformanceLimitsTests`（Core）
- `WorkingCopyWorkspacePerformanceGuardTests`（App 源码扫描）

```bash
swift test --filter DiffPerformanceLimitsTests
swift test --filter WorkingCopyWorkspacePerformanceGuardTests
```
