import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

extension ContentView {

    // Whether the live project state differs from the last successful
    // save/load. nil baseline (shouldn't normally happen past onAppear)
    // fails open — treated as "no changes" rather than risking a window
    // that can never close.
    func hasUnsavedChanges() -> Bool {
        guard let lastSavedProjectData else { return false }
        return encodedProjectData() != lastSavedProjectData
    }

    func encodedProjectData() -> Data? {
        let data = SaveData(
            duree: transport.duree,
            oscAddress: oscManager.address,
            oscAddressPrefix: oscAddressPrefix,
            oscReceivePort: oscReceivePort,
            zoomX: transport.zoomX,
            pistes: pistes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(data)
    }

    // Returns whether the save actually completed — used both to decide
    // whether it's safe to close the window afterward (see
    // MainWindowCloseDelegate) and to know whether to update the
    // unsaved-changes baseline.
    @discardableResult
    func saveProject() -> Bool {
        guard let jsonData = encodedProjectData() else {
            fileIOErrorMessage = "Could not prepare the project data to save."
            return false
        }

        if let url = savedFileURL {
            do {
                try jsonData.write(to: url)
                addToRecentFiles(url)
                lastSavedProjectData = jsonData
                return true
            } catch {
                fileIOErrorMessage = "Could not save \"\(url.lastPathComponent)\": \(error.localizedDescription)"
                return false
            }
        } else {
            return promptAndSave(jsonData)
        }
    }

    @discardableResult
    func saveProjectAs() -> Bool {
        guard let jsonData = encodedProjectData() else {
            fileIOErrorMessage = "Could not prepare the project data to save."
            return false
        }
        return promptAndSave(jsonData)
    }

    @discardableResult
    func promptAndSave(_ jsonData: Data) -> Bool {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "OSCcourier.json"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try jsonData.write(to: url)
            savedFileURL = url
            addToRecentFiles(url)
            lastSavedProjectData = jsonData
            return true
        } catch {
            fileIOErrorMessage = "Could not save \"\(url.lastPathComponent)\": \(error.localizedDescription)"
            return false
        }
    }

    func loadProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadProject(from: url)
    }

    // Shared by the "Load…" panel above and by clicking an entry in the
    // File > Open Recent submenu — both just need a URL to load from.
    func loadProject(from url: URL) {
        let jsonData: Data
        let decoded: SaveData
        do {
            jsonData = try Data(contentsOf: url)
            decoded = try JSONDecoder().decode(SaveData.self, from: jsonData)
        } catch {
            fileIOErrorMessage = "Could not open \"\(url.lastPathComponent)\": \(error.localizedDescription)"
            return
        }

        transport.enLecture = false
        transport.position = 0
        pointDrag.invalidateSentCache()
        transport.duree = decoded.duree
        transport.dureeText = formattedDuration(decoded.duree)
        transport.zoomX = decoded.zoomX
        oscManager.address = decoded.oscAddress
        oscManager.setupOSCConnection()
        // Fall back to this window's current values (its own defaults) for
        // project files saved before these existed, rather than silently
        // resetting to some hardcoded value.
        oscAddressPrefix = decoded.oscAddressPrefix ?? oscAddressPrefix
        oscReceivePort = decoded.oscReceivePort ?? oscReceivePort
        oscManager.startListening(port: oscReceivePort)
        pistes = decoded.pistes
        savedFileURL = url // further saves overwrite the file we just loaded
        addToRecentFiles(url)
        // Re-encode from the state we just applied (rather than reusing the
        // raw file bytes) so this exactly matches what encodedProjectData()
        // will produce on the next dirty-check — avoids a false "unsaved
        // changes" the instant a project is loaded, from incidental
        // formatting differences between the file on disk and our encoder.
        lastSavedProjectData = encodedProjectData()
    }

    // Recent files are shared with OSCcourierApp via the same @AppStorage
    // key, so the "Open Recent" submenu updates reactively without any
    // NotificationCenter plumbing for the list itself — only the click
    // action (which needs to load into THIS window) goes through a
    // notification. Stored as newline-separated POSIX paths (not full
    // URLs) since that's simple to persist as a single String value.
    func addToRecentFiles(_ url: URL) {
        var paths = recentFilePathsData.split(separator: "\n").map(String.init)
        let path = url.path
        paths.removeAll { $0 == path }
        paths.insert(path, at: 0)
        if paths.count > 10 {
            paths = Array(paths.prefix(10))
        }
        recentFilePathsData = paths.joined(separator: "\n")
    }

    func openPDFWindow() {
        if windowManagement.pdfWindowController != nil {
            windowManagement.pdfWindowController?.showWindow(nil)
            return
        }
        guard let pdfURL = Bundle.main.url(forResource: "Help", withExtension: "pdf") else { return }
        let document = PDFDocument(url: pdfURL)
        let pdfView = PDFView()
        pdfView.document = document
        pdfView.autoScales = false
        pdfView.scaleFactor = 1.5

        // Size the window to fit the PDF's actual page at that same scale,
        // instead of a fixed guess, so nothing gets cut off horizontally.
        var contentWidth: CGFloat = 600
        var contentHeight: CGFloat = 800
        if let page = document?.page(at: 0) {
            let pageBounds = page.bounds(for: .mediaBox)
            contentWidth = pageBounds.width * pdfView.scaleFactor
            contentHeight = pageBounds.height * pdfView.scaleFactor
        }
        if let screenFrame = NSScreen.main?.visibleFrame {
            contentWidth = min(contentWidth, screenFrame.width * 0.9)
            contentHeight = min(contentHeight, screenFrame.height * 0.9)
        }

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
                             styleMask: [.titled, .closable, .resizable],
                             backing: .buffered,
                             defer: false)
        window.title = "Help"
        window.center()
        window.contentView = pdfView
        // Without this, closing the window releases it (the default for a
        // programmatically-created NSWindow), leaving windowManagement.pdfWindowController
        // pointing at a dead window — so the menu item would appear to do
        // nothing at all the next time, since it thinks the window still
        // exists and just tries to re-show it instead of rebuilding one.
        window.isReleasedWhenClosed = false
        windowManagement.pdfWindowController = NSWindowController(window: window)
        windowManagement.pdfWindowController?.showWindow(nil)
    }

}
