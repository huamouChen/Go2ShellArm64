import AppKit

private let bundleID = "com.zipzapmac.Go2Shell"

// MARK: - Terminal descriptors

private struct TerminalDescriptor {
    let name: String
    let identifier: String
}

private let knownTerminals: [TerminalDescriptor] = [
    TerminalDescriptor(name: "Terminal", identifier: "com.apple.Terminal"),
    TerminalDescriptor(name: "iTerm2", identifier: "com.googlecode.iterm2"),
    TerminalDescriptor(name: "iTerm", identifier: "com.googlecode.iterm"),
    TerminalDescriptor(name: "xterm", identifier: "xterm"),
]

private func installedTerminals() -> [TerminalDescriptor] {
    knownTerminals.filter { td in
        if td.identifier == "xterm" {
            return FileManager.default.fileExists(atPath: "/opt/X11/bin/xterm")
                || FileManager.default.fileExists(atPath: "/usr/X11/bin/xterm")
        }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: td.identifier) != nil
    }
}

// MARK: - Config persistence

private struct Config {
    var terminalID: String
    var commandTemplate: String
    var useWindow: Bool

    static func load() -> Config {
        let defaults = UserDefaults(suiteName: bundleID) ?? .standard
        Config.migrate(defaults)
        return Config(
            terminalID: defaults.string(forKey: "Terminal Identifier") ?? "com.apple.Terminal",
            commandTemplate: defaults.string(forKey: "Terminal Command") ?? "cd %PATH%; clear; pwd",
            useWindow: defaults.object(forKey: "Use Window") as? Bool ?? true
        )
    }

    static func migrate(_ defaults: UserDefaults) {
        // Ensure keys exist; if the terminal is no longer installed, keep it anyway.
        if defaults.string(forKey: "Terminal Identifier") == nil {
            defaults.set("com.apple.Terminal", forKey: "Terminal Identifier")
        }
        if defaults.string(forKey: "Terminal Command") == nil {
            defaults.set("cd %PATH%; clear; pwd", forKey: "Terminal Command")
        }
        if defaults.object(forKey: "Use Window") == nil {
            defaults.set(true, forKey: "Use Window")
        }
    }

    func save() {
        let defaults = UserDefaults(suiteName: bundleID) ?? .standard
        defaults.set(terminalID, forKey: "Terminal Identifier")
        defaults.set(commandTemplate, forKey: "Terminal Command")
        defaults.set(useWindow, forKey: "Use Window")
    }
}

// MARK: - Finder toolbar installation

private func helperAppURL() -> URL? {
    // Helper is embedded at <MainApp>/Contents/MacOS/Go2ShellHelper.app
    let bundle = Bundle.main
    let helperPath = bundle.bundlePath + "/Contents/MacOS/Go2ShellHelper.app"
    if FileManager.default.fileExists(atPath: helperPath) {
        return URL(fileURLWithPath: helperPath)
    }
    // Fallback: look alongside main app
    let alongside = (bundle.bundlePath as NSString).deletingLastPathComponent + "/Go2ShellHelper.app"
    if FileManager.default.fileExists(atPath: alongside) {
        return URL(fileURLWithPath: alongside)
    }
    return nil
}

/// Modify com.apple.finder FXTaskbarApplications and relaunch Finder (matches original behavior).
private func addToFinderToolbar(helperURL: URL) {
    let finderPlist = (NSHomeDirectory() as NSString).appendingPathComponent(
        "Library/Preferences/com.apple.finder.plist")
    var dict = (NSDictionary(contentsOfFile: finderPlist) as? [String: Any]) ?? [:]
    var items = dict["FXTaskbarApplications"] as? [[String: Any]] ?? []
    let path = helperURL.path
    items.removeAll { ($0["path"] as? String) == path }
    items.append(["path": path, "name": "Go2Shell"])
    dict["FXTaskbarApplications"] = items
    (dict as NSDictionary).write(toFile: finderPlist, atomically: true)
    relaunchFinder()
}

private func removeFromFinderToolbar(helperURL: URL) {
    let finderPlist = (NSHomeDirectory() as NSString).appendingPathComponent(
        "Library/Preferences/com.apple.finder.plist")
    var dict = (NSDictionary(contentsOfFile: finderPlist) as? [String: Any]) ?? [:]
    var items = dict["FXTaskbarApplications"] as? [[String: Any]] ?? []
    let path = helperURL.path
    items.removeAll { ($0["path"] as? String) == path }
    dict["FXTaskbarApplications"] = items
    (dict as NSDictionary).write(toFile: finderPlist, atomically: true)
    relaunchFinder()
}

private func relaunchFinder() {
    let task = Process()
    task.launchPath = "/usr/bin/killall"
    task.arguments = ["Finder"]
    try? task.run()
}

