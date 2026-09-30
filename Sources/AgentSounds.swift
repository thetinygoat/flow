import AppKit

/// Plays agent sounds. A sound still playing starts over rather than queueing
/// another after it.
final class AgentSounds {
    private var sounds: [AgentSound: NSSound] = [:]
    private var throttle = AgentSoundThrottle()
    private var isSilenced = false

    func play(_ sound: AgentSound) {
        guard !isSilenced, throttle.allows(sound, at: Date()),
              let player = sounds[sound] ?? NSSound(named: sound.name) else { return }
        sounds[sound] = player
        player.stop()
        player.play()
    }

    /// For quitting, when a sound would outlive the app or be cut off.
    func silence() {
        isSilenced = true
        sounds.values.forEach { $0.stop() }
    }
}
