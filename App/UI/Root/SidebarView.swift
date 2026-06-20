import AppKit
import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppDestination
    @State private var windowTitlebarHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                Color.clear
                    .frame(
                        height: SidebarLayout.viewportTopInset(
                            safeAreaTop: geometry.safeAreaInsets.top,
                            windowTitlebarHeight: windowTitlebarHeight
                        )
                    )
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                List(selection: $selection) {
                    ForEach(AppDestination.Section.allCases) { section in
                        Section(section.title) {
                            ForEach(AppDestination.allCases.filter { $0.section == section }) { destination in
                                SidebarDestinationRow(destination: destination)
                                    .tag(destination)
                                    .accessibilityIdentifier("nav.\(destination.rawValue)")
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .background(WindowTitlebarHeightReader(height: $windowTitlebarHeight))
        }
        .navigationTitle("Omnipo")
        .navigationSplitViewColumnWidth(min: 210, ideal: 238, max: 300)
    }
}

enum SidebarLayout {
    private static let sectionHeaderClearance: CGFloat = 24

    static func viewportTopInset(safeAreaTop: CGFloat, windowTitlebarHeight: CGFloat) -> CGFloat {
        let titlebarInset = max(0, safeAreaTop, windowTitlebarHeight)
        return titlebarInset > 0 ? titlebarInset + sectionHeaderClearance : 0
    }
}

private struct WindowTitlebarHeightReader: NSViewRepresentable {
    @Binding var height: CGFloat

    func makeNSView(context: Context) -> WindowTitlebarProbeView {
        let view = WindowTitlebarProbeView()
        view.onHeightChange = updateHeight
        return view
    }

    func updateNSView(_ nsView: WindowTitlebarProbeView, context: Context) {
        nsView.onHeightChange = updateHeight
        nsView.publishCurrentHeight()
    }

    private func updateHeight(_ newHeight: CGFloat) {
        guard height != newHeight else { return }
        height = newHeight
    }
}

private final class WindowTitlebarProbeView: NSView {
    var onHeightChange: ((CGFloat) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindowResize()
        publishCurrentHeight()
    }

    override func layout() {
        super.layout()
        publishCurrentHeight()
    }

    func publishCurrentHeight() {
        guard let window else { return }
        let titlebarHeight = max(0, window.frame.height - window.contentLayoutRect.height)
        onHeightChange?(titlebarHeight)
    }

    private func observeWindowResize() {
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResizeNotification, object: nil)
        guard let window else { return }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidResize),
            name: NSWindow.didResizeNotification,
            object: window
        )
    }

    @objc private func windowDidResize() {
        publishCurrentHeight()
    }
}

private struct SidebarDestinationRow: View {
    let destination: AppDestination

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: destination.symbol)
                .foregroundStyle(.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(destination.title)
                    .lineLimit(1)
                Text(destination.sidebarSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    @Previewable @State var selection: AppDestination = .dashboard
    SidebarView(selection: $selection)
        .frame(width: 240, height: 640)
}
