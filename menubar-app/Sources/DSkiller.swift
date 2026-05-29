import AppKit
import Foundation

struct AppConfig: Codable {
    var targets: [String]
    var interval: Int

    enum CodingKeys: String, CodingKey {
        case targets
        case interval
    }

    static let configDir = "\(NSHomeDirectory())/Library/Application Support/DSkiller"
    static let configPath = "\(configDir)/config.json"
    static let appLaunchLabel = "local.dskiller"
    static let appLaunchPlist = "\(NSHomeDirectory())/Library/LaunchAgents/\(appLaunchLabel).plist"
    static let standardLogPath = "\(NSHomeDirectory())/Library/Logs/dskiller.log"
    static let errorLogPath = "\(NSHomeDirectory())/Library/Logs/dskiller.err.log"

    init(targets: [String], interval: Int = 10) {
        self.targets = targets
        self.interval = interval
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.targets = try container.decode([String].self, forKey: .targets)
        self.interval = (try? container.decode(Int.self, forKey: .interval)) ?? 10
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(targets, forKey: .targets)
        try container.encode(interval, forKey: .interval)
    }

    static var defaultTargets: [String] {
        [
            "\(NSHomeDirectory())/Desktop",
            "\(NSHomeDirectory())/Documents",
        ]
    }

    static func load() -> AppConfig {
        let url = URL(fileURLWithPath: configPath)
        guard
            let data = try? Data(contentsOf: url),
            let config = try? JSONDecoder().decode(AppConfig.self, from: data),
            !config.targets.isEmpty
        else {
            return AppConfig(targets: defaultTargets, interval: 10)
        }
        return config
    }

    func save() {
        let directoryURL = URL(fileURLWithPath: Self.configDir, isDirectory: true)
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: URL(fileURLWithPath: Self.configPath), options: .atomic)
        }
    }
}

