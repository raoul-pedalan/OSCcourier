// PointListView
import SwiftUI

struct PointListView: View {
    // Observed (not a plain array) so edits made on the timeline while this
    // window is open show up immediately.
    @ObservedObject var store: PointListStore
    @State private var selection: UUID?
    // nil = show every track. Otherwise, the name of the single track to show.
    @State private var trackFilter: String?

    // Double-clicking a row opens this editor, in a sheet on THIS window (so
    // the main window never has to come forward). It goes through the Table's
    // own primaryAction rather than per-cell tap gestures: those competed with
    // the Table's internal click handling and fired only intermittently.
    @State private var editingRow: PointListRow?
    @State private var draftTime: String = ""
    @State private var draftLabel: String = ""
    @State private var draftY: String = ""
    @State private var draftComment: String = ""

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
                    .width(min: 70, ideal: 85)

                    TableColumn("Label") { row in
                        naCell(row.label, applicable: row.hasLabel,
                               help: "Points on \(row.trackName) have no label — only markers and message tracks do.")
                    }
                    .width(min: 60, ideal: 90)

                    TableColumn("Value") { row in
                        naCell(row.valueText, applicable: row.hasY,
                               help: "Points on \(row.trackName) have no value — only curve and step tracks do.")
                    }
                    .width(min: 50, ideal: 65)

                    TableColumn("Comment") { row in
                        // Newlines flattened to spaces so one long comment can't
                        // blow up the row height; the full text is in the tooltip
                        // and in the editor.
                        let flat = row.comment
                            .replacingOccurrences(of: "\n", with: " ")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        Text(flat)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .help(row.comment)
                    }
                    .width(min: 120, ideal: 260)
                }
                .contextMenu(forSelectionType: UUID.self) { _ in
                    Button("Edit Point…") { beginEditSelected() }
                } primaryAction: { ids in
                    // Table's own double-click hook: reliable, unlike tap
                    // gestures attached to individual cells.
                    if let id = ids.first, let row = store.rows.first(where: { $0.id == id }) {
                        beginEdit(row)
                    }
                }

                Divider()

                HStack {
                    Text("\(visibleRows.count) point\(visibleRows.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Edit Point…") { beginEditSelected() }
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
        .sheet(isPresented: Binding<Bool>(
            get: { editingRow != nil },
            set: { if !$0 { cancelEdit() } }
        )) {
            editorSheet
        }
    }

    // Cells for fields the track doesn't have (a label on a bang, a value on a
    // marker) show an em dash — the macOS convention for "not applicable" —
    // instead of an ambiguous blank, with a tooltip saying why.
    @ViewBuilder
    private func naCell(_ text: String, applicable: Bool, help: String) -> some View {
        Text(applicable ? text : "—")
            .monospacedDigit()
            .foregroundColor(applicable ? .primary : .secondary.opacity(0.45))
            .lineLimit(1)
            .truncationMode(.tail)
            .help(applicable ? "" : help)
    }

    private var editorSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let row = editingRow {
                HStack(spacing: 6) {
                    Circle()
                        .fill(row.trackColor)
                        .frame(width: 8, height: 8)
                    Text("Edit point on \(row.trackName)")
                        .font(.headline)
                }
                .padding(.bottom, 4)

                HStack {
                    Text("Position (s)")
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 100, alignment: .trailing)
                    TextField("", text: $draftTime)
                }

                // Only the fields this track actually has are shown, so the
                // sheet never offers something meaningless to fill in.
                if row.hasY {
                    HStack {
                        Text(String(format: "Y [%g, %g]", row.minAmplitude, row.maxAmplitude))
                            .foregroundColor(.gray.opacity(0.7))
                            .frame(width: 100, alignment: .trailing)
                        TextField("", text: $draftY)
                    }
                }

                if row.hasLabel {
                    HStack {
                        Text("Label")
                            .foregroundColor(.gray.opacity(0.7))
                            .frame(width: 100, alignment: .trailing)
                        TextField("", text: $draftLabel)
                    }
                }

                HStack(alignment: .top) {
                    Text("Comment")
                        .foregroundColor(.gray.opacity(0.7))
                        .frame(width: 100, alignment: .trailing)
                    TextField("", text: $draftComment)
                        // A plain single-line field: no newlines to type in
                        // the first place, and Return submits (like every
                        // other field in this sheet) instead of inserting a
                        // line break.
                        .onSubmit { commitEdit() }
                }

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) { cancelEdit() }
                    Button("OK") { commitEdit() }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.top, 8)
            }
        }
        .padding(20)
        .frame(width: 360)
    }

    private func beginEditSelected() {
        guard let id = selection, let row = store.rows.first(where: { $0.id == id }) else { return }
        beginEdit(row)
    }

    private func beginEdit(_ row: PointListRow) {
        // Plain seconds, not mm:ss — simpler to type, and matches the
        // timeline's own point editor.
        draftTime = String(format: "%.2f", row.time)
        draftY = String(format: "%.2f", row.y)
        draftLabel = row.label
        draftComment = row.comment
        editingRow = row
    }

    private func commitEdit() {
        guard let row = editingRow else { return }
        var edit = PointEdit(id: row.id)

        if let v = Double(draftTime.trimmingCharacters(in: .whitespaces)) {
            edit.time = v
        }
        if row.hasY, let v = Double(draftY.trimmingCharacters(in: .whitespaces)) {
            edit.y = v
        }
        if row.hasLabel {
            edit.label = draftLabel
        }
        edit.comment = draftComment

        store.onCommitEdit?(edit)
        cancelEdit()
    }

    private func cancelEdit() {
        editingRow = nil
        draftTime = ""
        draftY = ""
        draftLabel = ""
        draftComment = ""
    }

    private func formattedTime(_ t: Double) -> String {
        let minutes = Int(t) / 60
        let seconds = Int(t) % 60
        let centis = Int((t - floor(t)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, centis)
    }
}
