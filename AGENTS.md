# vimember Agent Guide

> 每轮对话默认先读本文件。它只保留必须长期加载的工作边界、协作规则和文档入口；详细产品/视觉/状态说明按需去 `doc/` 查。
> 若与 `contributing_ai.md` 或旧参考资料冲突，以本文件、用户最新要求和用户指定读取的 Figma 内容为准。

## 1. 项目一句话

Vimory 是一个已经上架 App Store 的 iOS 视频日记 App：用户从系统相册导入视频，为视频配一段文字，然后在首页列表、画廊和详情页回看这些视频记忆。仓库名、工程名和本地路径仍保留 `vimember`，不要仅为了与上架名称一致而重命名。

当前工程使用 Swift / SwiftUI，最低目标 iOS 17.0。iOS 26 及以上必须保持当前原生 Liquid Glass 体验；iOS 17-25 只做官方公开 API 的兼容 fallback，不得因此改动 iOS 26 视觉和交互。

当前 App Store 线上基线为 `Vimory 0.1.0 (20)`。`main` 是与上线版本对应的代码副本，也是后续更新唯一允许使用的开发和发布基线。

## 2. 每轮必守边界

1. 用户最新要求优先；不清楚就问，不用“通用 App 做法”补关键产品细节。
2. 每次只处理用户指定任务；不要顺手重构、重做视觉或调整无关模块。
3. 修改前先确认仓库状态和相关文件；修改后说明改了哪些文件、如何验证。
4. 不能验证的内容在回复里标 `NOT VERIFIED`。
5. 正式 UI 以用户指定的 Figma 节点为准；未读取指定 Figma 前，不凭想象实现视觉细节。
6. 不得照搬 `指导文件参考/` 里旧项目的产品语义、页面结构或代码路径；该目录只可作协作方式参考。
7. 不要为了 GitHub 减重而删除本机测试视频、移除 Xcode 工程引用或改种子数据；如果只是不想推大文件，先用 Git 忽略/分支策略处理并向用户说明。
8. App 已有真实用户数据。涉及 SwiftData 模型、沙盒视频目录、文件名、Bundle ID、签名或 Capability 的改动必须先说明升级影响；不得用删除数据库、重建容器或清空沙盒作为迁移方案。

## 3. 必读产品红线

1. 视频日记必须由“视频 + 文字”组成。
2. 导入视频后必须进入编辑流程；编辑页只做视频预览和文字输入，不默认扩展滤镜、剪辑、贴纸等能力。
3. 首页和画廊只展示摘要；详情页展示全文。
4. 首页滚动时视频不播放或不运动；滚动停止后只播放当前屏幕最主要的一条可见视频。
5. 详情页视频自动循环播放；当前详情页视频有声音，首页/列表/preview 视频默认静音。
6. 删除视频日记时，只删除 App 本地数据库记录和沙盒视频文件，任何时候都不能删除系统相册原视频。
7. 首页搜索入口当前隐藏；代码可保留但不得显示，是否恢复待用户确认。
8. 首页长按菜单使用系统 `UIContextMenuInteraction`；不要用自绘菜单、SwiftUI overlay、`LongPressGesture` 或 zIndex 修补替代系统菜单。

详细产品规格见 [doc/PRODUCT_REQUIREMENTS.md](doc/PRODUCT_REQUIREMENTS.md)。

## 4. UI/Figma 入口

Figma 文件：
https://www.figma.com/design/z9ewZ9itwDRhTMK94G08u1/vimember?node-id=0-1&t=xXw4CqlJl4XHgkaf-1

做视觉或交互精修时先查 [doc/FIGMA_UI_RULES.md](doc/FIGMA_UI_RULES.md)，尤其是：

1. 首页 `首页` Frame / `iPhone Air` 尺寸换算规则。
2. 首页视频动态取色底、横竖屏底色高度、渐进融合规则。
3. 画廊 `Frame 8`、Albums 专辑栏、三列视频网格规则。
4. Liquid Glass 控件尺寸和实现边界。

## 5. 技术方向

1. 默认使用 Swift / SwiftUI 和 iOS 公开 API。
2. 本地数据优先 SwiftData；若不适配，说明原因后再改 Core Data 或 SQLite。
3. 视频导入后复制到 App 沙盒，App 播放自己的本地文件；可保存系统相册来源标识，但不能依赖系统相册原视频作为唯一播放源。
4. 视频播放、缩略图生成、文件访问、数据库读写必须管理生命周期和线程，重任务不得阻塞主线程。
5. iOS 26 及以上的可点击 Liquid Glass 按钮统一走原生 `.glassEffect(.regular.interactive(), in:)` + `.buttonStyle(.plain)`；iOS 17-25 使用兼容 material fallback，不要为了兼容而改动 26 的原生玻璃路径。

