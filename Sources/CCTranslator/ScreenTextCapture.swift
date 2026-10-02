import AppKit
import Vision

/// "Translate screen area": the system's own region picker, then on-device text recognition.
enum ScreenTextCapture {
    enum Outcome {
        case text(String)
        case noText
        case cancelled
        case needsPermission
    }

    static func run() async -> Outcome {
        guard CGPreflightScreenCaptureAccess() else {
            requestPermission()
            return .needsPermission
        }
        let url = FileManager.default.temporaryDirectory.appending(path: "cc-translator-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }

        guard await pickRegion(into: url), FileManager.default.fileExists(atPath: url.path) else {
            return .cancelled
        }
        let text = await recognizeText(in: url)
        return text.isEmpty ? .noText : .text(text)
    }

    /// `screencapture -i` is the same crosshair picker as ⇧⌘4: Space switches to window mode,
    /// Esc cancels (and then no file is written).
    private static func pickRegion(into url: URL) async -> Bool {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/screencapture")
        process.arguments = ["-i", "-x", "-o", url.path] // interactive, no shutter sound, no window shadow
        return await withCheckedContinuation { continuation in
            process.terminationHandler = { _ in continuation.resume(returning: true) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: false)
            }
        }
    }

    /// The document recognizer rebuilds paragraphs from wrapped lines, so the translator gets whole
    /// sentences instead of line fragments; paragraphs and list items come one per line.
    nonisolated private static func recognizeText(in url: URL) async -> String {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = true
        guard let document = try? await request.perform(on: url).first?.document else { return "" }
        return document.text.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// macOS shows its own prompt only the first time; after that the switch lives in System Settings.
    /// A granted permission takes effect after the app relaunches, which macOS offers to do.
    private static func requestPermission() {
        let askedKey = "requestedScreenCapture"
        if UserDefaults.standard.bool(forKey: askedKey) {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        } else {
            UserDefaults.standard.set(true, forKey: askedKey)
            CGRequestScreenCaptureAccess()
        }
    }
}
