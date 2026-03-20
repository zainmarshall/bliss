import AppKit

enum BlissSounds {
    static func playSuccess() {
        NSSound(named: NSSound.Name("Glass"))?.play()
    }

    static func playError() {
        NSSound(named: NSSound.Name("Basso"))?.play()
    }

    static func playMerge() {
        NSSound(named: NSSound.Name("Pop"))?.play()
    }

    static func playClick() {
        NSSound(named: NSSound.Name("Tink"))?.play()
    }
}
