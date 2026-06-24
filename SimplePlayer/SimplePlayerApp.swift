import SwiftUI

@main
struct SimplePlayerApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var updater = Updater()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .environmentObject(updater)
                .frame(minWidth: 640, minHeight: 400)
                .task { updater.startChecking() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("Buscar actualizaciones…") {
                    Task { await updater.check(announceUpToDate: true) }
                }
                .keyboardShortcut("u", modifiers: .command)
            }
            CommandMenu("Reproducir") {
                Button("Pegar URL de YouTube…") { model.showURLBar.toggle() }
                    .keyboardShortcut("l", modifiers: .command)
                Button("Volver a YouTube") { model.backToBrowse() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(model.mode == .browse)
            }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var updater: Updater

    var body: some View {
        ZStack(alignment: .top) {
            // Kept mounted (even while playing) so the login session and scroll position survive.
            BrowseView()
                .opacity(model.mode == .browse ? 1 : 0)

            if model.mode == .player, let id = model.currentVideoID {
                PlayerView(videoID: id)
                    .transition(.opacity)
            }

            if model.showURLBar {
                URLBar()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }

            if updater.available != nil || updater.status != nil {
                UpdateBanner()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .ignoresSafeArea()
        .background(Color.black)
        .animation(.easeInOut(duration: 0.2), value: updater.available?.version)
        .animation(.easeInOut(duration: 0.2), value: updater.status)
    }
}
