import SwiftUI
import AppKit

// Captures the NSWindow hosting this SwiftUI view, once it's attached to
// one — the standard trick for this since SwiftUI itself has no
// environment value for "my own window". Used so each ContentView
// instance can tell whether IT is the frontmost OSCcourier window:
// keyboard-shortcut/menu commands are broadcast via NotificationCenter to
// every open window's ContentView (see ContentView+NotificationHandling),
// so without this check a shortcut pressed in one window would also fire
// in every other OSCcourier window open at the same time.
struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ResolvingView()
        view.onResolve = onResolve
        return view
    }

    // Deliberately does nothing: the window is captured once, below, via
    // viewDidMoveToWindow — which AppKit calls exactly when the view's
    // window actually changes, not on every SwiftUI body re-evaluation.
    // An earlier version called onResolve here unconditionally, which
    // fired on every re-render (transport.position alone re-renders
    // ContentView ~20x/sec during playback), each time setting the
    // @State hostWindow property, which itself triggers another
    // re-render — a feedback loop that was the actual cause of the
    // choppy/stuttering playback reported after this file was added.
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ResolvingView: NSView {
        var onResolve: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onResolve?(window)
        }
    }
}
