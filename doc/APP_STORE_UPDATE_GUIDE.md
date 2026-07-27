# Vimory App Store 更新指南

> 本文件约束已经上架后的开发、验证和发布。它不代替 Apple 最新规则；每次提交前仍需核对 App Store Connect 和 Apple Developer 官方要求。

## 1. 当前发布身份

1. App Store 展示名称：`Vimory`。
2. 仓库、Xcode 工程和本地路径仍使用 `vimember`，不要仅为名称一致而重命名。
3. Bundle ID：`com.brycez021.vimember`。
4. 当前线上版本：`0.1.0 (20)`。
5. `main` 对应原 `vimember-release` 文件集，是上线副本和唯一发布基线。
6. `codex/perf-video-evidence` 对应原 `vimember` 测试文件集，只保留历史实现、性能证据和测试视频，不参与发布。

## 2. 开始一次更新

1. 先查看 App Store Connect，确认当前线上 Version / Build 和已经上传但未发布的最高 Build；不能只相信仓库记录。
2. 同步最新 `main`，从它创建新的 `codex/` 开发分支。禁止从 `codex/perf-video-evidence`、其他废弃分支或旧 worktree 开始更新。
3. 在任务开始时写清本次范围、用户可见变化、是否涉及数据模型/文件、权限、隐私、第三方 SDK 和最低系统版本。
4. 如果需求会改变 App 名称、Bundle ID、签名、Capability、App Group、Keychain Group、iCloud Container、数据收集、付费方式或系统最低版本，编码前先向用户确认。

## 3. 上架后编码注意事项

### 3.1 用户数据与升级兼容

1. 把“更新安装”作为默认场景。用户设备上已经存在 SwiftData Store、专辑、文字记录和复制到 `Application Support/ImportedVideos` 的视频。
2. 修改 `VideoDiaryRecord`、`VideoAlbumRecord` 或 ModelContainer Schema 前，先列出旧模型到新模型的迁移方案并补升级验证。新增字段优先使用兼容默认值或可选值。
3. 不得通过删除数据库、改 Store 路径、清空沙盒、卸载 App 或重新 seed 数据处理迁移问题。
4. 修改视频目录、文件名或引用关系时，必须保证旧记录仍能找到旧文件，并处理迁移中断或部分成功的情况。
5. 删除视频日记仍然只能删除 App 本地记录和对应沙盒视频，任何时候都不得删除系统相册原视频。
6. 迁移失败必须有可恢复或安全停止路径，不能静默丢弃用户数据。

### 3.2 App 身份和兼容性

1. 沿用 Bundle ID `com.brycez021.vimember`、发行签名和当前必要 Capability。不要因为 App Store 名称为 Vimory 就修改工程目录或 Bundle ID。
2. 保持最低 iOS 17.0，除非用户明确决定提高。iOS 26 及以上继续保留原生 Liquid Glass 路径，iOS 17-25 使用公开 API fallback。
3. 新增权限时同步提供准确的 `Info.plist` 用途说明，并覆盖允许、拒绝、受限和取消流程。
4. 新增或升级第三方 SDK 时检查其数据收集、Privacy Manifest、体积、最低系统要求和 App Review 风险。
5. `main` 和发布包中不得重新加入 sample/bundled 测试视频或启动 seed 测试数据逻辑。

### 3.3 版本号与工程生成

1. 新 App Store 版本的 Version 必须高于线上 `0.1.0`；具体版本号由本次改动范围和用户决定，不自动猜测。
2. 新上传 Build 必须高于线上 Build `20`，也必须高于 App Store Connect 中同一 Version 已上传的最高 Build。每次重新上传前继续递增。
3. 当前检查发现 `.xcodeproj` 为 `0.1.0 (4)`，`project.yml` 为 `0.1.0 (1)`，两者都落后于线上 `0.1.0 (20)`。下一次 Archive 前必须先统一为本次更新的正确值。
4. 运行 `scripts/xcode-dev generate` / XcodeGen 会以 `project.yml` 重建工程；生成前先更新 `project.yml`，生成后复核 `.xcodeproj` 的 `MARKETING_VERSION`、`CURRENT_PROJECT_VERSION`、Bundle ID、部署目标和设备范围。
5. 上传前在 Archive 的 General Information 或导出验证结果中再次确认实际 Version / Build，不只检查源码文本。

