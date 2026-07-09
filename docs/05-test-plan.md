# Mac SVN Desktop 测试计划

| 项 | 内容 |
|----|------|
| 文档版本 | v1.0 |
| 编写日期 | 2026-07-09 |
| 编写人 | 杨超 |
| 上游文档 | `docs/01-requirements.md`、`docs/04-detailed-design.md` |

## 1. 测试策略总览

| 层级 | 手段 | 覆盖对象 | 运行时机 |
|------|------|----------|----------|
| 单元测试 | XCTest，无外部依赖 | Parsers、MergeEngine、SvnErrorMapper、参数构造、PersistenceStore | 每次提交（CI） |
| 集成测试 | XCTest + 本地临时 SVN 仓库 | SvnCliBackend ↔ 真实 svn 全回路 | 每次提交（CI，需 svn） |
| 对拍测试 | 脚本 fuzz | MergeEngine vs `diff3 -m` | 每日/发版前 |
| 性能测试 | 脚本生成大仓库 + XCTest measure | NFR-01/02 | 每阶段验收 |
| 手工测试 | 用例清单 | UI 交互、真实内网仓库、异常环境 | 阶段验收 |

**通过标准：** 单测/集成测试 100% 通过；解析层与 MergeEngine 行覆盖率 ≥ 90%；性能达 NFR；手工清单零阻断缺陷。

## 2. 测试环境

### 2.1 本地临时仓库（集成测试基础设施）

`scripts/make-test-repo.sh`：

```
svnadmin create → file:// 协议 → 预置 trunk/branches/tags 布局
→ 导入种子文件（含中文文件名、中文内容、二进制文件）
→ checkout 两份 WC（wcA / wcB，用于制造冲突）
```

测试基类 `SvnIntegrationTestCase`：`setUp` 建临时仓库（`FileManager.temporaryDirectory` 下 UUID 目录），`tearDown` 清理；每个用例独立仓库，互不污染。

### 2.2 环境矩阵

| 维度 | 覆盖 |
|------|------|
| macOS | 14（最低）/ 15（主力） |
| svn | 1.14.x（基线）；1.10 降级路径单独手测 |
| 架构 | Apple Silicon（主力）+ Intel（发版前） |
| 协议 | file://（自动化）、https://、svn+ssh://（手测，内网仓库） |

## 3. 单元测试用例（关键组）

### TC-PS：Parsers

| 用例 | 输入 | 断言 |
|------|------|------|
| TC-PS-01 | 标准 status XML（M/A/D/?/!/C 混合） | 各状态计数与路径正确 |
| TC-PS-02 | 含 tree-conflicted 与中文路径的 status | `isTreeConflict=true`、中文路径无损 |
| TC-PS-03 | 10 万 entry 大 XML | 流式分批回调次数正确、内存峰值 < 200 MB |
| TC-PS-04 | 截断/非法 XML | 抛 `SvnError.parse`，不崩溃 |
| TC-PS-05 | log XML（含 -v 变更路径、copyfrom） | revision/author/date/paths 全字段正确 |
| TC-PS-06 | info XML 含 conflict 节点 | 三方文件路径解析正确并转绝对路径 |
| TC-PS-07 | update 输出（A/U/D/C/G 混合 + 未知行） | 计数正确、未知行忽略不抛错 |
| TC-PS-08 | `Committed revision 42.` | 提取 42 |

### TC-ME：MergeEngine

| 用例 | 场景 | 断言 |
|------|------|------|
| TC-ME-01 | 仅 mine 修改 | 无冲突，自动采纳 mine |
| TC-ME-02 | 仅 theirs 修改 | 无冲突，自动采纳 theirs |
| TC-ME-03 | 双方修改不同区域 | 无冲突，双方都采纳 |
| TC-ME-04 | 双方修改同一行且不同 | 产生 conflict 块，三方行内容正确 |
| TC-ME-05 | 双方做出完全相同的修改 | 无冲突，采纳一份 |
| TC-ME-06 | 一方删除、一方修改同区域 | conflict 块（删除侧为空行组） |
| TC-ME-07 | 相邻编辑区间归并 | 重叠/相邻修改合成单个冲突块 |
| TC-ME-08 | 空文件/单行/无换行结尾 | 边界不崩溃、语义正确 |
| TC-ME-09 | resolution 应用（takeMine/takeBoth/manual） | 结果文本拼装正确 |
| TC-ME-10 | 对拍 fuzz（1000 组随机三方文本） | 非冲突输出与 `diff3 -m` 一致；冲突判定不少于 diff3 |

### TC-EM：SvnErrorMapper / 参数构造

- E170001→authentication、E155011→outOfDate、E155004→wcLocked、未知码→other；
- commit argv 必含 `--encoding UTF-8 --non-interactive` 且 message 原样；
- 认证参数不含明文密码（扫描 argv 断言无密码字符串）。

