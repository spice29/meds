import Foundation
import AVFoundation
import AudioToolbox

// نغمات التذكير تتولّد داخل التطبيق نفسه (بدون ملفات صوت خارجية)

enum NotifSound: String, CaseIterable, Codable, Identifiable {
    case system, chime, bell, dingdong, gentle, alert
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "صوت النظام"
        case .chime: return "رنّة ناعمة"
        case .bell: return "جرس"
        case .dingdong: return "دنق دونق"
        case .gentle: return "هادئة"
        case .alert: return "تنبيه قوي"
        }
    }

    var fileName: String? {
        self == .system ? nil : "jorati_v1_\(rawValue).wav"
    }
}

struct Tone {
    let freq: Double
    let start: Double
    let dur: Double
    let amp: Double
}

enum SoundLibrary {
    static let rate = 44100.0

    static func tones(for s: NotifSound) -> [Tone] {
        switch s {
        case .system:
            return []
        case .chime:
            return [Tone(freq: 1046.5, start: 0.00, dur: 0.7, amp: 0.45),
                    Tone(freq: 1318.5, start: 0.18, dur: 0.7, amp: 0.45),
                    Tone(freq: 1568.0, start: 0.36, dur: 1.0, amp: 0.45)]
        case .bell:
            return [Tone(freq: 880.0, start: 0.0, dur: 1.9, amp: 0.6)]
        case .dingdong:
            return [Tone(freq: 987.8, start: 0.00, dur: 0.8, amp: 0.55),
                    Tone(freq: 783.99, start: 0.45, dur: 1.1, amp: 0.55)]
        case .gentle:
            return [Tone(freq: 523.25, start: 0.00, dur: 1.3, amp: 0.4),
                    Tone(freq: 659.25, start: 0.25, dur: 1.3, amp: 0.35)]
        case .alert:
            return [Tone(freq: 1000.0, start: 0.00, dur: 0.18, amp: 0.55),
                    Tone(freq: 1000.0, start: 0.28, dur: 0.18, amp: 0.55),
                    Tone(freq: 1000.0, start: 0.56, dur: 0.18, amp: 0.55),
                    Tone(freq: 1000.0, start: 0.84, dur: 0.30, amp: 0.55)]
        }
    }

    static func wavData(for sound: NotifSound) -> Data {
        let list = tones(for: sound)
        let total = (list.map { $0.start + $0.dur }.max() ?? 0.5) + 0.05
        let n = Int(total * rate)
        var samples = [Float](repeating: 0, count: n)

        for t in list {
            let s0 = Int(t.start * rate)
            let len = Int(t.dur * rate)
            for i in 0..<len {
                let idx = s0 + i
                if idx >= n { break }
                let time = Double(i) / rate
                let attack = min(1.0, time / 0.005)
                var decay: Double
                if sound == .alert {
                    decay = time < t.dur - 0.02 ? 1.0 : max(0.0, (t.dur - time) / 0.02)
                } else {
                    decay = exp(-3.2 * time / t.dur)
                }
                var v = sin(2.0 * Double.pi * t.freq * time)
                v += 0.35 * sin(2.0 * Double.pi * t.freq * 2.0 * time) * exp(-5.0 * time / t.dur)
                if sound == .bell {
                    v += 0.25 * sin(2.0 * Double.pi * t.freq * 2.76 * time) * exp(-4.0 * time / t.dur)
                }
                samples[idx] += Float(v * attack * decay * t.amp)
            }
        }
        return encodeWAV(samples)
    }

    private static func encodeWAV(_ samples: [Float]) -> Data {
        var data = Data()
        let byteRate = Int(rate) * 2
        let dataSize = samples.count * 2

        func u32(_ v: Int) {
            var x = UInt32(v).littleEndian
            data.append(Data(bytes: &x, count: 4))
        }
        func u16(_ v: Int) {
            var x = UInt16(v).littleEndian
            data.append(Data(bytes: &x, count: 2))
        }

        data.append("RIFF".data(using: .ascii)!)
        u32(36 + dataSize)
        data.append("WAVE".data(using: .ascii)!)
        data.append("fmt ".data(using: .ascii)!)
        u32(16); u16(1); u16(1); u32(Int(rate)); u32(byteRate); u16(2); u16(16)
        data.append("data".data(using: .ascii)!)
        u32(dataSize)
        for s in samples {
            let c = max(-1.0, min(1.0, s))
            var x = Int16(c * 32767).littleEndian
            data.append(Data(bytes: &x, count: 2))
        }
        return data
    }

    private static var soundsDir: URL? {
        guard let lib = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else {
            return nil
        }
        return lib.appendingPathComponent("Sounds", isDirectory: true)
    }

    /// ينشئ ملفات النغمات في Library/Sounds (المكان اللي يقرأ منه نظام الإشعارات)
    static func installAll() {
        guard let dir = soundsDir else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        for s in NotifSound.allCases {
            guard let name = s.fileName else { continue }
            let url = dir.appendingPathComponent(name)
            if !fm.fileExists(atPath: url.path) {
                try? wavData(for: s).write(to: url)
            }
        }
    }

    static func url(for s: NotifSound) -> URL? {
        guard let name = s.fileName, let dir = soundsDir else { return nil }
        return dir.appendingPathComponent(name)
    }
}

@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    private var player: AVAudioPlayer?

    func preview(_ s: NotifSound) {
        guard let url = SoundLibrary.url(for: s) else {
            AudioServicesPlaySystemSound(1007)
            return
        }
        try? AVAudioSession.sharedInstance().setCategory(.playback)
        try? AVAudioSession.sharedInstance().setActive(true)
        player = try? AVAudioPlayer(contentsOf: url)
        player?.play()
    }
}
