import SwiftUI
import UniformTypeIdentifiers

struct SidetopView: View {
    @ObservedObject var model: DesktopModel
    let close: () -> Void
    let setDesktopIconsHidden: (Bool) -> Void
    @State private var showingSettings = false
    @State private var iconCategory: DesktopGroup?
    @State private var iconFolderPath: [URL] = []
    @State private var pendingFolderOpen: DispatchWorkItem?
    @AppStorage("sidetopTheme") private var theme = "light"
    @AppStorage("itemSortMode") private var sortMode = ItemSortMode.name.rawValue
    @AppStorage("browserViewMode") private var browserViewMode = BrowserViewMode.list.rawValue
    @ObservedObject private var categoryOrder = CategoryOrderManager.shared

    private var usesDarkAppearance: Bool { theme != "light" }
    private var panelBackground: Color {
        switch theme {
        case "dark":
            // Keep the original dark theme colors under its new Blue name.
            return Color(red: 0.055, green: 0.31, blue: 0.46).opacity(0.96)
        case "charcoal":
            return Color(red: 44.0 / 255.0, green: 44.0 / 255.0, blue: 44.0 / 255.0)
        case "oled":
            return Color.black
        default:
            return Color(nsColor: .windowBackgroundColor).opacity(0.97)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().opacity(0.28)
            if showingSettings {
                SettingsView(model: model, setDesktopIconsHidden: setDesktopIconsHidden)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
            } else if browserViewMode == BrowserViewMode.icon.rawValue {
                iconBrowser
                    .transition(.opacity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 13) {
                        ForEach(categoryOrder.order) { group in
                            groupSection(group)
                        }
                        if model.groups.values.allSatisfy(\.isEmpty) { emptyState }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 9)
                }
                .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil, perform: model.importProviders)
                .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }
        .background(panelBackground)
        .clipShape(RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 27, style: .continuous)
            .stroke(usesDarkAppearance ? Color.clear : Color.primary.opacity(0.10),
                    lineWidth: usesDarkAppearance ? 0 : 0.5))
        .padding(6)
        .environment(\.colorScheme, usesDarkAppearance ? .dark : .light)
        .onAppear { updateSelectionScope() }
    }

    private var titleBar: some View {
        HStack {
            Button(action: close) {
                Circle()
                    .fill(Color(red: 1, green: 0.28, blue: 0.34))
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.black.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Hide Sidetop")

            if browserViewMode == BrowserViewMode.icon.rawValue, iconCategory != nil {
                Button(action: navigateBack) {
                    Image(systemName: "chevron.backward.2")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 38, height: 38)
                        .background(toolbarSurface(isActive: false), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Back")
            }

            Spacer()

            Button(action: changeView) {
                Image(systemName: browserViewMode == BrowserViewMode.icon.rawValue
                      ? "list.bullet" : "square.grid.2x2")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .background(toolbarSurface(isActive: false), in: Circle())
            }
            .buttonStyle(.plain)
            .help(browserViewMode == BrowserViewMode.icon.rawValue ? "List View" : "Icon View")

            Menu {
                ForEach(ItemSortMode.allCases) { mode in
                    Button {
                        sortMode = mode.rawValue
                    } label: {
                        if sortMode == mode.rawValue {
                            Label(mode.title, systemImage: "checkmark")
                        } else {
                            Text(mode.title)
                        }
                    }
                }
            } label: {
                ZStack {
                    Circle().fill(toolbarSurface(isActive: false))
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 38, height: 38)
                .contentShape(Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 38)
            .help("Sort Items")

            Button {
                withAnimation(.easeInOut(duration: 0.20)) { showingSettings.toggle() }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 38)
                    .background(toolbarSurface(isActive: showingSettings), in: Circle())
            }
            .buttonStyle(.plain)
            .frame(width: 38)
            .help(showingSettings ? "Close Settings" : "Settings")
        }
        .padding(.leading, 20)
        .padding(.trailing, 14)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var iconBrowser: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if let iconCategory {
                    let items = currentIconItems(for: iconCategory)
                    if items.isEmpty {
                        emptyState
                    } else {
                        LazyVGrid(columns: iconGridColumns, spacing: 8) {
                            ForEach(items) { item in iconItem(item) }
                        }
                        .padding(8)
                    }
                } else {
                    LazyVGrid(columns: iconGridColumns, spacing: 8) {
                        ForEach(nonemptyGroups) { group in categoryIcon(group) }
                    }
                    .padding(8)
                }
            }
            .onChange(of: model.selectedURL) { selectedURL in
                guard iconCategory != nil, let selectedURL else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(selectedURL, anchor: .center)
                }
            }
        }
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil, perform: model.importProviders)
    }

    private var iconGridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 108, maximum: 108), spacing: 6, alignment: .top)]
    }

    private var nonemptyGroups: [DesktopGroup] {
        categoryOrder.order.filter { !(model.groups[$0] ?? []).isEmpty }
    }

    private func categoryIcon(_ group: DesktopGroup) -> some View {
        Button {
            iconCategory = group
            iconFolderPath = []
            updateSelectionScope()
        } label: {
            VStack(spacing: 2) {
                categoryImage(group)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                Text(group.title)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
    }

    private func iconItem(_ item: DesktopItem) -> some View {
        ZStack {
            VStack(spacing: 3) {
                FileThumbnailView(url: item.url, size: 100)
                Text(item.name)
                    .font(.system(size: 13))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.middle)
            }
            .padding(4)
            .frame(width: 108, height: 126)
            .background(iconItemBackground(for: item), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .allowsHitTesting(false)

            DraggableFileSurface(url: item.url,
                                 dragURLs: { model.dragURLs(for: item.url) }) { clickCount, modifiers in
                model.select(item.url, extendingRange: modifiers.contains(.shift))
                if item.isDirectory {
                    handleIconFolderClick(item.url, clickCount: clickCount)
                } else if clickCount >= 2 {
                    model.open(item.url)
                }
            }
        }
        .frame(width: 108, height: 126)
        .id(item.url)
        .contextMenu { itemContextMenu(item) }
    }

    private func handleIconFolderClick(_ url: URL, clickCount: Int) {
        if clickCount >= 2 {
            pendingFolderOpen?.cancel()
            pendingFolderOpen = nil
            model.open(url)
            return
        }
        pendingFolderOpen?.cancel()
        let workItem = DispatchWorkItem {
            iconFolderPath.append(url)
            updateSelectionScope()
        }
        pendingFolderOpen = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: workItem)
    }

    @ViewBuilder private func itemContextMenu(_ item: DesktopItem) -> some View {
        Button("Open") {
            if item.isDirectory, browserViewMode == BrowserViewMode.icon.rawValue {
                iconFolderPath.append(item.url)
                updateSelectionScope()
            } else {
                model.open(item.url)
            }
        }
        Menu("Open With") {
            ForEach(model.openWithApplications(for: item.url)) { application in
                Button(application.name) { model.open(item.url, with: application.url) }
            }
        }
        Button("Show in Finder") { model.reveal(item.url) }
        Divider()
        Button("Rename…") { model.rename(item.url) }
        Button("Duplicate") { model.duplicate(item.url) }
        Button("Copy") { model.copy(item.url) }
        Divider()
        Button("Move to Trash", role: .destructive) { model.delete(item.url) }
    }

    private func categoryImage(_ group: DesktopGroup) -> Image {
        let url = Bundle.main.resourceURL?
            .appendingPathComponent("CategoryIcons", isDirectory: true)
            .appendingPathComponent("\(group.iconAssetName).png")
        if let url, let image = NSImage(contentsOf: url) { return Image(nsImage: image) }
        return Image(systemName: "folder.fill")
    }

    private func currentIconItems(for group: DesktopGroup) -> [DesktopItem] {
        if let folder = iconFolderPath.last { return model.items(in: folder) }
        return model.sorted(model.groups[group] ?? [])
    }

    private func navigateBack() {
        if !iconFolderPath.isEmpty { iconFolderPath.removeLast() }
        else { iconCategory = nil }
        updateSelectionScope()
    }

    private func changeView() {
        browserViewMode = browserViewMode == BrowserViewMode.icon.rawValue
            ? BrowserViewMode.list.rawValue : BrowserViewMode.icon.rawValue
        iconCategory = nil
        iconFolderPath = []
        showingSettings = false
        updateSelectionScope()
    }

    private func updateSelectionScope() {
        if browserViewMode == BrowserViewMode.icon.rawValue, let group = iconCategory {
            model.setSelectionScope(currentIconItems(for: group))
        } else {
            model.setSelectionScope(nil)
        }
    }

    @ViewBuilder private func groupSection(_ group: DesktopGroup) -> some View {
        if let unsortedItems = model.groups[group], !unsortedItems.isEmpty {
            let items = model.sorted(unsortedItems)
            VStack(alignment: .leading, spacing: 1) {
                Button {
                    if model.expandedGroups.contains(group) { model.expandedGroups.remove(group) }
                    else { model.expandedGroups.insert(group) }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: model.expandedGroups.contains(group) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 11)
                        Text(group.title)
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                    }
                    .foregroundStyle(Color.secondary)
                    .padding(.horizontal, 7)
                    .frame(height: 23)
                }
                .buttonStyle(.plain)

                if model.expandedGroups.contains(group) {
                    ForEach(items) { item in
                        itemTree(item, depth: 0)
                    }
                }
            }
        }
    }

    private func itemTree(_ item: DesktopItem, depth: Int) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 1) {
                itemRow(item, depth: depth)
                if item.isDirectory, model.isFolderExpanded(item.url) {
                    ForEach(model.children(of: item.url)) { child in
                        itemTree(child, depth: depth + 1)
                    }
                }
            }
        )
    }

    private func itemRow(_ item: DesktopItem, depth: Int) -> some View {
        ZStack {
            HStack(spacing: 6) {
                if item.isDirectory {
                    Image(systemName: model.isFolderExpanded(item.url) ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 9)
                } else {
                    Color.clear.frame(width: 9)
                }
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 19, height: 19)
                Text(item.name)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 2)
            }
            .allowsHitTesting(false)

            DraggableFileSurface(url: item.url,
                                 dragURLs: { model.dragURLs(for: item.url) }) { clickCount, modifiers in
                model.select(item.url, extendingRange: modifiers.contains(.shift))
                if clickCount >= 2 {
                    model.open(item.url)
                } else if item.isDirectory, !modifiers.contains(.shift) {
                    model.toggleFolder(item.url)
                }
            }
        }
        .padding(.leading, 5 + CGFloat(depth * 15))
        .padding(.trailing, 6)
        .frame(height: 27)
        .background(rowBackground(for: item), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .contextMenu { itemContextMenu(item) }
    }

    private func rowBackground(for item: DesktopItem) -> Color {
        if model.isSelected(item.url) {
            return usesDarkAppearance ? Color(red: 0.02, green: 0.48, blue: 1.0) : Color.accentColor.opacity(0.22)
        }
        if theme == "charcoal" {
            return Color(red: 65.0 / 255.0, green: 65.0 / 255.0, blue: 65.0 / 255.0)
        }
        return usesDarkAppearance ? Color.white.opacity(0.045) : Color.primary.opacity(0.045)
    }

    private func iconItemBackground(for item: DesktopItem) -> Color {
        guard model.isSelected(item.url) else { return .clear }
        return usesDarkAppearance
            ? Color(red: 0.02, green: 0.48, blue: 1.0)
            : Color.accentColor.opacity(0.22)
    }

    private func toolbarSurface(isActive: Bool) -> Color {
        if theme == "charcoal" {
            return Color(red: 65.0 / 255.0, green: 65.0 / 255.0, blue: 65.0 / 255.0)
        }
        return usesDarkAppearance ? Color.blue.opacity(isActive ? 0.75 : 0.35)
                                  : Color.primary.opacity(isActive ? 0.14 : 0.055)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "desktopcomputer").font(.system(size: 30)).foregroundStyle(.tertiary)
            Text("This folder is empty").font(.headline)
            Text("Drag files here to add them.").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}
