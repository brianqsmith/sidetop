import SwiftUI
import UniformTypeIdentifiers

struct SidetopView: View {
    @ObservedObject var model: DesktopModel
    let close: () -> Void
    let settings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            Divider().opacity(0.45)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(DesktopGroup.allCases) { group in
                        groupSection(group)
                    }
                    if model.groups.values.allSatisfy(\.isEmpty) { emptyState }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: nil, perform: model.importProviders)
        }
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).stroke(.white.opacity(0.32), lineWidth: 0.7))
        .padding(8)
    }

    private var titleBar: some View {
        HStack {
            Button(action: close) {
                Circle().fill(Color(red: 1, green: 0.28, blue: 0.34)).frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.black.opacity(0.12), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Hide Sidetop")

            Spacer()
            Text("Desktop")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()

            Menu {
                Button("Paste") { model.paste() }
                Button("Open Desktop in Finder") { NSWorkspace.shared.open(model.desktopURL) }
                Divider()
                Button("Settings…", action: settings)
                Button("Quit Sidetop") { NSApp.terminate(nil) }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 42, height: 42)
                    .background(.gray.opacity(0.12), in: Circle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 42)
        }
        .padding(.leading, 24)
        .padding(.trailing, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    @ViewBuilder private func groupSection(_ group: DesktopGroup) -> some View {
        if let items = model.groups[group], !items.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    if model.expandedGroups.contains(group) { model.expandedGroups.remove(group) }
                    else { model.expandedGroups.insert(group) }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: model.expandedGroups.contains(group) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .bold)).frame(width: 12)
                        Text(group.rawValue).font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text("\(items.count)").font(.caption).foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .frame(height: 25)
                }
                .buttonStyle(.plain)

                if model.expandedGroups.contains(group) {
                    ForEach(items) { item in itemRow(item) }
                }
            }
        }
    }

    private func itemRow(_ item: DesktopItem) -> some View {
        HStack(spacing: 9) {
            Image(nsImage: item.icon)
                .resizable().aspectRatio(contentMode: .fit).frame(width: 23, height: 23)
            Text(item.name)
                .font(.system(size: 14))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 9)
        .frame(height: 32)
        .background(model.selectedURL == item.url ? Color.accentColor.opacity(0.20) : Color.primary.opacity(0.035),
                    in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { model.open(item.url) }
        .onTapGesture { model.selectedURL = item.url }
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
        .contextMenu {
            Button("Open") { model.open(item.url) }
            Button("Show in Finder") { model.reveal(item.url) }
            Divider()
            Button("Rename…") { model.rename(item.url) }
            Button("Duplicate") { model.duplicate(item.url) }
            Button("Copy") { model.copy(item.url) }
            Divider()
            Button("Move to Trash", role: .destructive) { model.delete(item.url) }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "desktopcomputer").font(.system(size: 34)).foregroundStyle(.tertiary)
            Text("Your Desktop is empty").font(.headline)
            Text("Drag files here to add them.").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 70)
    }
}
