// OSCMessageView
import SwiftUI

struct OSCMessagesView: View {
    @ObservedObject var messageStore: OSCMessageStore
    // Appearance is applied app-wide via NSApp.appearance (see
    // AppearanceMode.apply in OSCcourierApp), so this view doesn't set any
    // .preferredColorScheme of its own — it just reads the resolved scheme
    // and picks colors from it. That's what keeps SwiftUI views and
    // AppKit-backed chrome (title bar) from disagreeing.
    @Environment(\.colorScheme) private var colorScheme

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color(white: 1)
    }
    private var dividerColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.1)
    }
    private var secondaryTextColor: Color {
        colorScheme == .dark ? Color.gray.opacity(0.6) : Color.gray
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(messageStore.messages.reversed(), id: \.id) { message in
                        let parts = message.content.components(separatedBy: " ")
                        if parts.count > 0 {
                            HStack(spacing: 6) {
                                Text(parts[0])
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .frame(width: 70, alignment: .trailing)
                                if parts.count > 1 {
                                    Text(parts.dropFirst().joined(separator: " "))
                                        .font(.system(size: 11, design: .monospaced))
                                }
                                Spacer(minLength: 0)
                            }
                            .foregroundColor(message.color)
                            .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 50, idealWidth: 220, minHeight: 260)
            .background(backgroundColor)

            Divider()
                .background(dividerColor)

            HStack {
                Text("\(messageStore.messages.count) message\(messageStore.messages.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundColor(secondaryTextColor)
                Spacer()
                Button(action: { messageStore.messages.removeAll() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundColor(secondaryTextColor)
                }
                .buttonStyle(.plain)
                .help("Clear all messages")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
        }
        .background(backgroundColor)
    }
}
