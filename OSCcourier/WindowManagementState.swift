import Combine
import SwiftUI
import AppKit

/// Owns the state for the three auxiliary NSWindow-backed panels
/// (OSC messages log, point list, modifier-keys help) plus the PDF
/// export preview window: their controllers, visibility flags, and
/// close delegates. Extracted from ContentView as part of the
/// ObservableObject-based state architecture refactor.
final class WindowManagementState: ObservableObject {
    @Published var messagesWindowController: NSWindowController?
    @Published var isOSCWindowVisible: Bool = false
    @Published var oscWindowCloseDelegate: OSCWindowCloseDelegate?

    @Published var pointListWindowController: NSWindowController?
    @Published var isPointListWindowVisible: Bool = false
    @Published var pointListCloseDelegate: OSCWindowCloseDelegate?

    @Published var pdfWindowController: NSWindowController?

    @Published var modifierKeysWindowController: NSWindowController?
    @Published var isModifierKeysWindowVisible: Bool = false
    @Published var modifierKeysCloseDelegate: OSCWindowCloseDelegate?
}
