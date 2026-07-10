//OSCMessageStore
import SwiftUI
import Combine

struct OSCMessage: Identifiable {
    let id = UUID()
    let content: String
    // Color of the track this message originated from, used to color-code
    // each line in the outgoing messages window. Defaults to .primary for
    // any caller that doesn't specify one.
    var color: Color = .primary
}

class OSCMessageStore: ObservableObject {
    @Published var messages: [OSCMessage] = []

    func addMessage(_ message: String, color: Color = .primary) {
        DispatchQueue.main.async {
            self.messages.append(OSCMessage(content: message, color: color))
            if self.messages.count > 100 {
                self.messages.removeFirst(self.messages.count - 100)
            }
        }
    }
}
