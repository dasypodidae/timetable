//© 2020 dasypodidae.

import SwiftUI
import Foundation
import AVKit

final class MiniPlayer {
    private var avPlayer: AVPlayer? = nil
    private var observation: NSKeyValueObservation? = nil
    private weak var timeoutTimer: Timer? = nil
    static let timeoutInterval: TimeInterval = 7
    
    deinit {
        clear()
    }
    func clear() {
        clearTimeoutTimer()
        observation = nil
        avPlayer = nil
    }
    func clearTimeoutTimer() {
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }
    
    
    func resetAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: AVAudioSession.Mode.default, options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP, .allowAirPlay])
            try session.setActive(true)
            
        }
    }
    
    enum PlayingState {
        case playing
        case paused(Error?)
        case err(Error)
        case timeout
        case invalidURL
    }
    
    func play(_ urlString: String, block: @escaping (PlayingState) -> Void) {
        
        clear()
        
        do {
            try resetAudioSession()
            
        } catch {
            block(.err(error))
            return
        }
        
        guard let url = URL(string: urlString) else {
            block(.invalidURL)
            return
        }
        
        
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(Self.timeoutInterval), repeats: false, block: { [weak self] _ in
            self?.clearTimeoutTimer()
            block(.timeout)
        })
        
        let newPlayer = AVPlayer(url: url)
        
        observation = newPlayer.observe(\.timeControlStatus, changeHandler: { [weak self] (player, change) in
            DispatchQueue.main.async {
                switch player.timeControlStatus {
                case .paused:
                    self?.clearTimeoutTimer()
                    block(.paused(player.error))
                    break
                case .waitingToPlayAtSpecifiedRate:
                    break
                case .playing:
                    self?.clearTimeoutTimer()
                    block(.playing)
                    break
                @unknown default:
                    fatalError("\(Self.self).timeControlStatus")
                }
            }
        })
        
        newPlayer.play()
        avPlayer = newPlayer
    }
    
}

final class RadioPlayer: ObservableObject {
    static let shared = RadioPlayer()
    
    private let player = MiniPlayer()
    
    @Published var surl: String? = nil
    @Published var isBuffering: Bool = false
    
    func togglePlay(_ program: RadioProgram) {
        if (surl != program.surl) {
            withAnimation {
                play(program)
            }
        } else {
            stop()
        }
    }
    
    func play(_ program: RadioProgram) {
        let newURL = program.surl
        guard surl != newURL else {
            return
        }
        surl = newURL
        isBuffering = true
        player.play(program.m3uURL) { state in
            switch state {
            case .playing:
                withAnimation {
                    self.isBuffering = false
                }
                return
            default:
                break
            }
            self.stop()
        }
    }
    func stop() {
        withAnimation {
            player.clear()
            surl = nil
            isBuffering = false
        }
    }
}


extension RadioPlayer {
    
    func buttonImage(_ surl: String?, enabled: Bool = true) -> some View {
        HStack {
            if (self.surl == surl) {
                if isBuffering {
                    Image(systemName: "stop")
                        .foregroundColor(.yellow)
                } else {
                    Image(systemName: "stop.fill")
                }
            } else {
                if enabled {
                    Image(systemName: "play.fill")
                } else {
                    Image(systemName: "play.slash.fill")
                }
            }
        }
    }
    
    struct StopButton: View {
        @ObservedObject var player: RadioPlayer
        var body: some View {
            Button(action: {
                self.player.stop()
            }) {
                player.buttonImage(player.surl)
            }
            .disabled((player.surl == nil))
        }
    }
    
}
