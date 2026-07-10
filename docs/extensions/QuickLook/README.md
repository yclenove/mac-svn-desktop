# MacSVN Quick Look 扩展（G8）

## 目标

在 Finder 空格预览中展示 SVN 文本 Diff / 冲突三路摘要。

## 落地形态（本仓库阶段）

SwiftPM 无法直接产出 `.appex`。本目录提供：

1. 预览数据契约（输入路径 → 生成 HTML/纯文本预览）；
2. `MacSvnQuickLookPreview.swift` 骨架，供 Xcode QL 扩展 target 使用；
3. 与主应用共享的预览生成约定：优先调用本机 `svn diff --git` 输出。

## 预览策略

| 文件场景 | 预览内容 |
|----------|----------|
| WC 内已修改文本文件 | `svn diff` unified |
| 冲突文件 | base/mine/theirs 摘要（路径旁 `.mine` / `.r*`） |
| 二进制 | 「二进制文件，请在 MacSVN Diff 页查看」 |

## Xcode 集成步骤

1. 用 Xcode 打开仓库根目录 `MacSVN.xcodeproj`，新增 macOS → Quick Look Preview Extension；
2. 加入本目录骨架源文件；
3. Info.plist 声明支持的 UTI（`public.plain-text`、`public.source-code` 等）；
4. 安装后 `qlmanage -r` 刷新缓存。

## 验证

- [ ] 对已修改源文件按空格可见 Diff 预览
- [ ] 冲突文件显示三路提示而非空白
