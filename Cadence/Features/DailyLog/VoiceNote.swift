import SwiftUI
import AVFoundation
import OSLog

// Records a single voice note to a temp .m4a file. UI-observable so the record
// button can reflect state. Actual capture requires a real device/mic for full
// verification; it compiles and drives the permission flow in the simulator.
@MainActor
@Observable
final class AudioRecorder {
    private static let log = Logger(subsystem: "com.carpecadence", category: "AudioRecorder")
    private var recorder: AVAudioRecorder?
    private var fileURL: URL?
    private(set) var isRecording = false

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    @discardableResult
    func start() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("voice-\(UUID().uuidString).m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ]
            let recorder = try AVAudioRecorder(url: url, settings: settings)
            guard recorder.record() else { return false }
            self.recorder = recorder
            self.fileURL = url
            isRecording = true
            return true
        } catch {
            Self.log.error("Failed to start recording: \(error.localizedDescription)")
            return false
        }
    }

    // Stops recording and returns the finished file URL (nil if not recording).
    func stop() -> URL? {
        recorder?.stop()
        recorder = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false)
        let url = fileURL
        fileURL = nil
        return url
    }
}

// Owns an AVAudioPlayer and tracks play/stop state, resetting when playback ends.
@MainActor
@Observable
final class AudioPlayback: NSObject, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private(set) var isPlaying = false

    func toggle(url: URL) {
        if isPlaying { stop(); return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            guard player.play() else { return }
            self.player = player
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.stop() }
    }
}

// A reusable play/stop button for a recorded voice note.
struct AudioPlaybackButton: View {
    let url: URL
    @State private var playback = AudioPlayback()

    var body: some View {
        Button {
            playback.toggle(url: url)
        } label: {
            Image(systemName: playback.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                .font(.title2)
                .foregroundStyle(CadenceColor.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(playback.isPlaying ? "Stop voice note" : "Play voice note")
        .onDisappear { playback.stop() }
    }
}
