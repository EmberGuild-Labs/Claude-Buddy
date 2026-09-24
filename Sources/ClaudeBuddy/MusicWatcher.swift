import AppKit

/// Knows whether Spotify or Apple Music is playing, from the distributed notifications both
/// apps post on every play/pause/track change. No permissions needed.
///
/// Those notifications don't carry the song's tempo, so each track gets a steady made-up BPM
/// (derived from its name, so the same song always grooves the same way).
final class MusicWatcher {
    private(set) var isPlaying = false
    private(set) var track: String?
    private(set) var bpm: Double = 112

    private static let notifications = [
        "com.spotify.client.PlaybackStateChanged",
        "com.apple.Music.playerInfo",
        "com.apple.iTunes.playerInfo",
    ]
    private static let playerBundleIDs: Set = ["com.spotify.client", "com.apple.Music", "com.apple.iTunes"]

    init() {
        let center = DistributedNotificationCenter.default()
        for name in Self.notifications {
            // Background apps get distributed notifications suspended by default.
            center.addObserver(self, selector: #selector(changed(_:)), name: .init(name), object: nil,
                               suspensionBehavior: .deliverImmediately)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appQuit(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    /// For the menu's demo: pretend a song is playing for a while.
    func simulate(seconds: TimeInterval) {
        isPlaying = true
        track = "Demo Beat"
        bpm = 120
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard self?.track == "Demo Beat" else { return }
            self?.isPlaying = false
            self?.track = nil
        }
    }

    @objc private func changed(_ note: Notification) {
        let info = note.userInfo ?? [:]
        isPlaying = (info["Player State"] as? String) == "Playing"
        let name = info["Name"] as? String
        let artist = info["Artist"] as? String
        track = [name, artist].compactMap { $0 }.joined(separator: " — ")
        if track?.isEmpty == true { track = nil }
        let seed = (name ?? "").unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        bpm = 96 + Double(seed % 37)
    }

    @objc private func appQuit(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        if let id = app?.bundleIdentifier, Self.playerBundleIDs.contains(id) {
            isPlaying = false
            track = nil
        }
    }
}
