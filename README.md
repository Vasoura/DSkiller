# DSkiller (v1.0.0)

一个 100% 纯 Swift 原生的 macOS 菜单栏小工具，常驻后台实时自动清理指定目录下的 `.DS_Store` 垃圾文件。

---

## ✨ 功能特点

- **全功能菜单栏应用**：动态状态指示（运行/暂停）、一键管理监听目录、10s~60s间隔调节、FDA 权限检测、实时日志查看与一键清空及开机自启。

---

## 🛠️ 编译与打包

- 在 `menubar-app` 目录下依次执行 `./build_app.sh` 与 `./build_dmg.sh` 即可在项目根目录生成 `DSkiller-1.0.0.dmg` 且不留任何临时 `.app`。

---

## 📥 安装与授权

- 双击 `DSkiller-1.0.0.dmg` 拖入 Applications，启动后在系统“完全磁盘访问权限 (FDA)”中勾选启用即可。

---

## 📂 核心路径

- **配置**: `~/Library/Application Support/DSkiller/config.json`
- **日志**: `~/Library/Logs/dskiller.log`

---

## 📜 协议

MIT License.
