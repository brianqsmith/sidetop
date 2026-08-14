import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()
    @Published var enabled: Bool {
        didSet { UserDefaults.standard.set(enabled, forKey: "launchAtLogin") }
    }
    @Published var errorMessage: String?

    private init() {
        if UserDefaults.standard.object(forKey: "launchAtLogin") == nil {
            UserDefaults.standard.set(false, forKey: "launchAtLogin")
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
    @ObservedObject var model: DesktopModel
    let setDesktopIconsHidden: (Bool) -> Void
    @ObservedObject private var login = LaunchAtLoginManager.shared
    @AppStorage("hideDesktopIcons") private var hideDesktopIcons = false
    @AppStorage("closeWindowMode") private var closeWindowMode = "auto"
    @AppStorage("sidetopTheme") private var theme = "light"
    @AppStorage("menuIconMode") private var menuIconMode = "always"
    @AppStorage("animationSpeed") private var animationSpeed = "slow"
    @ObservedObject private var categoryOrder = CategoryOrderManager.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 17) {
                    verticalSetting("Window opening speed:") {
                        Picker("", selection: $animationSpeed) {
                            Text("Slow").tag("slow")
                            Text("Fast").tag("fast")
                            Text("Instant").tag("instant")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }

                    verticalSetting("Window closing method:") {
                        Picker("", selection: $closeWindowMode) {
                            Text("Focus").tag("focus")
                            Text("Auto").tag("auto")
                            Text("Button").tag("button")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 190)
                    }

                    verticalSetting("Menu icon visibility:") {
                        Picker("", selection: $menuIconMode) {
                            Text("Always visible").tag("always")
                            Text("Remove on quit").tag("remove")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }

                    verticalSetting("Theme:") {
                        Picker("", selection: $theme) {
                            Text("Light").tag("light")
                            Text("Blue").tag("dark")
                            Text("Charcoal").tag("charcoal")
                            Text("OLED").tag("oled")
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 260)
                    }

                    HStack {
                        Toggle("Launch at login", isOn: $login.enabled)
                            .fixedSize()
                            .onChange(of: login.enabled) { _ in login.applyPreferredState() }
                        Spacer(minLength: 8)
                        Toggle("Hide icons", isOn: hideIconsBinding)
                            .fixedSize()
                    }

                    verticalSetting("Display Folder:") {
                        Button(action: chooseDisplayFolder) {
                            HStack(spacing: 7) {
                                Image(systemName: "folder")
                                Text(model.desktopURL.lastPathComponent)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Text("Choose…")
                                    .foregroundStyle(.secondary)
                            }
                            .frame(width: 260)
                        }
                    }

                    Divider()

                    Text("Arrange categories:")

                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(categoryOrder.order) { group in
                            HStack(spacing: 10) {
                                Image(systemName: "square.grid.3x3")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 18)
                                    .onDrag { NSItemProvider(object: group.rawValue as NSString) }
                                Text(group.title)
                                    .font(.system(size: 13))
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .frame(height: 31)
                            .onDrop(of: [UTType.text.identifier],
                                    delegate: CategoryDropDelegate(target: group, manager: categoryOrder))
                        }
                    }

                    if let error = login.errorMessage {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }

            Divider().opacity(0.55)

            VStack(alignment: .leading, spacing: 12) {
                Button { NSWorkspace.shared.open(model.desktopURL) } label: {
                    Label("Open Display Folder in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button(role: .destructive) { (NSApp.delegate as? AppDelegate)?.quitSidetop() } label: {
                    Label("Quit Sidetop", systemImage: "power")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.borderless)
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
    }

    private func verticalSetting<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
            content()
        }
    }

    private func settingRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(title).font(.system(size: 13, weight: .medium))
            Spacer()
            content()
        }
    }

    private var hideIconsBinding: Binding<Bool> {
        Binding(
            get: { hideDesktopIcons },
            set: { hidden in
                hideDesktopIcons = hidden
                setDesktopIconsHidden(hidden)
            }
        )
    }

    private func chooseDisplayFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose a Folder to Display"
        panel.prompt = "Choose"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.desktopURL
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        UserDefaults.standard.set(folder.path, forKey: "displayFolderPath")
        model.setDisplayFolder(folder)
    }
}

private struct CategoryDropDelegate: DropDelegate {
    let target: DesktopGroup
    let manager: CategoryOrderManager

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [UTType.text.identifier]).first else { return }
        provider.loadObject(ofClass: NSString.self) { value, _ in
            guard let rawValue = value as? String,
                  let source = DesktopGroup(rawValue: rawValue) else { return }
            Task { @MainActor in
                withAnimation(.easeInOut(duration: 0.16)) {
                    manager.move(source, before: target)
                }
            }
        }
    }

    func performDrop(info: DropInfo) -> Bool { true }
}
