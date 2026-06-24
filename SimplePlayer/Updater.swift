import SwiftUI
import AppKit

struct UpdateInfo {
    let version: String
    let notes: String
    let downloadURL: URL
}

/// Self-updater backed by GitHub Releases. Checks the latest published release, and on request
/// downloads its .zip asset, swaps the running .app bundle and relaunches — no manual steps.
@MainActor
final class Updater: ObservableObject {
    @Published var available: UpdateInfo?
    @Published var status: String?
    @Published var busy = false

    private let repo = "zordor/simple-player"
    private var pollTask: Task<Void, Never>?
    private var dismissedVersion: String?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Checks now and then keeps polling in the background, so a release published while the app
    /// is open is offered live — not only at launch.
    func startChecking() {
        guard pollTask == nil else { return }
        pollTask = Task {
            await check(announceUpToDate: false)
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15 * 60 * 1_000_000_000)
                if Task.isCancelled { break }
                await check(announceUpToDate: false)
            }
        }
    }

    /// `announceUpToDate` shows a transient "you're current" message (used by the manual menu check).
    func check(announceUpToDate: Bool) async {
        guard !busy else { return }
        if announceUpToDate { status = "Buscando actualizaciones…" }
        do {
            if let info = try await fetchLatest(), isNewer(info.version, than: currentVersion) {
                // For background polls, don't re-nag about a version the user already dismissed.
                if !announceUpToDate && info.version == dismissedVersion { return }
                available = info
                status = nil
            } else {
                available = nil
                if announceUpToDate { flash("Ya tienes la última versión (v\(currentVersion)).") }
            }
        } catch {
            if announceUpToDate { flash("No se pudo comprobar: \(error.localizedDescription)") }
        }
    }

    func install() {
        guard let info = available, !busy else { return }
        busy = true
        Task {
            do {
                status = "Descargando v\(info.version)…"
                let newApp = try await downloadAndUnzip(info.downloadURL)
                status = "Instalando…"
                try relaunch(with: newApp)   // terminates the app on success
            } catch {
                busy = false
                status = "Error al actualizar: \(error.localizedDescription)"
            }
        }
    }

    func dismiss() {
        dismissedVersion = available?.version
        available = nil
        status = nil
    }

    // MARK: - GitHub

    private struct GHRelease: Decodable {
        let tag_name: String
        let body: String?
        let assets: [GHAsset]
    }
    private struct GHAsset: Decodable {
        let name: String
        let browser_download_url: String
    }

    private func fetchLatest() async throws -> UpdateInfo? {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }          // no releases yet
        guard http.statusCode == 200 else {
            throw err("GitHub respondió \(http.statusCode)")
        }
        let release = try JSONDecoder().decode(GHRelease.self, from: data)
        guard let asset = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
              let url = URL(string: asset.browser_download_url) else { return nil }
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        return UpdateInfo(version: version, notes: release.body ?? "", downloadURL: url)
    }

    // MARK: - Install mechanics

    private func downloadAndUnzip(_ url: URL) async throws -> URL {
        let (tmpFile, _) = try await URLSession.shared.download(from: url)
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("SimplePlayerUpdate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("update.zip")
        try FileManager.default.moveItem(at: tmpFile, to: zip)

        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", zip.path, work.path]
        try unzip.run()
        unzip.waitUntilExit()
        guard unzip.terminationStatus == 0 else { throw err("No se pudo descomprimir la actualización") }

        let contents = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
        guard let app = contents.first(where: { $0.pathExtension == "app" }) else {
            throw err("El zip no contenía una app")
        }
        return app
    }

    /// Hands off to a detached shell script that waits for us to quit, replaces the bundle and
    /// reopens it, then terminates the app.
    private func relaunch(with newApp: URL) throws {
        let dest = Bundle.main.bundleURL
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        #!/bin/sh
        while kill -0 \(pid) 2>/dev/null; do sleep 0.3; done
        xattr -dr com.apple.quarantine "\(newApp.path)" 2>/dev/null
        rm -rf "\(dest.path)"
        mv "\(newApp.path)" "\(dest.path)"
        xattr -dr com.apple.quarantine "\(dest.path)" 2>/dev/null
        open "\(dest.path)"
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sp-update-\(UUID().uuidString).sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let runner = Process()
        runner.executableURL = URL(fileURLWithPath: "/bin/sh")
        runner.arguments = [scriptURL.path]
        try runner.run()

        NSApp.terminate(nil)
    }

    // MARK: - Helpers

    private func isNewer(_ a: String, than b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private func flash(_ message: String) {
        status = message
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if self.status == message { self.status = nil }
        }
    }

    private func err(_ message: String) -> NSError {
        NSError(domain: "Updater", code: 0, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

/// Discreet top banner: offers the update (or shows a transient status message).
struct UpdateBanner: View {
    @EnvironmentObject var updater: Updater

    var body: some View {
        Group {
            if let info = updater.available {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.app.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Versión \(info.version) disponible")
                            .font(.system(size: 13, weight: .semibold))
                        if updater.busy, let s = updater.status {
                            Text(s).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if updater.busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Actualizar") { updater.install() }
                            .buttonStyle(.borderedProminent)
                        Button("Ahora no") { updater.dismiss() }
                            .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .frame(maxWidth: 620)
            } else if let status = updater.status {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                    Text(status).font(.system(size: 13))
                }
                .padding(12)
                .frame(maxWidth: 620)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.1)))
        .shadow(radius: 16, y: 4)
        .padding(.top, 12)
    }
}
