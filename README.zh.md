# Click

[English](README.md)

为 macOS 编写的原生按键映射与宏工具。按设备配置，关闭窗口后继续在菜单栏后台运行。

![Click 宏编辑器](docs/images/macros.png)

## 功能

- **按设备映射。** 每把键盘独立配置，将按键映射到另一个键或可复用的宏。
- **宏编排。** 按顺序切换应用、等待、发送快捷键、输入 Unicode 文本，可调整步骤顺序。
- **载入与导出。** 带版本号的 JSON 保存设备、映射和宏；载入后先编辑，保存后生效。
- **后台运行。** 关闭窗口后继续工作，在菜单栏暂停服务、停止宏或退出。
- **登录自启动。** 在设置中开启，macOS 可能要求在登录项设置中批准。
- **原生编辑器。** 紧凑侧栏、行式映射表和有序宏编辑器。切换语言会即时更新界面与菜单，并保留未保存的编辑。
- **本地运行。** 无账号、网络服务、Shell 执行、分析统计或按键历史记录。

## 安装

需要 **macOS 14 或更新版本**。界面默认使用 **English**。在 **Settings → Language** 中切换 English 或简体中文，应用会记住选择。

从 [Releases](https://github.com/MrCroxx/click/releases) 下载符合 CPU 架构的应用，解压后将 **Click.app** 放到 Applications，再授权和启用登录项。构建采用临时签名，未经过 Apple 公证；也可以从源码构建。

1. 安装并激活官方 [Karabiner DriverKit VirtualHIDDevice](https://github.com/pqrs-org/Karabiner-DriverKit-VirtualHIDDevice/releases) **8.5.0 或 8.6.0**（客户端协议 7）。不需要 Karabiner-Elements 主程序。
2. 在 Click 设置中启用**键盘服务**，在 macOS 登录项中批准，并按需授予**辅助功能**与**输入监控**权限。
3. 点击**添加设备**，选择已连接的键盘，添加映射。
4. 若要使用宏，先在宏编排页创建步骤，再把宏分配给按键。
5. 打开设备的**启用映射**，点击**保存**。
6. 按需开启**登录时启动**。

新添加的设备默认不启用映射。保存只应用已启用的配置。暂停会恢复原有键位；启动会恢复最近保存的配置。关闭窗口保持后台运行，退出会恢复映射并停止服务。

## 构建

需要 macOS 上的 Swift 6 和支持 C++23 的 Apple Clang 工具链。固定版本的上游虚拟 HID 客户端使用 C++23。

```sh
make test
make dev
make release
```

`make release` 生成 `build/Click.app` 和当前构建机架构的 `build/Click-macOS-<arch>.zip`。设置 `SIGNING_IDENTITY` 可以使用自己的签名身份。以下命令用示例数据预览界面，不访问键盘：

```sh
make demo
```

`Click.app/Contents/MacOS/Click --background` 启动用户代理，不打开窗口。
应用内包含独立的 **ClickDaemon**，通过 `SMAppService.daemon` 注册为 root LaunchDaemon。
服务只接受当前图形会话用户的已签名 Click 应用连接。用户代理通过心跳维持设备接管；
代理失联、用户会话切换或虚拟驱动断开时释放设备。切换应用和文本插入留在用户会话中执行。
登录自启动负责启动用户代理。

## 配置与恢复

文件保存在 `~/Library/Application Support/Click/`：

- `config.json` — 经过校验并原子保存的配置，仅当前用户可读写。
- `recovery.json` — 旧版映射恢复记录，用于从 v0.1.x 迁移。

设备通过厂商、产品和序列号识别；没有序列号时使用连接位置。无序列号设备更换 USB 接口后可能需要新配置。具有相同身份的多个键盘接口共享配置。后台通过 IOHID 回调处理设备连接变化，界面每两秒刷新设备列表。

新后端独占捕获 HID，通过虚拟 HID 输出，不修改系统映射属性。`recovery.json` 只用于恢复旧版遗留的 `UserKeyMapping`。损坏的配置或恢复文件会显示错误，不会被覆盖。导出的配置可能包含序列号和宏文本，公开分享前请检查。

## 当前边界

- 原始 HID 后端仍待硬件验证。本地测试和打包通过；实体按键与输入法的顺序、权限批准、安全输入、退出与登录、断连恢复仍需在目标 Mac 上实测。现有 v0.1.x 下载仍使用旧后端。
- 支持键盘页按键及左右修饰键。暂不支持以 Fn 为输入键、媒体键映射、鼠标映射、固件编程和 Caps Lock 指示灯同步。映射可以输出按住的 Fn，也可给目标键添加 Fn 修饰（例如用 Fn + F1 输出普通功能键）。受支持的其他键盘输入页会透传，不支持的复合接口留给 macOS，同一键盘的兼容接口仍可接管。没有兼容接口的设备会明确报错。
- 单个物理按键按设备触发，**不再保留 F13–F20，也没有八个宏触发键的限制**。修饰键不能触发宏。
- 物理按键捕获和快捷键输出使用 HID，位于正常输入法处理链路之前。显式 Unicode 文本插入仍是用户会话中的独立动作，可能被安全输入或特定应用拒绝。
- 同时只执行一个宏，重叠触发被忽略。应用激活最多等待五秒；前台应用意外变化时停止后续操作。已经提交的应用启动请求无法撤回。
- Karabiner-Elements 等工具不能同时接管同一物理键盘。虚拟键盘不会被接管。睡眠会暂停映射，唤醒后需手动恢复。

[输入链路说明](docs/input-pipeline.md) 记录了权限边界、失败恢复、驱动版本和硬件验收清单。

## 开发

`ClickCore` 包含配置结构、键码表、原始 HID 路由和旧版映射恢复逻辑；`Click` 包含 SwiftUI 编辑器、AppKit 菜单栏、XPC 客户端、宏执行器及登录项集成。`ClickDaemon` 捕获原始 HID，并通过一个 C++ 适配器调用官方 pqrs 虚拟 HID 客户端。CI 执行测试并上传应用压缩包。

翻译集中在 `Sources/ClickCore/Resources/Translations.json`。新增语言时在 `AppLanguage` 中声明，并提供相同的键和格式参数；本地化测试会检查完整性。应用包包含语言资源。系统原生对话框使用 macOS 语言偏好。

架构参考了 [Olanzi](https://github.com/MrCroxx/olanzi) 的原生宏和生命周期实现；本项目使用独立 UI 和通用键盘后端。相关 Apple 文档：[按键映射](https://developer.apple.com/library/archive/technotes/tn2450/)与[登录项注册](https://developer.apple.com/documentation/servicemanagement/smappservice/register())。

采用 MIT 许可证，欢迎贡献代码和设备兼容性反馈。
