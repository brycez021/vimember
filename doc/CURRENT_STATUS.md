# Vimory / vimember Current Status

检查日期：2026-07-10

> 本文件记录当前上线、代码、分支、验证和已知风险。App Store 名称是 `Vimory`；仓库、工程和本地路径继续使用 `vimember`。开始任务前仍需以实际 `git status` 和 App Store Connect 为准。

## 1. 上线与工程身份

1. Vimory 已上架 App Store，用户确认当前线上版本为 `0.1.0 (20)`。
2. Bundle ID 为 `com.brycez021.vimember`，最低目标为 iOS 17.0，发布设备范围为 iPhone。
3. `main` 对应原 `/Users/zhangsiyuan/Documents/vimember-release` 文件集，是上线代码副本和今后唯一的开发/发布基线。当前 `main` 已与 `origin/main` 同步。
4. 当前工作目录虽然是 `/Users/zhangsiyuan/Documents/vimember`，但检出 `main` 时内容身份仍是上述 release 文件集；不要按目录名误判为历史测试版本。
5. 当前 `main` 不包含 sample/bundled 测试视频，也不包含启动时自动 seed 测试视频日记的发布逻辑。

## 2. 当前实现状态

1. App 使用 SwiftUI + SwiftData；`VideoDiaryRecord` 保存日记记录，`VideoAlbumRecord` 保存当前专辑原型，导入视频复制到 `Application Support/ImportedVideos`。
2. 首页支持单栏时间线与三列模式、无视频空状态、右下添加入口、右上显示模式切换；搜索入口继续隐藏。
3. 首页视频滚动期间保持不播放/不运动，停止后选择主要可见视频播放；首页和 preview 默认静音。
4. 首页视频卡片保留动态取色背景、横竖屏差异化融合、标题/日期/横线/两行摘要和系统 Context Menu。
5. 系统 Context Menu 提供 Delete、分享视频、分享文字和 Edit；删除前二次确认。
6. 导入流程支持从系统相册选择视频、视频预览、文字编辑、复制视频到沙盒并写入 SwiftData。
7. 详情页支持有声自动循环播放、完整文字、persistent 毛玻璃文字面板、视差/渐进模糊、可拖动播放进度、编辑、分享和本地删除。
8. 当前专辑实现包含 SwiftData 记录、创建/命名、封面选择、向专辑添加视频、筛选查看和删除等轻量能力；正式产品规则和后续扩展仍以用户确认为准。
9. iOS 26 及以上可点击玻璃控件走原生 Liquid Glass；iOS 17-25 走兼容 fallback。

## 3. 已知产品问题与待确认项

1. 首页系统 Context Menu 的浮起 preview 中，竖版视频仍记录有上下裁切/显示不完整问题。不要用自绘菜单、截图 preview、zIndex 或 LongPressGesture 绕过系统菜单。
2. 摘要固定字数、截断细节和“最主要的一条视频”的最终算法规则仍需按后续任务确认。
3. 专辑已有可运行的持久化原型，但正式专辑数据关系、完整专辑详情页和长期迁移规则仍需用户确认后再扩大实现。
4. 日期显示方式切换、搜索恢复后的范围/结果/空状态、浅色与深色模式仍待确认。
5. 后续新增页面状态或视觉改动仍需读取用户指定的 Figma 节点，不能根据当前代码自行延伸。

## 4. 上架后更新风险

1. 当前 `.xcodeproj` 记录 `0.1.0 (4)`，`project.yml` 记录 `0.1.0 (1)`，都落后于线上 `0.1.0 (20)`。下一次 Archive 前必须先确定新 Version，并把 Build 设置为高于 20 及 App Store Connect 已上传最高值，再同步两处配置。
2. 当前 SwiftData 入口直接使用 `[VideoDiaryRecord.self, VideoAlbumRecord.self]`，仓库中未见 `VersionedSchema` / `SchemaMigrationPlan`。修改现有模型前必须先设计并验证从线上数据升级的迁移。
3. 当前没有单元测试或 UI 测试 Target。构建成功不能替代线上版本覆盖安装、真机和 TestFlight 回归。
4. 仓库中当前未见 `PrivacyInfo.xcprivacy`。这不自动表示当前版本违规，但新增/更新 SDK、数据收集或 Required Reason API 前必须重新判断并补齐需要的声明。
5. `scripts/xcode-dev` 默认把 Xcode 指向 `/Applications/Xcode.app`，但本机当前实际 Xcode 位于 `/Users/zhangsiyuan/Downloads/Xcode-beta.app`；直接运行脚本会先因路径不存在失败，显式覆盖 `DEVELOPER_DIR` 后可构建。
6. 当前有未跟踪的 `vimember.xcodeproj/xcshareddata/xcodecloud/manifest.json`。它不属于本次文档改动，发布或提交前需要单独确认是否纳入版本控制。

详细更新规则和 App Store 提交流程见 [APP_STORE_UPDATE_GUIDE.md](APP_STORE_UPDATE_GUIDE.md)。

## 5. 分支与历史文件集

1. `main`：唯一开发、PR 和发布基线；来源是原 `vimember-release` 文件集。
2. `codex/perf-video-evidence`：对应原 `vimember` 测试文件集的历史证据分支，含 22 个测试视频，约 512 MB；当前只存在本机，没有同名远程分支。
3. `main` 与 `codex/perf-video-evidence` 没有共同 Git 祖先，不能普通 merge，也不能用 Git 的 merged/unmerged 结果判断 release 是否包含某项历史效果。
4. 其他本地/远程功能分支均已标记为废弃历史，不再用于后续开发；远程 `backup/main-before-release-snapshot-20260702` 视为发布整理前的历史备份。
5. 本次未删除任何分支、测试视频或备份。清理分支必须由用户另行明确授权。
6. Git 仍记录三个指向已不存在临时目录的 prunable worktree；它们不改变上述分支用途，本次未清理。

## 6. 本次检查的验证状态

1. `main` 与 `origin/main` 同步：`PASS`（检查时 HEAD 为 `d7f7d20`，文档改动尚未提交）。
2. Debug iOS Simulator Build：`PASS`，使用 `/Users/zhangsiyuan/Downloads/Xcode-beta.app` 的 iOS 27.0 Simulator SDK 构建成功。
3. 单元/UI 测试：`NOT VERIFIED`，工程当前没有测试 Target。
4. Release 真机 Build / Archive / 签名 / App Store 上传：`NOT VERIFIED`。
5. 从 App Store `0.1.0 (20)` 覆盖安装到候选版本的数据迁移：`NOT VERIFIED`，当前没有候选更新 Build。
6. TestFlight、App Review 和正式发布：`NOT VERIFIED`，本次任务仅更新指导文档。
