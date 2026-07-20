import SwiftUI

// A quick-reference list of every modifier-key behavior in the app —
// distinct from the full Help PDF, this is meant to stay open on the side
// while working, as a cheat sheet.
struct ModifierKeysHelpView: View {
    private struct Entry: Identifiable {
        let id = UUID()
        let keys: String
        let action: String
        let context: String
    }

    private let entries: [Entry] = [
        Entry(keys: "⌘ drag", action: "Snap to the nearest marker or grid line",
              context: "Dragging a point, the playhead, or a loop zone edge/body"),
        Entry(keys: "⌥ drag", action: "Add curvature (simple or S-shaped)",
              context: "Dragging a curve segment (curve tracks only)"),
        Entry(keys: "⌥ hover", action: "Switch to “Duplicate track”",
              context: "Hovering the Clear-points button in a track header"),
        Entry(keys: "⌥ click", action: "Edit the grid's offset (Φ) and step (T)",
              context: "Clicking the Grid button in the command bar"),
        Entry(keys: "⇧ click", action: "Remove the point",
              context: "Clicking a point"),
        Entry(keys: "⇧ click", action: "Remove or rebuild the segment",
              context: "Clicking a curve segment"),
        Entry(keys: "⇧ click", action: "Erase the loop zone",
              context: "Clicking the loop zone in the ruler"),
        Entry(keys: "⇧⌥ drag", action: "Lasso-select points",
              context: "Dragging on a track's content area"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Modifier Keys")
                .font(.headline)
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            VStack(spacing: 0) {
                ForEach(entries) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Text(entry.keys)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 80, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.action)
                                .font(.body)
                            Text(entry.context)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if entry.id != entries.last?.id {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .frame(width: 380)
    }
}
