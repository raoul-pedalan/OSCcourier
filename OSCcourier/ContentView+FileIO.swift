import SwiftUI
import AppKit
import PDFKit
import UniformTypeIdentifiers

extension ContentView {

    func encodedProjectData() -> Data? {
        let data = SaveData(duree: duree, oscAddress: oscManager.address, zoomX: zoomX, pistes: pistes)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(data)
    }

    func saveProject() {
        guard let jsonData = encodedProjectData() else { return }

        if let url = savedFileURL {
            try? jsonData.write(to: url)
        } else {
            promptAndSave(jsonData)
        }
    }

    func saveProjectAs() {
        guard let jsonData = encodedProjectData() else { return }
        promptAndSave(jsonData)
    }

    func promptAndSave(_ jsonData: Data) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "OSCcourier.json"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            savedFileURL = url
            try? jsonData.write(to: url)
        }
    }

    func loadProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let jsonData = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(SaveData.self, from: jsonData) else { return }

        enLecture = false
        position = 0
        lastSentEvents.removeAll()
        duree = decoded.duree
        dureeText = formattedDuration(decoded.duree)
        zoomX = decoded.zoomX
        oscManager.address = decoded.oscAddress
        oscManager.setupOSCConnection()
        pistes = decoded.pistes
        savedFileURL = url // further saves overwrite the file we just loaded
    }

    func openPDFWindow() {
        if pdfWindowController != nil {
            pdfWindowController?.showWindow(nil)
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
        pdfWindowController = NSWindowController(window: window)
        pdfWindowController?.showWindow(nil)
    }

}