## 4. 集成测试用例（真实 svn 回路）

| 用例 | 流程 | 断言 |
|------|------|------|
| TC-IT-01 | checkout → status | WC 有效、status 为空 |
| TC-IT-02 | 修改/新增/删除文件 → status | 三种状态正确识别 |
| TC-IT-03 | 勾选部分文件 commit（中文说明"修复：登录超时问题 🚀"） | 仅选中文件提交；`svn log` 读回说明逐字节一致 |
| TC-IT-04 | wcA、wcB 同文件同行不同修改 → B 提交 → A update | A 出现冲突 C；info 可取三方文件 |
| TC-IT-05 | TC-IT-04 基础上 MergeEngine 合并 → 写回 → resolve → commit | status 无 C；提交成功；文件内容为合并结果 |
| TC-IT-06 | 浅检出 depth=empty → set-depth files | 目录内容随深度变化正确 |
| TC-IT-07 | copy 创建分支 → switch → 提交 → merge --dry-run → merge 回 trunk | 分支流全通；dry-run 与实际影响文件一致 |
| TC-IT-08 | update 中途取消（大仓库） | 进程终止、WC 可 cleanup 恢复、无残留锁 |
| TC-IT-09 | revert 单文件/递归目录 | 内容还原、状态回 normal |
| TC-IT-10 | 中文目录名 + 中文文件名全流程（add→commit→update→log） | 全程无乱码 |
| TC-IT-11 | 树冲突（A 改文件、B 删文件并提交、A update） | 树冲突识别、keepLocal/acceptRemote 两分支均可恢复正常状态 |
| TC-IT-12 | 二进制文件冲突 | 不进文本合并；mine-full/theirs-full 二选一有效 |

## 5. 性能测试

| 用例 | 场景 | 指标（NFR） |
|------|------|------|
| TC-PF-01 | 脚本生成 1 万文件 WC，10% 变更 → status 全链路 | 首批结果 ≤ 3 s |
| TC-PF-02 | 10 万文件 WC status | 不崩溃、UI 不冻结、可取消、内存 < 500 MB |
| TC-PF-03 | 1 万条日志仓库，连续加载 10 批 | 单批 ≤ 2 s（file:// 基准） |
| TC-PF-04 | 2 万行文件三路合并 | merge3 计算 ≤ 1 s，编辑器滚动 60 fps 无明显掉帧 |

工具：`scripts/make-big-repo.sh`（参数化文件数/日志数）+ XCTest `measure`；UI 帧率用 Instruments Core Animation 手测记录。

## 6. 手工测试清单（阶段验收）

### P1 验收

- [ ] 干净机器（无 svn）首启 → 引导页正确 → 装 svn 后重检通过
- [ ] 拖拽添加 WC；非 WC 目录提示明确
- [ ] 内网 https 仓库：认证弹框 → Keychain 缓存后二次操作免密
- [ ] 中文提交说明在服务端 web 界面/其他客户端显示无乱码
- [ ] 断网 update → 错误横幅含建议；恢复网络重试成功
- [ ] revert 二次确认文案清晰；误触可取消
- [ ] 应用强退后重启：WC 列表恢复、无损坏

### P2 验收

- [ ] 仓库浏览器浏览 10 万条目目录不卡死
- [ ] 浅检出 + 加深操作与 CLI 行为一致
- [ ] 非标准布局仓库配置分支目录后列表正确
- [ ] svn+ssh 仓库按引导配置后可用

### P3 验收

- [ ] 构造 5 类冲突（改-改、改-删、相邻块、多块、二进制）全部在应用内闭环解决
- [ ] 合并编辑器未保存关闭拦截；放弃后冲突状态保持
- [ ] 解决后 `svn status`（CLI 交叉验证）无 C 项

### P4 验收

- [ ] blame 大文件（5000 行）渲染与跳转正常
- [ ] lock/unlock 与他人夺锁流程（双机）
- [ ] 公证构建在全新 macOS 虚拟机 Gatekeeper 直接放行

## 7. CI 方案（GitHub Actions）

```yaml
# .github/workflows/ci.yml（设计稿）
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-15
    steps:
      - checkout
      - brew install subversion        # 集成测试依赖
      - xcodebuild test -scheme MacSvnDesktop -destination 'platform=macOS'
      - 覆盖率上报（xccov → 阈值检查：Parsers/MergeEngine ≥ 90%）
  fuzz-nightly:
    schedule: 每日
    steps: [scripts/diff3-fuzz.sh 1000]
```

## 8. 缺陷管理

- GitHub Issues + 标签：`bug/P0-阻断`、`bug/P1-严重`、`bug/P2-一般`、`bug/P3-轻微`；
- 阻断定义：数据丢失（WC 损坏、合并错误落盘）、崩溃、提交内容与所选不符；
- 每个 bug 修复必须附回归测试（单测或集成用例）。