## 4. 更新验证门槛

### 4.1 必做升级测试

1. 在专用测试设备上安装当前线上 `0.1.0 (20)`。
2. 创建横屏/竖屏视频日记、长短文字、空专辑和有内容专辑，记录升级前状态。
3. 用 TestFlight 候选 Build 覆盖安装，不卸载旧版本。
4. 验证记录数量、文字、日期、专辑归属、封面和本地视频均保留且可播放。
5. 再验证导入、编辑、分享、删除、重新启动、前后台切换和存储不足/权限异常路径。
6. 如果修改过 Schema 或文件布局，至少验证一次迁移中断后的重新启动行为。

### 4.2 发布候选检查

1. Debug 模拟器 Build 通过只是基础门槛；还必须完成 Release 配置的真机 Build/Archive。
2. 覆盖最低支持系统和当前主要系统版本，分别检查 iOS 17 fallback 与 iOS 26 及以上原生 Liquid Glass。
3. 检查首页滚动只播放主要视频、详情有声循环播放、其他 preview 默认静音，以及退出页面后的播放器释放。
4. 检查 App 包资源和体积，确认没有测试视频、测试数据、私有素材或不需要的调试文件。
5. 检查崩溃、主线程卡顿、视频导入峰值内存和长列表性能。
6. 没有完成的项目在发布记录中标为 `NOT VERIFIED`，不得用“构建成功”代替真机、升级和 TestFlight 验证。

## 5. App Store Connect 提交流程

1. 在 App Store Connect 的现有 Vimory App 记录中创建更高的 iOS Version，不要新建另一个 App。
2. 填写 `What's New in This Version`、审核联系信息和审核备注；UI 或商店展示发生变化时更新截图、描述和其他元数据。
3. 如果权限、数据收集或第三方 SDK 行为改变，先更新 App Privacy 和隐私政策；同时检查 `PrivacyInfo.xcprivacy` 与 Required Reason API 声明。
4. 在 Xcode 使用 Release 配置执行 `Product > Archive`，从 Organizer 验证并上传到 App Store Connect。
5. 等待 Build 处理完成，处理失败或有警告时先解决，再选择该 Build。
6. 先分发到 TestFlight，完成升级安装和核心流程回归，再把 Build 加入 App Review submission。
7. 填写出口合规等问题，选择发布方式后提交审核。首次更新或需要控制上线时间时优先手动发布；涉及数据迁移或高风险改动时可考虑 7 天分阶段发布。
8. App Store 不能直接回滚到旧 Build；线上严重问题只能修复后提交更高的新版本，因此提交前必须保留可快速修复的干净 `main` 基线。

## 6. 发布后

1. 确认 App Store 页面显示的 Version、What's New、截图和隐私信息正确。
2. 监控 App Store Connect 中的崩溃、启动、使用和用户反馈；分阶段发布期间重点查看数据打不开、视频丢失、导入失败和播放异常。
3. 发现严重问题时暂停分阶段发布（如果已启用），在最新 `main` 上创建修复分支并提交更高 Version / Build。
4. 发布稳定后在 `doc/CURRENT_STATUS.md` 更新线上 Version / Build、发布日期、验证范围和遗留问题。

## 7. 官方入口

1. [创建新版本](https://developer.apple.com/help/app-store-connect/update-your-app/create-a-new-version)
2. [上传 Build](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
3. [选择版本发布方式](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/select-an-app-store-version-release-option/)
4. [分阶段发布更新](https://developer.apple.com/help/app-store-connect/update-your-app/release-a-version-update-in-phases)
5. [管理 App Privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/)
6. [添加 Privacy Manifest](https://developer.apple.com/documentation/bundleresources/adding-a-privacy-manifest-to-your-app-or-third-party-sdk)