final class DSkillerStatusApp: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    
    // Interval Slider items
    private let intervalMenuItem = NSMenuItem()
    private let intervalSlider = NSSlider()
    private let intervalLabel = NSTextField(labelWithString: "扫描间隔: 10秒")

    private let statusMenuItem = NSMenuItem(title: "状态：🟡 检查中...", action: nil, keyEquivalent: "")
    private let toggleServiceMenuItem = NSMenuItem(title: "启动监听", action: #selector(toggleService), keyEquivalent: "")
    private let launchAtLoginMenuItem = NSMenuItem(title: "开机自启动", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
    
    // Consolidated folder management menu
    private let foldersMenuItem = NSMenuItem(title: "监听目录管理", action: nil, keyEquivalent: "")
    private let foldersSubmenu = NSMenu()
    
    // Permissions status sub-menu
    private let permissionsMenuItem = NSMenuItem(title: "系统权限与依赖状态", action: nil, keyEquivalent: "")
    private let permissionsSubmenu = NSMenu()
    
    private var config = AppConfig.load()
    private var logWindowController: LogWindowController?
    private var autoCleanTimer: Timer?
    private let cleanQueue = DispatchQueue(label: "local.dsstore-cleaner.app-cleaner", qos: .utility)
    private var isCleaning = false
    private var isServiceActive = true
    
    private let skippedDirectoryNames = Set([
        ".git",
        ".hg",
        ".svn",
        ".venv",
        "venv",
        "node_modules",
        "__pycache__",
        "site-packages",
        "Library",
        "Applications",
    ])

    func start() {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        configureMenu()
        config.save()
        updateMenuState()
        if isServiceActive {
            startAutoCleaner()
        }
        FileHandle.standardError.write(Data("DSStoreCleaner status item started\n".utf8))
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        updateMenuState()
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = nil
            button.title = "DS"
            button.toolTip = "DSkiller"
            FileHandle.standardError.write(Data("status item configured\n".utf8))
        } else {
            FileHandle.standardError.write(Data("failed to create status item button\n".utf8))
        }
    }

    private func configureMenu() {
        menu.delegate = self
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(NSMenuItem.separator())

        addMenuItem("立即清理", action: #selector(cleanNow))

        foldersMenuItem.submenu = foldersSubmenu
        menu.addItem(foldersMenuItem)

        permissionsMenuItem.submenu = permissionsSubmenu
        menu.addItem(permissionsMenuItem)

        menu.addItem(NSMenuItem.separator())
        
        // Add interval slider menu item
        intervalMenuItem.view = buildIntervalSliderView()
        menu.addItem(intervalMenuItem)

        menu.addItem(NSMenuItem.separator())
        toggleServiceMenuItem.target = self
        menu.addItem(toggleServiceMenuItem)

        launchAtLoginMenuItem.target = self
        menu.addItem(launchAtLoginMenuItem)

        menu.addItem(NSMenuItem.separator())
        addMenuItem("关于 DSkiller", action: #selector(showAbout))
        addMenuItem("打开日志", action: #selector(openLogs))

        menu.addItem(NSMenuItem.separator())
        addMenuItem("退出菜单栏 App", action: #selector(quitApp), keyEquivalent: "q")

        statusItem.menu = menu
    }

    private func addMenuItem(_ title: String, action: Selector, keyEquivalent: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.target = self
        menu.addItem(item)
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateMenuState()
    }

    private func updateMenuState() {
        let running = isServiceRunning()
        statusMenuItem.title = running ? "状态：🟢 正在监听" : "状态：🔴 已暂停"
        toggleServiceMenuItem.title = running ? "暂停监听" : "启动监听"
        launchAtLoginMenuItem.state = isLaunchAtLoginEnabled() ? .on : .off
        rebuildFoldersSubmenu()
        rebuildPermissionsSubmenu()
    }

    private func rebuildFoldersSubmenu() {
        foldersSubmenu.removeAllItems()
        
        // Item 1: Add new directory
        let addItem = NSMenuItem(title: "➕ 添加新监听目录...", action: #selector(addFolder), keyEquivalent: "")
        addItem.target = self
        foldersSubmenu.addItem(addItem)
        
        foldersSubmenu.addItem(NSMenuItem.separator())
        
        // List currently watched folders
        for target in config.targets {
            let url = URL(fileURLWithPath: target)
            let folderName = url.lastPathComponent
            let home = NSHomeDirectory()
            let displayPath = target.replacingOccurrences(of: home, with: "~")

            let folderItem = NSMenuItem(title: "📁 \(folderName)", action: #selector(manageFolder(_:)), keyEquivalent: "")
            folderItem.target = self
            folderItem.representedObject = target
            folderItem.subtitle = displayPath
            foldersSubmenu.addItem(folderItem)
        }

        if config.targets.isEmpty {
            let empty = NSMenuItem(title: "无监听目录", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            foldersSubmenu.addItem(empty)
        }
    }

    @objc private func manageFolder(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? String else { return }
        let url = URL(fileURLWithPath: target)
        let folderName = url.lastPathComponent
        
        let alert = NSAlert()
        alert.messageText = "📁 管理监听目录"
        alert.informativeText = """
        目录名：\(folderName)
        绝对路径：\(target)
        
        请选择你想要执行的操作：
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "在 Finder 中打开")
        alert.addButton(withTitle: "移除监听")
        alert.addButton(withTitle: "取消")
        
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        
        if response == .alertFirstButtonReturn {
            // Open in Finder
            NSWorkspace.shared.open(url)
        } else if response == .alertSecondButtonReturn {
            // Remove monitored folder
            config.targets.removeAll { $0 == target }
            persistTargetsAndRestartIfNeeded(changed: true)
            appendAppLog("已移除监听目录: \(target)")
        }
    }

    private func hasAppFDA() -> Bool {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        let probePaths = [
            "\(home)/Library/Safari",
            "\(home)/Library/Mail",
            "\(home)/Library/HomeKit",
            "/Library/SystemMigration"
        ]
        
        for path in probePaths {
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue {
                do {
                    _ = try fm.contentsOfDirectory(atPath: path)
                    return true
                } catch {
                    continue
                }
            }
        }
        return false
    }

    private func rebuildPermissionsSubmenu() {
        permissionsSubmenu.removeAllItems()
        
        let appFDA = hasAppFDA()
        let appFDAItem = NSMenuItem(
            title: "App 磁盘访问：" + (appFDA ? "🟢 已授予" : "🔴 未授予 (点击修复)"),
            action: appFDA ? nil : #selector(showFDAGuidance),
            keyEquivalent: ""
        )
        appFDAItem.target = self
        permissionsSubmenu.addItem(appFDAItem)
        
        let serviceRunning = isServiceRunning()
        let serviceItem = NSMenuItem(
            title: "后台监听服务：" + (serviceRunning ? "🟢 运行中" : "🟡 已暂停"),
            action: nil,
            keyEquivalent: ""
        )
        permissionsSubmenu.addItem(serviceItem)
        
        permissionsSubmenu.addItem(NSMenuItem.separator())
        let helpItem = NSMenuItem(title: "如何授予完全磁盘访问权限 (FDA)...", action: #selector(showFDAGuidance), keyEquivalent: "")
        helpItem.target = self
        permissionsSubmenu.addItem(helpItem)
    }

    @objc private func addFolder() {
        let panel = NSOpenPanel()
        panel.title = "选择要监听的文件夹"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)

        guard panel.runModal() == .OK else { return }

        let newTargets = panel.urls.map { $0.path }
        var changed = false
        for target in newTargets where !config.targets.contains(target) {
            config.targets.append(target)
            changed = true
        }
        persistTargetsAndRestartIfNeeded(changed: changed)
    }

    @objc private func removeFolder(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? String else { return }
        config.targets.removeAll { $0 == target }
        persistTargetsAndRestartIfNeeded(changed: true)
    }

    private func persistTargetsAndRestartIfNeeded(changed: Bool) {
        guard changed else { return }
        config.targets.sort()
        config.save()
        if isServiceRunning() {
            startAutoCleaner()
        }
        updateMenuState()
    }

    @objc private func cleanNow() {
        guard !isCleaning else { return }
        isCleaning = true
        let targetsSnapshot = config.targets
        cleanQueue.async { [weak self] in
            guard let self else { return }
            let deletedCount = self.cleanTargets(targets: targetsSnapshot, reason: "手动清理")
            DispatchQueue.main.async {
                self.isCleaning = false
                self.appendAppLog("手动清理完成，共删除 \(deletedCount) 个 .DS_Store 文件")
                self.logWindowController?.startLiveUpdates()
                self.updateMenuState()
            }
        }
    }

    @objc private func toggleService() {
        isServiceActive = !isServiceActive
        if isServiceActive {
            startAutoCleaner()
            appendAppLog("后台监听服务已启动")
        } else {
            stopAutoCleaner()
            appendAppLog("后台监听服务已暂停")
        }
        logWindowController?.startLiveUpdates()
        updateMenuState()
    }

    @objc private func toggleLaunchAtLogin() {
        if isLaunchAtLoginEnabled() {
            disableLaunchAtLogin()
        } else {
            enableLaunchAtLogin()
        }
        updateMenuState()
    }

    @objc private func showFDAGuidance() {
        let alert = NSAlert()
        alert.messageText = "完全磁盘访问权限 (FDA) 引导"
        alert.informativeText = """
        由于 macOS 的安全隐私机制，后台清理程序在访问「桌面」或「文档」等文件夹时可能会遇到“Operation not permitted”权限错误。

        若要确保清理器正常工作，请按照以下步骤授予权限：
        1. 点击下方按钮，在打开的系统窗口中进入「完全磁盘访问权限」。
        2. 点击列表下方的「+」号。
        3. 将本应用 (DSStore Cleaner.app) 添加到列表中并启用。
        
        你可以通过本应用的「打开日志」窗口检查是否有权限报错。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "打开系统设置")
        alert.addButton(withTitle: "确定")
        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func isServiceRunning() -> Bool {
        return isServiceActive
    }

    private func isLaunchAtLoginEnabled() -> Bool {
        let uid = String(getuid())
        let result = runProcess("/bin/launchctl", ["print", "gui/\(uid)/\(AppConfig.appLaunchLabel)"])
        return result.exitCode == 0 || FileManager.default.fileExists(atPath: AppConfig.appLaunchPlist)
    }

    private func enableLaunchAtLogin() {
        let appPath = Bundle.main.bundlePath
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
          "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>\(AppConfig.appLaunchLabel)</string>
          <key>ProgramArguments</key>
          <array>
            <string>/usr/bin/open</string>
            <string>\(escapeXML(appPath))</string>
          </array>
          <key>RunAtLoad</key>
          <true/>
        </dict>
        </plist>
        """

        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: "\(NSHomeDirectory())/Library/LaunchAgents", isDirectory: true),
            withIntermediateDirectories: true
        )
        try? plist.write(toFile: AppConfig.appLaunchPlist, atomically: true, encoding: .utf8)
        _ = runProcess("/bin/launchctl", ["bootout", "gui/\(getuid())", AppConfig.appLaunchPlist])
        _ = runProcess("/bin/launchctl", ["bootstrap", "gui/\(getuid())", AppConfig.appLaunchPlist])
    }

    private func disableLaunchAtLogin() {
        _ = runProcess("/bin/launchctl", ["bootout", "gui/\(getuid())", AppConfig.appLaunchPlist])
        try? FileManager.default.removeItem(atPath: AppConfig.appLaunchPlist)
    }

    private func escapeXML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "关于 DSkiller"
        alert.informativeText = "Swift 原生的 macOS 菜单栏小工具，常驻后台实时自动清理指定目录下的 .DS_Store 垃圾文件。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "确定")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func openLogs() {
        if logWindowController == nil {
            logWindowController = LogWindowController(
                logPaths: [AppConfig.standardLogPath, AppConfig.errorLogPath]
            )
        }
        NSApp.activate(ignoringOtherApps: true)
        logWindowController?.showWindow(nil)
        logWindowController?.startLiveUpdates()
    }

    @objc private func quitApp() {
        stopAutoCleaner()
        NSApp.terminate(nil)
    }

    private func buildIntervalSliderView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 44))
        
        intervalLabel.frame = NSRect(x: 12, y: 24, width: 196, height: 16)
        intervalLabel.font = NSFont.systemFont(ofSize: 11, weight: .medium)
        intervalLabel.textColor = .secondaryLabelColor
        intervalLabel.stringValue = "扫描间隔: \(config.interval)秒"
        
        intervalSlider.frame = NSRect(x: 10, y: 4, width: 200, height: 18)
        intervalSlider.minValue = 10.0
        intervalSlider.maxValue = 60.0
        intervalSlider.doubleValue = Double(config.interval)
        intervalSlider.numberOfTickMarks = 6
        intervalSlider.allowsTickMarkValuesOnly = false
        intervalSlider.target = self
        intervalSlider.action = #selector(sliderValueChanged(_:))
        
        view.addSubview(intervalLabel)
        view.addSubview(intervalSlider)
        
        return view
    }

    @objc private func sliderValueChanged(_ sender: NSSlider) {
        let newInterval = Int(sender.doubleValue)
        intervalLabel.stringValue = "扫描间隔: \(newInterval)秒"
        
        if config.interval != newInterval {
            config.interval = newInterval
            config.save()
            
            // Re-apply interval to active fallback timer if running
            if autoCleanTimer != nil {
                startAutoCleaner()
            }
        }
    }

    private func startAutoCleaner() {
        autoCleanTimer?.invalidate()
        appendAppLog("原生后台扫描已启动，时间间隔：\(config.interval)秒")
        scheduleAppClean(reason: "应用启动")
        autoCleanTimer = Timer.scheduledTimer(withTimeInterval: Double(config.interval), repeats: true) { [weak self] _ in
            self?.scheduleAppClean(reason: "自动扫描")
        }
        if let autoCleanTimer {
            RunLoop.main.add(autoCleanTimer, forMode: .common)
        }
    }

    private func stopAutoCleaner() {
        autoCleanTimer?.invalidate()
        autoCleanTimer = nil
        appendAppLog("后台监控服务已暂停")
    }

    private func scheduleAppClean(reason: String) {
        guard !isCleaning else {
            appendAppLog("\(reason) 跳过：上一次扫描仍在运行")
            return
        }

        isCleaning = true
        let targetsSnapshot = config.targets
        cleanQueue.async { [weak self] in
            guard let self else { return }
            let deletedCount = self.cleanTargets(targets: targetsSnapshot, reason: reason)
            DispatchQueue.main.async {
                self.isCleaning = false
                if deletedCount > 0 {
                    self.appendAppLog("\(reason) 扫描完成，共删除 \(deletedCount) 个 .DS_Store 文件")
                } else {
                    self.appendAppLog("\(reason) 扫描完成，未发现垃圾文件")
                }
                self.logWindowController?.startLiveUpdates()
            }
        }
    }

    private func cleanTargets(reason: String) -> Int {
        cleanTargets(targets: config.targets, reason: reason)
    }

    private func cleanTargets(targets: [String], reason: String) -> Int {
        var deleted = 0
        let fileManager = FileManager.default

        for target in targets {
            let targetURL = URL(fileURLWithPath: target)
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: targetURL.path, isDirectory: &isDirectory) else {
                appendAppErrorLog("\(reason) 跳过不存在的目标: \(target)")
                continue
            }

            if !isDirectory.boolValue {
                if targetURL.lastPathComponent == ".DS_Store", removeDSStore(at: targetURL, reason: reason) {
                    deleted += 1
                }
                continue
            }

            guard let enumerator = fileManager.enumerator(
                at: targetURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsPackageDescendants],
                errorHandler: { [weak self] url, error in
                    self?.appendAppErrorLog("\(reason) 遍历失败: \(url.path): \(error.localizedDescription)")
                    return true
                }
            ) else {
                appendAppErrorLog("\(reason) 无法遍历目标: \(target)")
                continue
            }

            for case let fileURL as URL in enumerator {
                if skippedDirectoryNames.contains(fileURL.lastPathComponent) {
                    enumerator.skipDescendants()
                    continue
                }

                guard fileURL.lastPathComponent == ".DS_Store" else { continue }
                if removeDSStore(at: fileURL, reason: reason) {
                    deleted += 1
                }
            }
        }

        return deleted
    }

    private func removeDSStore(at url: URL, reason: String) -> Bool {
        do {
            try FileManager.default.removeItem(at: url)
            appendAppLog("\(reason) 已删除: \(url.path)")
            return true
        } catch {
            appendAppErrorLog("\(reason) 删除失败: \(url.path): \(error.localizedDescription)")
            return false
        }
    }

    private func appendAppLog(_ message: String) {
        appendLine(message, to: AppConfig.standardLogPath)
    }

    private func appendAppErrorLog(_ message: String) {
        appendLine(message, to: AppConfig.errorLogPath)
    }

    private func appendLine(_ message: String, to path: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)
        let line = "\(timestamp) \(message)\n"
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: url.path),
               let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }

    private func runProcess(_ executable: String, _ arguments: [String]) -> (exitCode: Int32, output: String, error: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return (1, "", error.localizedDescription)
        }

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()

        let output = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let error = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return (process.terminationStatus, output, error)
    }
}

final class LogWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers?.lowercased() == "w" {
            self.performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

final class LogWindowController: NSWindowController, NSWindowDelegate {
    private let logPaths: [String]
    private var textView: NSTextView!
    private var scrollView: NSScrollView!
    private var timer: Timer?
    private var lastRenderedText = ""

    init(logPaths: [String]) {
        self.logPaths = logPaths

        let window = LogWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DSkiller 日志"
        window.center()

        super.init(window: window)
        window.delegate = self
        buildContent(in: window)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func startLiveUpdates() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func windowWillClose(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    private func buildContent(in window: NSWindow) {
        let contentView = NSView()

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        let refreshButton = NSButton(title: "刷新", target: self, action: #selector(refreshButtonClicked))
        let clearButton = NSButton(title: "清空日志", target: self, action: #selector(clearLogs))
        let hintLabel = NSTextField(labelWithString: "每秒自动刷新，显示最近日志")
        hintLabel.textColor = .secondaryLabelColor

        toolbar.addArrangedSubview(refreshButton)
        toolbar.addArrangedSubview(clearButton)
        toolbar.addArrangedSubview(hintLabel)

        let scrollView = NSTextView.scrollableTextView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false

        textView = (scrollView.documentView as! NSTextView)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 10, height: 10)

        contentView.addSubview(toolbar)
        contentView.addSubview(scrollView)
        window.contentView = contentView

        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 12),
            toolbar.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -12),

            scrollView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    @objc private func refreshButtonClicked() {
        refresh(force: true)
    }

    @objc private func clearLogs() {
        for path in logPaths {
            let url = URL(fileURLWithPath: path)
            try? "".write(to: url, atomically: true, encoding: .utf8)
        }
        lastRenderedText = ""
        textView.string = ""
        refresh(force: true)
    }

    private func refresh(force: Bool = false) {
        let text = renderLogs()
        guard force || text != lastRenderedText else { return }
        lastRenderedText = text
        textView.string = text
        scrollToBottom()
    }

    private func renderLogs() -> String {
        logPaths.map { path in
            let body = tailFile(path: path, maxBytes: 120_000)
            return """
            ===== \(path) =====
            \(body.isEmpty ? "(暂无日志)" : body)
            """
        }.joined(separator: "\n\n")
    }

    private func tailFile(path: String, maxBytes: UInt64) -> String {
        let url = URL(fileURLWithPath: path)
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "(无法读取或文件不存在)"
        }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > maxBytes ? size - maxBytes : 0
        try? handle.seek(toOffset: offset)
        let data = handle.readDataToEndOfFile()
        var text = String(data: data, encoding: .utf8) ?? ""
        if offset > 0, let firstNewline = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstNewline)...])
        }
        return text.trimmingCharacters(in: .newlines)
    }

    private func scrollToBottom() {
        guard let textView = textView.enclosingScrollView?.documentView as? NSTextView else { return }
        let range = NSRange(location: textView.string.count, length: 0)
        textView.scrollRangeToVisible(range)
    }
}
