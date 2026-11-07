#if DEBUG
import SwiftUI
import AppKit

/// Nur in Debug-Builds: Ist `BLITZTEXT_SNAPSHOT_DIR` gesetzt, rendert die App
/// die Hauptseite hell und dunkel als PNG in diesen Ordner und beendet sich.
/// So lässt sich die Oberfläche prüfen, ohne das Menüleisten-Fenster per Hand
/// zu öffnen.
enum DebugSnapshots {
    static var folder: URL? {
        ProcessInfo.processInfo.environment["BLITZTEXT_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0) }
    }

    @MainActor
    static func renderAndQuit(appState: AppState) {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let pages: [(String, PopoverPage)] = [("main", .main), ("history", .history), ("settings", .settings)]
        for (name, page) in pages {
            appState.page = page
            for (suffix, appearanceName) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let host = NSHostingView(rootView: MenuBarView(appState: appState))
                let window = NSWindow(
                    contentRect: NSRect(x: -4000, y: -4000, width: MenuBarView.width, height: 400),
                    styleMask: [.borderless], backing: .buffered, defer: false
                )
                window.appearance = NSAppearance(named: appearanceName)
                window.contentView = host
                window.orderFrontRegardless()
                host.layoutSubtreeIfNeeded()
                // Seiten mit ScrollView haben keine natürliche Höhe; wie im Popover begrenzen.
                let size = page == .settings
                    ? NSSize(width: MenuBarView.width, height: 600)
                    : host.fittingSize
                window.setContentSize(size)
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                    NSLog("Snapshot: kein Bitmap für \(name) \(NSStringFromSize(size))")
                    continue
                }
                host.cacheDisplay(in: host.bounds, to: rep)
                let url = folder.appendingPathComponent("\(name)-\(suffix).png")
                do {
                    try rep.representation(using: .png, properties: [:])?.write(to: url)
                } catch {
                    NSLog("Snapshot: \(error)")
                }
                window.orderOut(nil)
            }
        }
        exit(0)
    }
}
#endif
