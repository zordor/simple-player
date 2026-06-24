import Foundation

struct StreamURLs {
    let video: URL
    /// nil ⇒ `video` is a combined (progressive) stream with audio already muxed in.
    let audio: URL?
}

enum StreamResolverError: LocalizedError {
    case ytdlpNotFound
    case failed(String)
    case noURLs

    var errorDescription: String? {
        switch self {
        case .ytdlpNotFound:
            return "No se encontró yt-dlp. Instálalo con: brew install yt-dlp"
        case .failed(let msg):
            return msg
        case .noURLs:
            return "yt-dlp no devolvió ninguna URL de stream."
        }
    }
}

/// Resolves a YouTube video id into directly-playable stream URLs via yt-dlp.
///
/// We deliberately constrain to H.264 video + m4a audio (mp4 container): AVFoundation
/// cannot decode YouTube's VP9/AV1 high-res streams, so H.264 (≤1080p) is the realistic
/// native ceiling. Falls back to a progressive mp4, then to whatever `best` yields.
enum StreamResolver {
    private static let format =
        "bestvideo[vcodec^=avc1][height<=1080]+bestaudio[acodec^=mp4a]/" +
        "best[ext=mp4][height<=1080]/best[ext=mp4]/best"

    static func resolve(videoID: String, cookiesFile: URL?) throws -> StreamURLs {
        guard let ytdlp = locate() else { throw StreamResolverError.ytdlpNotFound }

        var args = ["-f", format, "-g", "--no-playlist", "--no-warnings"]
        if let cookiesFile {
            args += ["--cookies", cookiesFile.path]
        }
        args.append("https://www.youtube.com/watch?v=\(videoID)")

        let output = try run(ytdlp, args)
        let urls = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("http") }
            .compactMap { URL(string: $0) }

        guard let first = urls.first else { throw StreamResolverError.noURLs }
        if urls.count >= 2 {
            return StreamURLs(video: first, audio: urls[1])
        }
        return StreamURLs(video: first, audio: nil)
    }

    private static func locate() -> String? {
        let candidates = ["/opt/homebrew/bin/yt-dlp", "/usr/local/bin/yt-dlp", "/usr/bin/yt-dlp"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func run(_ launchPath: String, _ args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        try process.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            let err = String(data: errData, encoding: .utf8) ?? ""
            let trimmed = err.trimmingCharacters(in: .whitespacesAndNewlines)
            throw StreamResolverError.failed(trimmed.isEmpty ? "yt-dlp salió con código \(process.terminationStatus)" : trimmed)
        }
        return String(data: outData, encoding: .utf8) ?? ""
    }
}
