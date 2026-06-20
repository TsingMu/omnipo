import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppDestination
    let windowTitlebarHeight: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        Color.clear
                            .frame(
                                height: MainWindowLayout.sidebarTopInset(
                                    safeAreaTop: geometry.safeAreaInsets.top,
                                    windowTitlebarHeight: windowTitlebarHeight
                                )
                            )
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)

                    ForEach(AppDestination.Section.allCases) { section in
                            Text(section.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                                .padding(.horizontal, 8)
                                .padding(.top, section == .overview ? 0 : 14)

                            ForEach(destinations(in: section)) { destination in
                                Button {
                                    selection = destination
                                } label: {
                                    SidebarDestinationRow(
                                        destination: destination,
                                        isSelected: selection == destination
                                    )
                                }
                                .buttonStyle(.plain)
                                .id(destination)
                                .accessibilityIdentifier("nav.\(destination.rawValue)")
                                .accessibilityAddTraits(selection == destination ? .isSelected : [])
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 16)
                }
                .focusable()
                .focusEffectDisabled()
                .onMoveCommand { direction in
                    guard let move = SidebarNavigation.Move(direction) else { return }
                    let destination = SidebarNavigation.destination(from: selection, move: move)
                    selection = destination
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(destination)
                    }
                }
            }
        }
        .navigationTitle("Omnipo")
        .navigationSplitViewColumnWidth(min: 210, ideal: 238, max: 300)
    }

    private func destinations(in section: AppDestination.Section) -> [AppDestination] {
        AppDestination.allCases.filter { $0.section == section }
    }
}

enum SidebarNavigation {
    enum Move {
        case previous
        case next

        init?(_ direction: MoveCommandDirection) {
            switch direction {
            case .up: self = .previous
            case .down: self = .next
            default: return nil
            }
        }
    }

    static func destination(from current: AppDestination, move: Move) -> AppDestination {
        guard let index = AppDestination.allCases.firstIndex(of: current) else {
            return .dashboard
        }
        switch move {
        case .previous:
            return AppDestination.allCases[max(0, index - 1)]
        case .next:
            return AppDestination.allCases[min(AppDestination.allCases.count - 1, index + 1)]
        }
    }
}

private struct SidebarDestinationRow: View {
    let destination: AppDestination
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: destination.symbol)
                .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 1) {
                Text(destination.title)
                    .lineLimit(1)
                Text(destination.sidebarSubtitle)
                    .font(.caption)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Color.secondary)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            isSelected ? Color.accentColor : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contentShape(Rectangle())
    }
}

#Preview {
    @Previewable @State var selection: AppDestination = .dashboard
    SidebarView(selection: $selection, windowTitlebarHeight: 52)
        .frame(width: 240, height: 640)
}
