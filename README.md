# Venera

[![flutter](https://img.shields.io/badge/flutter-3.41.4-blue)](https://flutter.dev/)
[![License](https://img.shields.io/github/license/DAZING-FOR/venera)](LICENSE)
[![Flutter Build](https://github.com/DAZING-FOR/venera/actions/workflows/main.yml/badge.svg)](https://github.com/DAZING-FOR/venera/actions)

> 本仓库是基于 [venera-app/venera](https://github.com/venera-app/venera) 的修改版。
> 原作者因精力有限已停止维护。此 fork 在原基础上进行了一系列性能优化和功能增强。

跨平台漫画阅读器，支持本地漫画和网络漫画源。

## 与上游的差异（此 fork 新增）

| 改动 | 说明 |
|------|------|
| 🚀 **启动加速** | 优化初始化流程，非关键模块延迟加载，不阻塞启动 |
| ⚡ **Tab 切换优化** | 修复 Navigator 嵌套导致的页面卡顿，主页导航重写 |
| 🌐 **JM 域名自动管理** | 内置域名测速，自动选择最快可用域名，持久化缓存 |
| ⬇️ **并发下载控制** | 图片下载信号量限流（默认5，可配置1-16），页面预解码范围扩大 |
| 🔄 **网络错误自动重试** | 首页、探索页加载失败自动重试一次 |
| 📄 **"我的"页面重做** | 更清晰的入口分组，新增功能直达 |
| 🔌 **JM 源自动安装** | 首次启动自动从 CDN 安装禁漫天堂源，无需手动导入 |
| 🧠 **漫画详情缓存** | 会话内漫画详情内存缓存，减少重复请求 |
| 🛠 **域名兜底** | 多个 CDN/镜像源配置，断网/失效时自动切换 |

## 功能

- 本地漫画阅读
- 通过 JavaScript 创建漫画源
- 网络漫画源阅读
- 收藏管理
- 漫画下载
- 查看评论、标签等（源支持的情况下）
- 登录评论、评分等（源支持的情况下）
- **WebDAV 跨设备同步**
- **Headless 模式**（命令行爬虫/脚本）

## ⚠️ 重要：与原版不兼容

本 fork 使用**自定义签名密钥**构建 Android 包，与官方原版签名不同：

1. **必须先卸载原版** — 由于 Android 签名冲突，无法直接覆盖安装原版 venera
2. **数据不互通** — 原版与本 fork 的应用数据隔离，卸载原版前请确认是否需要备份数据（收藏、历史等）
3. **包名相同** — 为尽量与原版对齐，`applicationId` 保持 `com.github.wgh136.venera` 不变

### 数据迁移

如果你之前使用原版，想要迁移数据到本 fork：

1. 在原版中导出数据（如有 WebDAV 同步功能）
2. 卸载原版
3. 安装本 fork 版本
4. 导入数据

> **提示：** 你也可以更改 `android/app/build.gradle` 中的 `applicationId` 来避免冲突，但需要注意这也会导致无法从原版迁移部分数据。

## 从源码构建

### 系统要求

- Flutter 3.41.4+
- Dart SDK >=3.8.0
- Rust 1.85.1+（编译 rhttp native）

### 构建步骤

```bash
# 1. 克隆
git clone https://github.com/DAZING-FOR/venera.git
cd venera

# 2. 安装依赖
flutter pub get

# 3. 构建（选择你的平台）
flutter build apk            # Android APK
flutter build windows        # Windows
flutter build linux          # Linux (appimage/deb)

# 4. Linux 额外打包
flutter build linux                                     # 常规构建
dart run flutter_to_debian                              # deb 包
dart run flutter_to_arch                                # Arch Linux 包
```

### Android 签名配置

`android/key.properties` 不存在于仓库中（已 `.gitignore`），需要自行创建：

```properties
storeFile=path/to/your/keystore.jks
storePassword=your_store_password
keyAlias=your_key_alias
keyPassword=your_key_password
```

## 编写漫画源

参见 [Comic Source](doc/comic_source.md) 文档。

## Headless 模式

参见 [Headless Doc](doc/headless_doc.md)。

## 致谢

- [venera-app/venera](https://github.com/venera-app/venera) — 上游项目
- [EhTagTranslation](https://github.com/EhTagTranslation/Database) — 标签中文翻译
- [JMComic-Crawler-Python](https://github.com/hect0x7/JMComic-Crawler-Python) — 域名列表

## 许可

GNU General Public License v3.0 — 详见 [LICENSE](LICENSE)
