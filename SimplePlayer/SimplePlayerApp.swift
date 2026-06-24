import SwiftUI

@main
struct SimplePlayerApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 640, minHeight: 400)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
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
        }
        .ignoresSafeArea()
        .background(Color.black)
    }
}
