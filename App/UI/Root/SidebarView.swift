import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppDestination

    var body: some View {
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
        .navigationTitle("Omnipo")
        .navigationSplitViewColumnWidth(min: 210, ideal: 238, max: 300)
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
