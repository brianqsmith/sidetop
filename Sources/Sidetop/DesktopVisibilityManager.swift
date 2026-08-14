import Foundation

final class DesktopVisibilityManager {
    private let defaults = UserDefaults.standard
    private let storedValueKey = "desktopIconsWereVisible"
    private let explicitValueKey = "desktopIconsSettingWasExplicit"
    private let activeKey = "desktopIconsHiddenBySidetop"
    private let finderDomain = "com.apple.finder" as CFString
    private let createDesktopKey = "CreateDesktop" as CFString

    @discardableResult
    func recoverInterruptedSessionIfNeeded() -> Bool {
        guard defaults.bool(forKey: activeKey) else { return false }
        restoreDesktopIcons()
        return true
    }

    func hideDesktopIcons() {
        // The preference is already applied and owned by this Sidetop
        // session. Reapplying it would unnecessarily restart Finder and make
        // all of the user's Finder windows disappear and reopen.
        if defaults.bool(forKey: activeKey) { return }
        let current = readFinderSetting()
        defaults.set(current.value, forKey: storedValueKey)
        defaults.set(current.wasExplicit, forKey: explicitValueKey)
        defaults.set(true, forKey: activeKey)
        if current.value { setFinderSetting(false) }
    }

    func restoreDesktopIcons() {
        guard defaults.bool(forKey: activeKey) else { return }
        let previous = defaults.object(forKey: storedValueKey) as? Bool ?? true
        if defaults.bool(forKey: explicitValueKey) {
            setFinderSetting(previous)
        } else {
            clearFinderSetting()
            restartFinder()
        }
        defaults.set(false, forKey: activeKey)
    }

    func forceDesktopIconsVisible() {
        clearFinderSetting()
        defaults.set(false, forKey: activeKey)
        restartFinder()
    }

    private func readFinderSetting() -> (value: Bool, wasExplicit: Bool) {
        if let value = CFPreferencesCopyValue(createDesktopKey,
                                              finderDomain,
                                              kCFPreferencesCurrentUser,
                                              kCFPreferencesAnyHost) as? Bool {
            return (value, true)
        }
        let result = run("/usr/bin/defaults", ["read", "com.apple.finder", "CreateDesktop"])
        guard result.status == 0 else { return (true, false) }
        let output = result.output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return (!output.hasPrefix("0") && !output.hasPrefix("false"), true)
    }

    private func setFinderSetting(_ visible: Bool) {
        CFPreferencesSetValue(createDesktopKey,
                              visible ? kCFBooleanTrue : kCFBooleanFalse,
                              finderDomain,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost)
        CFPreferencesSynchronize(finderDomain,
                                 kCFPreferencesCurrentUser,
                                 kCFPreferencesAnyHost)
        // Keep the command-line path as a compatibility fallback for macOS
        // versions that do not immediately persist cross-domain preferences.
        _ = run("/usr/bin/defaults", ["write", "com.apple.finder", "CreateDesktop", "-bool", visible ? "true" : "false"])
        restartFinder()
    }

    private func restartFinder() {
        _ = run("/usr/bin/killall", ["Finder"])
    }

    private func clearFinderSetting() {
        CFPreferencesSetValue(createDesktopKey,
                              nil,
                              finderDomain,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost)
        CFPreferencesSynchronize(finderDomain,
                                 kCFPreferencesCurrentUser,
                                 kCFPreferencesAnyHost)
        _ = run("/usr/bin/defaults", ["delete", "com.apple.finder", "CreateDesktop"])
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8) ?? "")
        } catch {
            return (-1, "")
        }
    }
}
