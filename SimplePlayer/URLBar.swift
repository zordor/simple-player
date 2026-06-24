import SwiftUI
import AppKit

/// Small overlay bar (⌘L) to paste a YouTube link directly. Pre-fills from the clipboard
/// if it already holds a YouTube URL.
struct URLBar: View {
    @EnvironmentObject var model: AppModel
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "link")
                .foregroundStyle(.secondary)
            TextField("Pega un enlace de YouTube y pulsa Enter…", text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit(submit)
            Button("Ver", action: submit)
                .keyboardShortcut(.defaultAction)
                .disabled(YouTubeURL.videoID(from: text) == nil)
            Button {
                model.showURLBar = false
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.1)))
        .shadow(radius: 16, y: 4)
        .frame(maxWidth: 620)
        .padding(.top, 12)
        .onAppear {
            focused = true
            if let clip = NSPasteboard.general.string(forType: .string),
               YouTubeURL.videoID(from: clip) != nil {
                text = clip
            }
        }
    }

    private func submit() {
        guard let id = YouTubeURL.videoID(from: text) else { return }
        model.play(videoID: id)
        model.showURLBar = false
        text = ""
    }
}
