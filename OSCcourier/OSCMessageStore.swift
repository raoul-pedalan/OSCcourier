import SwiftUI
import Combine

struct OSCMessage: Identifiable {
    let id = UUID()
    let content: String
}

class OSCMessageStore: ObservableObject {
    @Published var messages: [OSCMessage] = []

    func addMessage(_ message: String) {
        DispatchQueue.main.async {
            self.messages.append(OSCMessage(content: message))
            if self.messages.count > 100 {
                self.messages.removeFirst(self.messages.count - 100)
            }
        }
    }
}
