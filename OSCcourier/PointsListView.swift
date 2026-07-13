// PointsListView
import SwiftUI

struct PointsListView: View {
    // Observed (not a plain array) so edits made on the timeline while this
    // window is open show up immediately.
    @ObservedObject var store: PointsListStore
    @State private var selection: UUID?
    // nil = show every track. Otherwise, the name of the single track to show.
    @State private var trackFilter: String?

    // Rows actually displayed, after the track filter is applied.
    private var visibleRows: [PointListRow] {
        guard let filter = trackFilter else { return store.rows }
        return store.rows.filter { $0.trackName == filter }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Track")
                    .foregroundColor(.secondary)
                Picker("", selection: $trackFilter) {
                    Text("All Tracks").tag(String?.none)
                    Divider()
                    ForEach(store.trackNames, id: \.self) { name in
                        Text(name).tag(String?.some(name))
                    }
                }
                .labelsHidden()
                .frame(width: 180)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if visibleRows.isEmpty {
                Spacer()
                Text(store.rows.isEmpty ? "No points" : "No points on this track")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                Table(visibleRows, selection: $selection) {
                    TableColumn("Track") { row in
                        HStack(spacing: 6) {
                            Circle()
                                .fill(row.trackColor)
                                .frame(width: 8, height: 8)
                            Text(row.trackName)
                        }
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("Time") { row in
                        Text(formattedTime(row.time))
                            .monospacedDigit()
                    }
                    .width(min: 70, ideal: 80)

                    TableColumn("Label") { row in
                        Text(row.label)
                    }
                    .width(min: 60, ideal: 90)

                    TableColumn("Value") { row in
                        Text(row.value)
                            .monospacedDigit()
                    }
                    .width(min: 50, ideal: 60)

                    TableColumn("Comment") { row in
                        // Comments are multi-line; show them wrapped rather
                        // than truncated to a single line.
                        Text(row.comment)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .width(min: 120, ideal: 260)
                }
                // Double-clicking a row opens the same point editor the
                // timeline uses (see PointsListStore.onRequestEdit).
                .contextMenu(forSelectionType: UUID.self) { _ in
                    Button("Edit Point…") { requestEditSelected() }
                } primaryAction: { ids in
                    if let id = ids.first {
                        store.onRequestEdit?(id)
                    }
                }

                Divider()

                HStack {
                    Text("\(visibleRows.count) point\(visibleRows.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Edit Point…") {
                        requestEditSelected()
                    }
                    .disabled(selection == nil)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .frame(minWidth: 520, minHeight: 300)
        .onChange(of: store.trackNames) { _, names in
            // A filtered track can disappear (renamed or deleted) while the
            // window is open — fall back to showing everything rather than an
            // empty list pinned to a track that no longer exists.
            if let filter = trackFilter, !names.contains(filter) {
                trackFilter = nil
            }
        }
    }

    private func requestEditSelected() {
        guard let id = selection else { return }
        store.onRequestEdit?(id)
    }

    private func formattedTime(_ t: Double) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        let centis = Int((t - floor(t)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, centis)
    }
}
