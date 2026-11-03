import AppKit

// MARK: - Configuration (compatible with original Go2Shell defaults)
private let bundleID = "com.zipzapmac.Go2Shell"

private struct Config {
    let terminalID: String
    let commandTemplate: String
    let useWindow: Bool

    static func load() -> Config {
        let defaults = UserDefaults(suiteName: bundleID) ?? .standard
        let terminalID = defaults.string(forKey: "Terminal Identifier") ?? "com.apple.Terminal"
        let commandTemplate = defaults.string(forKey: "Terminal Command") ?? "cd %PATH%; clear; pwd"
        let useWindow = defaults.object(forKey: "Use Window") as? Bool ?? true
        return Config(terminalID: terminalID, commandTemplate: commandTemplate, useWindow: useWindow)
    }
}

// MARK: - Helpers

/// Quote a path for safe use inside a single-quoted shell string.
private func shellQuote(_ path: String) -> String {
    "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
}

/// Run an AppleScript source string, returning the result string (or nil on failure).
@discardableResult
private func runAppleScript(_ source: String) -> String? {
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source) else { return nil }
    let descriptor = script.executeAndReturnError(&error)
    if error != nil { return nil }
    return descriptor.stringValue
}

/// Get the POSIX path of the frontmost Finder window's target.
private func frontFinderWindowPath() -> String? {
    let script = """
    tell application "Finder"
        if (count of windows) > 0 then
            set winTarget to target of front window
            if (class of winTarget) is folder then
                return POSIX path of (winTarget as alias)
            else if (class of winTarget) is disk then
                return POSIX path of (winTarget as alias)
            end if
        end if
        return ""
    end tell
    """
    guard let result = runAppleScript(script), !result.isEmpty else { return nil }
    return result
}

/// Fallback: get the insertion location / desktop path.
private func fallbackPath() -> String {
    let script = """
    tell application "Finder"
        try
            return POSIX path of (insertion location as alias)
        on error
            return POSIX path of (path to desktop folder)
        end try
    end tell
    """
    return runAppleScript(script) ?? NSHomeDirectory()
}

// MARK: - Terminal openers

private func openTerminal(_ config: Config, path: String) {
    let command = config.commandTemplate.replacingOccurrences(of: "%PATH%", with: shellQuote(path))

    switch config.terminalID {
    case "com.apple.Terminal":
        openAppleTerminal(command: command, inNewWindow: config.useWindow)
    case "com.googlecode.iterm2":
        openiTerm2(command: command, inNewWindow: config.useWindow)
    case "com.googlecode.iterm":
        openiTerm(command: command, inNewWindow: config.useWindow)
    case "xterm":
        openXterm(path: path)
    default:
        // Try as a generic bundle identifier; fall back to Terminal
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: config.terminalID) {
            _ = url
            openAppleTerminal(command: command, inNewWindow: config.useWindow)
        } else {
            openAppleTerminal(command: command, inNewWindow: config.useWindow)
        }
    }
}

private func openAppleTerminal(command: String, inNewWindow: Bool) {
    let script: String
    if inNewWindow {
        script = """
        tell application "Terminal"
            activate
            do script "\(escapedAppleScriptString(command))"
        end tell
        """
    } else {
        script = """
        tell application "Terminal"
            activate
            if (count of windows) = 0 then
                do script "\(escapedAppleScriptString(command))"
            else
                do script "\(escapedAppleScriptString(command))" in front window
            end if
        end tell
        """
    }
    runAppleScript(script)
}

private func openiTerm2(command: String, inNewWindow: Bool) {
    let script = """
    tell application "iTerm"
        activate
        if \(inNewWindow ? "true" : "false") then
            create window with default profile
            tell current session of current window
                write text "\(escapedAppleScriptString(command))"
            end tell
        else
            if (count of windows) = 0 then
                create window with default profile
            end if
            tell current session of current window
                write text "\(escapedAppleScriptString(command))"
            end tell
        end if
    end tell
    """
    runAppleScript(script)
}

private func openiTerm(command: String, inNewWindow: Bool) {
    let script = """
    tell application "iTerm"
        activate
        if \(inNewWindow ? "true" : "false") then
            make new terminal
        end if
        tell the current terminal
            activate current session
            tell the last session
                write text "\(escapedAppleScriptString(command))"
            end tell
        end tell
    end tell
    """
    runAppleScript(script)
}

private func openXterm(path: String) {
    let task = Process()
    task.launchPath = "/opt/X11/bin/xterm"
    if !FileManager.default.fileExists(atPath: task.launchPath!) {
        task.launchPath = "/usr/X11/bin/xterm"
    }
    if FileManager.default.fileExists(atPath: task.launchPath!) {
        task.arguments = ["-e", "cd \(shellQuote(path)) && exec \"$SHELL\""]
        try? task.run()
    } else {
        // X11 not installed; fall back to Terminal
        let cmd = "cd \(shellQuote(path)); clear; pwd"
        openAppleTerminal(command: cmd, inNewWindow: true)
    }
}

/// Escape a string for safe embedding inside a double-quoted AppleScript string literal.
private func escapedAppleScriptString(_ s: String) -> String {
    var out = ""
    for ch in s {
        switch ch {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default: out.append(ch)
        }
    }
    return out
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let config = Config.load()
        let path = frontFinderWindowPath() ?? fallbackPath()
        openTerminal(config, path: path)
        NSApp.terminate(nil)
    }
}

// MARK: - Entry point

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