架构细节按需查：

1. [doc/ARCH_REQUIREMENTS.md](doc/ARCH_REQUIREMENTS.md)
2. [doc/ARCH_TEST_REVIEW.md](doc/ARCH_TEST_REVIEW.md)
3. [doc/PERFORMANCE_BASELINE.md](doc/PERFORMANCE_BASELINE.md)

## 6. 当前状态入口

当前实现状态、已知问题和待确认事项见 [doc/CURRENT_STATUS.md](doc/CURRENT_STATUS.md)。开始修具体功能前，先查看该文件里对应模块，避免重复踩旧坑。

特别注意：当前首页/画廊/详情页/导入流程已有大量 Figma 对齐和用户微调。除非用户明确要求重做，不要以“清理代码”为名改变视觉、布局、动效或视频卡片样式。

## 7. GitHub、文件集与分支

1. `main` 对应原 `/Users/zhangsiyuan/Documents/vimember-release` 文件集，是当前 App Store 上线副本，也是今后唯一的开发、PR 和发布基线。虽然当前检出目录名为 `vimember`，仍以分支内容和本条规则判断身份。
2. `codex/perf-video-evidence` 对应原 `/Users/zhangsiyuan/Documents/vimember` 测试文件集，是带测试视频的历史性能/功能证据分支，不是发布分支。当前该分支含 22 个视频，约 512 MB，且只存在本机；不要从它开始新功能、不要合并到 `main`、不要把其中视频带入发布包，也不要未经用户允许删除。
3. `main` 与 `codex/perf-video-evidence` 是两套没有共同 Git 祖先的历史，禁止对两者做普通 merge 或用“是否已合并”判断内容归属。需要参考历史实现时只读对照，并在 `main` 上重新做最小改动。
4. 除上述两个分支外，现存本地/远程功能分支均视为废弃历史，不作为后续开发来源；`backup/main-before-release-snapshot-20260702` 也只视为发布整理前的历史备份。未经用户明确要求，不清理、不合并、不恢复这些分支。
5. 新任务必须从最新 `main` 创建 `codex/` 前缀分支；功能完成并验证后通过 PR 合并回 `main`。
6. 未经用户确认，不直接把未验证代码推到 `main`。推送前检查 `git status`、staged diff、版本号和大文件，确保测试视频不会进入 `main` 或 App 包。

## 8. 上架后更新红线

详细流程见 [doc/APP_STORE_UPDATE_GUIDE.md](doc/APP_STORE_UPDATE_GUIDE.md)。每次更新至少遵守：

1. 开发前确认 App Store 当前线上 Version / Build，并从最新 `main` 建分支。当前已知线上基线是 `0.1.0 (20)`。
2. 更新必须沿用现有 App Store 记录、Bundle ID `com.brycez021.vimember`、签名与必要 Capability；任何身份或容器变更先向用户确认。
3. 新版本必须完整验证“线上版本覆盖安装到候选版本”，重点检查 SwiftData 记录、专辑、文字和 `Application Support/ImportedVideos` 视频文件，不得只测全新安装。
4. 修改 SwiftData 模型前先设计并验证迁移；不得靠删除 Store、卸载 App 或清空数据让代码通过。
5. 上传前确保 Version 高于当前线上版本、Build 高于线上及所有已上传 Build。`project.yml`、`.xcodeproj` 和 Archive 的最终值必须一致。
6. 权限、数据收集、第三方 SDK 或 Required Reason API 有变化时，同步核对 `Info.plist`、App Store Connect App Privacy、隐私政策和 `PrivacyInfo.xcprivacy`。
7. 必须先完成 Release/Archive 检查和 TestFlight 升级回归，再提交 App Review；涉及迁移或高风险改动时优先手动发布或分阶段发布。

## 9. 建议阅读顺序

1. 每轮先读本文件。
2. 产品行为不清楚：读 [doc/PRODUCT_REQUIREMENTS.md](doc/PRODUCT_REQUIREMENTS.md) 和 [doc/CURRENT_STATUS.md](doc/CURRENT_STATUS.md)。
3. 视觉/Figma/UI 精修：读 [doc/FIGMA_UI_RULES.md](doc/FIGMA_UI_RULES.md)，并按用户指定节点读取 Figma。
4. 架构/测试/性能：读 `doc/ARCH_REQUIREMENTS.md`、`doc/ARCH_TEST_REVIEW.md`、`doc/PERFORMANCE_BASELINE.md`。
5. 版本、分支、发布或上线后数据改动：读 [doc/APP_STORE_UPDATE_GUIDE.md](doc/APP_STORE_UPDATE_GUIDE.md)。
6. 项目背景和路线：按需读 `README.md`、`ROADMAP.md`、`Designsystem.md`、`contributing_ai.md`。
