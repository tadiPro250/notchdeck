import SwiftUI

struct TrayView: View {
    @ObservedObject var model: NotchModel
    @ObservedObject var tray: FileTray

    var body: some View {
        if tray.items.isEmpty {
            dropZone
        } else {
            HStack(spacing: 14) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(tray.items, id: \.self) { url in
                            TrayTile(url: url, tray: tray)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .overlay(alignment: .center) {
                    if model.dropTargeted {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    }
                }
                VStack(spacing: 8) {
                    Button { tray.airDrop() } label: {
                        Label("AirDrop", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle())
                    Button { tray.clear() } label: {
                        Label("Clear", systemImage: "trash")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PillButtonStyle())
                    Text("Drag out to use")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .frame(width: 96)
            }
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Color.white.opacity(model.dropTargeted ? 0.7 : 0.22),
                          style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(model.dropTargeted ? 0.06 : 0)))
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 22))
                    Text("Drop files here")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Drag anything onto the notch to stash it for later")
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.45))
                }
                .foregroundStyle(.white.opacity(0.85))
            }
            .animation(.easeOut(duration: 0.15), value: model.dropTargeted)
    }
}

private struct TrayTile: View {
    let url: URL
    let tray: FileTray
    @StateObject private var thumbnail = ViewState<NSImage?>(nil)
    @StateObject private var hovering = ViewState<Bool>(false)

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: thumbnail.value ?? NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 54, height: 54)
            Text(url.lastPathComponent)
                .font(.system(size: 9.5, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 76, height: 26, alignment: .top)
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(hovering.value ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if hovering.value {
                Button { tray.remove(url) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, Color(white: 0.35))
                }
                .buttonStyle(.plain)
                .offset(x: 2, y: -2)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering.value = $0 }
        .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
        .onTapGesture(count: 2) { tray.open(url) }
        .contextMenu {
            Button("Open") { tray.open(url) }
            Button("Show in Finder") { tray.reveal(url) }
            Button("AirDrop") { tray.airDrop([url]) }
            Divider()
            Button("Remove from Tray") { tray.remove(url) }
        }
        .help(url.path)
        .task(id: url) {
            thumbnail.value = await Thumbnails.image(for: url, size: 108)
        }
    }
}
