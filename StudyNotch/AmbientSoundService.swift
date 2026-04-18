import Foundation
import AVFoundation
import Observation

enum AmbientSoundType: String, CaseIterable, Identifiable {
    case rain    = "Rain"
    case cafe    = "Cafe"
    case library = "Library"
    case forest  = "Forest"
    case none    = "None"
    
    var id: String { self.rawValue }
    
    var url: URL? {
        switch self {
        case .rain:    return URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3") // Placeholder
        case .cafe:    return URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3")
        case .library: return URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3")
        case .forest:  return URL(string: "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-4.mp3")
        case .none:    return nil
        }
    }
}

@Observable
final class AmbientSoundService {
    static let shared = AmbientSoundService()
    
    var currentSound: AmbientSoundType = .none
    var isPlaying: Bool = false
    var volume: Float = 0.5 {
        didSet { player?.volume = volume }
    }
    
    private var player: AVPlayer?
    private var looper: AVPlayerLooper?
    private var queuePlayer: AVQueuePlayer?
    
    func toggle(_ sound: AmbientSoundType) {
        if currentSound == sound && isPlaying {
            stop()
        } else {
            play(sound)
        }
    }
    
    func play(_ sound: AmbientSoundType) {
        stop()
        guard let url = sound.url else { return }
        
        currentSound = sound
        let asset = AVAsset(url: url)
        let item  = AVPlayerItem(asset: asset)
        
        queuePlayer = AVQueuePlayer(playerItem: item)
        looper = AVPlayerLooper(player: queuePlayer!, templateItem: item)
        
        queuePlayer?.volume = volume
        queuePlayer?.play()
        isPlaying = true
    }
    
    func stop() {
        queuePlayer?.pause()
        queuePlayer = nil
        looper = nil
        currentSound = .none
        isPlaying = false
    }
}
