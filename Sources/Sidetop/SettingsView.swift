import ServiceManagement
import SwiftUI

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "launchAtLogin") }
    }
    @Published var errorMessage: String?

    private init() {
        if UserDefaults.standard.object(forKey: "launchAtLogin") == nil {
            UserDefaults.standard.set(true, forKey: "launchAtLogin")
        }
        enabled = UserDefaults.standard.bool(forKey: "launchAtLogin")
    }

    func applyPreferredState() {
        do {
            if enabled, SMAppService.mainApp.status == .notRegistered { try SMAppService.mainApp.register() }
            if !enabled, SMAppService.mainApp.status != .notRegistered { try SMAppService.mainApp.unregister() }
            errorMessage = nil
        } catch {
            errorMessage = "Launch at login could not be updated. Move Sidetop to Applications and try again."
        }
    }
}

struct SettingsView: View {
    @ObservedObject private var login = LaunchAtLoginManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(systemName: "sidebar.right").font(.system(size: 28)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sidetop").font(.title2.bold())
                    Text("Your Desktop, tucked neatly to the side.").foregroundStyle(.secondary)
                }
            }
            Divider()
            Toggle("Launch Sidetop automatically at login", isOn: $login.enabled)
                .onChange(of: login.enabled) { _ in login.applyPreferredState() }
            Label("Touch the right edge for one second to open Sidetop.", systemImage: "cursorarrow.motionlines")
                .font(.callout).foregroundStyle(.secondary)
            if let error = login.errorMessage {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(24)
        .frame(width: 430, height: 260)
    }
}