// MARK: - Main app delegate / UI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var terminalPopup: NSPopUpButton!
    private var commandField: NSTextField!
    private var useWindowCheckbox: NSButton!
    private var statusLabel: NSTextField!

    private var config = Config.load()

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildWindow()
        loadConfigToUI()
    }

    private func buildWindow() {
        let windowRect = NSRect(x: 0, y: 0, width: 480, height: 280)
        window = NSWindow(
            contentRect: windowRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Go2Shell"
        window.center()
        window.isReleasedWhenClosed = false

        let content = window.contentView!

        // Terminal label + popup
        let termLabel = NSTextField(labelWithString: "Open with:")
        termLabel.frame = NSRect(x: 24, y: 220, width: 120, height: 22)
        content.addSubview(termLabel)

        terminalPopup = NSPopUpButton(frame: NSRect(x: 150, y: 216, width: 300, height: 28))
        terminalPopup.target = self
        terminalPopup.action = #selector(terminalChanged(_:))
        content.addSubview(terminalPopup)

        // Command label + field
        let cmdLabel = NSTextField(labelWithString: "Command (%PATH% = folder):")
        cmdLabel.frame = NSRect(x: 24, y: 178, width: 300, height: 22)
        content.addSubview(cmdLabel)

        commandField = NSTextField(frame: NSRect(x: 24, y: 148, width: 432, height: 28))
        commandField.placeholderString = "cd %PATH%; clear; pwd"
        content.addSubview(commandField)

        // Use Window checkbox
        useWindowCheckbox = NSButton(checkboxWithTitle: "Open in a new window",
                                      target: self, action: #selector(toggleUseWindow(_:)))
        useWindowCheckbox.frame = NSRect(x: 24, y: 118, width: 300, height: 22)
        content.addSubview(useWindowCheckbox)

        // Buttons row
        let testButton = NSButton(title: "Test", target: self, action: #selector(testClicked(_:)))
        testButton.frame = NSRect(x: 24, y: 70, width: 100, height: 32)
        testButton.bezelStyle = .rounded
        content.addSubview(testButton)

        let installButton = NSButton(title: "Install to Finder Toolbar",
                                       target: self, action: #selector(installClicked(_:)))
        installButton.frame = NSRect(x: 136, y: 70, width: 200, height: 32)
        installButton.bezelStyle = .rounded
        content.addSubview(installButton)

        let saveButton = NSButton(title: "Save Settings", target: self, action: #selector(saveClicked(_:)))
        saveButton.frame = NSRect(x: 356, y: 70, width: 100, height: 32)
        saveButton.bezelStyle = .rounded
        content.addSubview(saveButton)

        // Status label
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: 24, y: 30, width: 432, height: 22)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        content.addSubview(statusLabel)

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func loadConfigToUI() {
        let terminals = installedTerminals()
        terminalPopup.removeAllItems()
        for t in terminals {
            terminalPopup.addItem(withTitle: t.name)
            terminalPopup.lastItem?.representedObject = t.identifier
        }
        // Also include currently selected even if not installed
        if let selected = terminalPopup.item(withTitle: "") {
            _ = selected
        }
        let currentID = config.terminalID
        if let item = terminalPopup.itemArray.first(where: { ($0.representedObject as? String) == currentID }) {
            terminalPopup.select(item)
        } else if currentID.isEmpty == false {
            terminalPopup.addItem(withTitle: currentID)
            terminalPopup.lastItem?.representedObject = currentID
            terminalPopup.selectItem(at: terminalPopup.numberOfItems - 1)
        }

        commandField.stringValue = config.commandTemplate
        useWindowCheckbox.state = config.useWindow ? .on : .off
    }

    @objc private func terminalChanged(_ sender: NSPopUpButton) {
        if let id = sender.selectedItem?.representedObject as? String {
            config.terminalID = id
        }
    }

    @objc private func toggleUseWindow(_ sender: NSButton) {
        config.useWindow = (sender.state == .on)
    }

    @objc private func saveClicked(_ sender: Any) {
        config.commandTemplate = commandField.stringValue
        config.save()
        setStatus("Settings saved.")
    }

    @objc private func testClicked(_ sender: Any) {
        config.commandTemplate = commandField.stringValue
        config.save()
        setStatus("Opening terminal at current Finder folder…")
        // Launch the helper directly
        if let helper = helperAppURL() {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: helper, configuration: config) { _, error in
                if let error = error {
                    self.setStatus("Failed to launch helper: \(error.localizedDescription)")
                }
            }
        } else {
            setStatus("Helper app not found.")
        }
    }

    @objc private func installClicked(_ sender: Any) {
        guard let helper = helperAppURL() else {
            setStatus("Go2ShellHelper.app not found in the bundle.")
            return
        }
        addToFinderToolbar(helperURL: helper)
        setStatus("Added to Finder toolbar (Finder restarted). If the icon is missing, hold ⌘ and drag Go2ShellHelper.app onto the Finder toolbar manually.")
    }

    private func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
