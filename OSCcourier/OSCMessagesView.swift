import SwiftUI

struct OSCMessagesView: View {
    @ObservedObject var messageStore: OSCMessageStore

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
                            .textSelection(.enabled)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minWidth: 50, idealWidth: 220, minHeight: 260)

            Divider()

            Button("Clear Window") {
                messageStore.messages.removeAll()
            }
            .padding(8)
        }
    }
}
