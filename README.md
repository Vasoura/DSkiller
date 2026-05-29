# DSkiller (v1.0.0)

一个 100% 纯 Swift 原生的 macOS 菜单栏免安装小工具，自动实时清理指定文件夹及其子目录下的 `.DS_Store` 垃圾文件。

无需 Python 或 `fswatch` 依赖，内存/CPU 占用极低，体积轻量（仅数百 KB）。

---

## ✨ 核心功能

- **🟢 动态状态**：菜单栏实时显示监听状态（绿色运行中 / 红色已暂停）。
- **🎛️ 整合管理**：一键添加、删除和查看监听目录。
- **⏱️ 自由调节**：内置拖动条支持 10 秒到 1 分钟扫描间隔微调。
- **🔒 权限检测**：准确的“完全磁盘访问权限 (FDA)”动态检测与状态显示。
- **📝 日志系统**：秒级自动刷新日志查看器，支持一键清空日志文件。
- **🔌 开机启动**：支持原生配置开机自启动。

---

## 🛠️ 编译与打包

1. 进入 `menubar-app` 文件夹：
   ```bash
   cd menubar-app
   ```
2. 依次运行编译与打包脚本：
   ```bash
   ./build_app.sh
   ./build_dmg.sh
   ```
   - 脚本会自动编译并打包成 `DSkiller-1.0.0.dmg`，同时**自动清除本地 `.app` 文件夹**，确保工作区干净。

---

## 📥 安装与权限授予

1. 双击打开 `DSkiller-1.0.0.dmg`，将 **DSkiller** 拖入 **Applications**。
2. 启动后，若要监控桌面/文档等系统目录，需授予完全磁盘访问权限：
   - 点击 DSkiller 菜单 -> `系统权限与依赖状态` -> `如何授予完全磁盘访问权限 (FDA)...`
   - 根据引导在系统设置中勾选启用 `DSkiller`。

---

## 📂 核心路径

- **配置**: `~/Library/Application Support/DSkiller/config.json`
- **日志**: `~/Library/Logs/dskiller.log` （及 `dskiller.err.log`）

---

## 📜 协议
MIT License.
