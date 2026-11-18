import AVFoundation
import Foundation

// MARK: - Синтез WAV на лету (без файлов в бандле)

enum Synth {
    static func wavData(_ samples: [Float]) -> Data {
        var d = Data()
        let sr = 44100
        let n = samples.count
        func str(_ s: String) { d.append(s.data(using: .ascii)!) }
        func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        str("RIFF"); u32(UInt32(36 + n * 2)); str("WAVE"); str("fmt ")
        u32(16); u16(1); u16(1); u32(UInt32(sr)); u32(UInt32(sr * 2)); u16(2); u16(16)
        str("data"); u32(UInt32(n * 2))
        for s in samples {
            let clamped = Float(max(-1.0, min(1.0, Double(s))))
            var v = Int16(clamped * 32000)
            withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) }
        }
        return d
    }

    static func tone(f0: Double, f1: Double, dur: Double, vol: Double, decay: Double = 8) -> [Float] {
        let n = Int(dur * 44100)
        var out = [Float]()
        out.reserveCapacity(n)
        var phase = 0.0
        for i in 0..<n {
            let t = Double(i) / 44100
            let f = f0 + (f1 - f0) * (t / dur)
            phase += 2 * Double.pi * f / 44100
            let env = exp(-decay * t / dur)
            out.append(Float(sin(phase) * vol * env))
        }
        return out
    }

    static func noise(dur: Double, vol: Double) -> [Float] {
        let n = Int(dur * 44100)
        var out = [Float]()
        out.reserveCapacity(n)
        var last: Float = 0
        for i in 0..<n {
            let t = Double(i) / 44100
            let white = Float.random(in: -1...1)
            last = 0.7 * last + 0.3 * white
            let env = sin(Double.pi * t / dur)
            out.append(last * Float(vol) * Float(env))
        }
        return out
    }

    static func silence(_ dur: Double) -> [Float] {
        [Float](repeating: 0, count: Int(dur * 44100))
    }

    static func join(_ parts: [[Float]]) -> [Float] {
        parts.flatMap { $0 }
    }
}

// MARK: - Менеджер звуков

final class SoundManager {
    static let shared = SoundManager()
    private var players: [String: AVAudioPlayer] = [:]
    var isEnabled = UserDefaults.standard.object(forKey: "sfxEnabled") as? Bool ?? true

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        make(name: "click", samples: Synth.join([
            Synth.tone(f0: 2400, f1: 1800, dur: 0.035, vol: 0.5, decay: 10),
            Synth.noise(dur: 0.012, vol: 0.12)
        ]))
        make(name: "tap", samples: Synth.tone(f0: 1150, f1: 640, dur: 0.07, vol: 0.45, decay: 7))
        make(name: "tick", samples: Synth.join([
            Synth.noise(dur: 0.02, vol: 0.1),
            Synth.tone(f0: 3600, f1: 3200, dur: 0.02, vol: 0.2, decay: 9)
        ]))
        make(name: "pop", samples: Synth.tone(f0: 320, f1: 980, dur: 0.13, vol: 0.55, decay: 5))
        make(name: "success", samples: Synth.join([
            Synth.tone(f0: 660, f1: 660, dur: 0.1, vol: 0.4, decay: 6),
            Synth.tone(f0: 830, f1: 830, dur: 0.1, vol: 0.42, decay: 6),
            Synth.tone(f0: 1046, f1: 1046, dur: 0.22, vol: 0.45, decay: 6)
        ]))
        make(name: "error", samples: Synth.join([
            Synth.tone(f0: 220, f1: 150, dur: 0.3, vol: 0.5, decay: 4),
            Synth.tone(f0: 110, f1: 90, dur: 0.22, vol: 0.3, decay: 5)
        ]))
        make(name: "whoosh", samples: Synth.noise(dur: 0.5, vol: 0.5))
        make(name: "chime", samples: Synth.join([
            Synth.tone(f0: 523, f1: 523, dur: 0.14, vol: 0.4, decay: 5),
            Synth.tone(f0: 659, f1: 659, dur: 0.14, vol: 0.42, decay: 5),
            Synth.tone(f0: 784, f1: 784, dur: 0.14, vol: 0.44, decay: 5),
            Synth.tone(f0: 1046, f1: 1046, dur: 0.5, vol: 0.5, decay: 3)
        ]))
        make(name: "boot", samples: Synth.join([
            Synth.tone(f0: 392, f1: 392, dur: 0.16, vol: 0.4, decay: 5),
            Synth.tone(f0: 523, f1: 523, dur: 0.4, vol: 0.45, decay: 3)
        ]))
    }

    private func make(name: String, samples: [Float]) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sfx_" + name + ".wav")
        do {
            try Synth.wavData(samples).write(to: url)
            let p = try AVAudioPlayer(contentsOf: url)
            p.prepareToPlay()
            p.volume = 0.9
            players[name] = p
        } catch { }
    }

    func play(_ name: String) {
        guard isEnabled, let p = players[name] else { return }
        p.currentTime = 0
        p.play()
    }
}

// MARK: - Вибрация

import UIKit

enum Haptics {
    static func light() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium() { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func rigid() { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func selection() { UISelectionFeedbackGenerator().selectionChanged() }
    static func success() { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning() { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error() { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// MARK: - Фасад: звук + вибрация вместе

enum SFX {
    static func click() { SoundManager.shared.play("click"); Haptics.light() }
    static func tap() { SoundManager.shared.play("tap"); Haptics.light() }
    static func tick() { SoundManager.shared.play("tick") }
    static func pop() { SoundManager.shared.play("pop"); Haptics.rigid() }
    static func success() { SoundManager.shared.play("success"); Haptics.success() }
    static func error() { SoundManager.shared.play("error"); Haptics.error() }
    static func whoosh() { SoundManager.shared.play("whoosh") }
    static func chime() { SoundManager.shared.play("chime"); Haptics.success() }
    static func boot() { SoundManager.shared.play("boot"); Haptics.medium() }
}
