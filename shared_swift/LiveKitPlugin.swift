// Copyright 2024 LiveKit, Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import WebRTC
import flutter_webrtc

#if os(macOS)
import Cocoa
import FlutterMacOS
#else
import Flutter
import UIKit
#endif

public class LiveKitPlugin: NSObject, FlutterPlugin {

    var processers: Dictionary<Track, Visualizer> = [:]
    
    var binaryMessenger: FlutterBinaryMessenger?

    public static func register(with registrar: FlutterPluginRegistrar) {

        #if os(macOS)
        let messenger = registrar.messenger
        #else
        let messenger = registrar.messenger()
        #endif

        let channel = FlutterMethodChannel(name: "livekit_client", binaryMessenger: messenger)
        let instance = LiveKitPlugin()
        instance.binaryMessenger = messenger
        registrar.addMethodCallDelegate(instance, channel: channel)
    }

    #if !os(macOS)
    // https://developer.apple.com/documentation/avfaudio/avaudiosession/category
    let categoryMap: [String: AVAudioSession.Category] = [
        "ambient": .ambient,
        "multiRoute": .multiRoute,
        "playAndRecord": .playAndRecord,
        "playback": .playback,
        "record": .record,
        "soloAmbient": .soloAmbient
    ]

    // https://developer.apple.com/documentation/avfaudio/avaudiosession/categoryoptions
    let categoryOptionsMap: [String: AVAudioSession.CategoryOptions] = [
        "mixWithOthers": .mixWithOthers,
        "duckOthers": .duckOthers,
        "interruptSpokenAudioAndMixWithOthers": .interruptSpokenAudioAndMixWithOthers,
        "allowBluetooth": .allowBluetooth,
        "allowBluetoothA2DP": .allowBluetoothA2DP,
        "allowAirPlay": .allowAirPlay,
        "defaultToSpeaker": .defaultToSpeaker
        //        @available(iOS 14.5, *)
        //        "overrideMutedMicrophoneInterruption": .overrideMutedMicrophoneInterruption,
    ]

    // https://developer.apple.com/documentation/avfaudio/avaudiosession/mode
    let modeMap: [String: AVAudioSession.Mode] = [
        "default": .default,
        "gameChat": .gameChat,
        "measurement": .measurement,
        "moviePlayback": .moviePlayback,
        "spokenAudio": .spokenAudio,
        "videoChat": .videoChat,
        "videoRecording": .videoRecording,
        "voiceChat": .voiceChat,
        "voicePrompt": .voicePrompt
    ]

    private func categoryOptions(fromFlutter options: [String]) -> AVAudioSession.CategoryOptions {
        var result: AVAudioSession.CategoryOptions = []
        for option in categoryOptionsMap {
            if options.contains(option.key) {
                result.insert(option.value)
            }
        }
        return result
    }
    #endif
    
    public func handleStartAudioVisualizer(args: [String: Any?], result: @escaping FlutterResult) {
        let webrtc = FlutterWebRTCPlugin.sharedSingleton()
        
        let trackId = args["trackId"] as? String
        let barCount = args["barCount"] as? Int ?? 7
        let isCentered = args["isCentered"] as? Bool ?? true
        
        if let unwrappedTrackId = trackId {
            
            let localTrack = webrtc?.localTracks![unwrappedTrackId]
            if let audioTrack = localTrack as? LocalAudioTrack {
                let lkLocalTrack = LKLocalAudioTrack(name: unwrappedTrackId, track: audioTrack);
                let processor = Visualizer(track: lkLocalTrack,
                                               binaryMessenger: self.binaryMessenger!,
                                               bandCount: barCount,
                                               isCentered: isCentered)
                processers[lkLocalTrack] = processor
            }
             
            let track = webrtc?.remoteTrack(forId: unwrappedTrackId)
            if let audioTrack = track as? RTCAudioTrack {
                let lkRemoteTrack = LKRemoteAudioTrack(name: unwrappedTrackId, track: audioTrack);
                let processor = Visualizer(track: lkRemoteTrack,
                                               binaryMessenger: self.binaryMessenger!,
                                               bandCount: barCount,
                                               isCentered: isCentered)
                processers[lkRemoteTrack] = processor
            }
        }
        
        
        result(true)
    }
    
    public func handleStopAudioVisualizer(args: [String: Any?], result: @escaping FlutterResult) {
        let trackId = args["trackId"] as? String
        if let unwrappedTrackId = trackId {
            for key in processers.keys {
                if key.mediaTrack.trackId == unwrappedTrackId {
                    processers.removeValue(forKey: key)
                }
            }
        }
        result(true)
    }

    public func handleConfigureNativeAudio(args: [String: Any?], result: @escaping FlutterResult) {

        #if os(macOS)
        result(FlutterMethodNotImplemented)
        #else

        let configuration = RTCAudioSessionConfiguration.webRTC()

        // Category
        if let string = args["appleAudioCategory"] as? String,
           let category = categoryMap[string] {
            configuration.category = category.rawValue
            print("[LiveKit] Configuring category: ", configuration.category)
        }

        // CategoryOptions
        if let strings = args["appleAudioCategoryOptions"] as? [String] {
            configuration.categoryOptions = categoryOptions(fromFlutter: strings)
            print("[LiveKit] Configuring categoryOptions: ", strings)
        }

        // Mode
        if let string = args["appleAudioMode"] as? String,
           let mode = modeMap[string] {
            configuration.mode = mode.rawValue
            print("[LiveKit] Configuring mode: ", configuration.mode)
        }

        // get `RTCAudioSession` and lock
        let rtcSession = RTCAudioSession.sharedInstance()
        rtcSession.lockForConfiguration()

        var isLocked: Bool = true
        let unlock = {
            guard isLocked else {
                print("[LiveKit] not locked, ignoring unlock")
                return
            }
            rtcSession.unlockForConfiguration()
            isLocked = false
        }

        // always `unlock()` when exiting scope, calling multiple times has no side-effect
        defer {
            unlock()
        }

        do {
            try rtcSession.setConfiguration(configuration, active: true)
            // unlock here before configuring `AVAudioSession`
            // unlock()
            print("[LiveKit] RTCAudioSession Configure success")

            if let preferSpeakerOutput = args["preferSpeakerOutput"] as? Bool {
              try rtcSession.overrideOutputAudioPort(preferSpeakerOutput ? .speaker : .none)
            } else {
              let avSession = AVAudioSession.sharedInstance()
              if let availableInputs = avSession.availableInputs {
                  for input in availableInputs {
                      print("log: input: \(input.portType)")
                      if input.portType == .bluetoothHFP {
                          // Prefer Bluetooth if available
                          print("log: choose bluetooth")
                          try avSession.setPreferredInput(input)
                          result(true)
                      }
                  }
              }
              try avSession.overrideOutputAudioPort(.none)
            }
            result(true)
        } catch let error {
            print("[LiveKit] Configure audio error: ", error)
            result(FlutterError(code: "configure", message: error.localizedDescription, details: nil))
        }
        #endif
    }

    private static let processInfo = ProcessInfo()

    /// Returns os version as a string.
    /// format: `12.1`, `15.3.1`, `15.0.1`
    private static func osVersionString() -> String {
        let osVersion = processInfo.operatingSystemVersion
        var versions = [osVersion.majorVersion]
        if osVersion.minorVersion != 0 || osVersion.patchVersion != 0 {
            versions.append(osVersion.minorVersion)
        }
        if osVersion.patchVersion != 0 {
            versions.append(osVersion.patchVersion)
        }
        return versions.map({ String($0) }).joined(separator: ".")
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {

        guard let args = call.arguments as? [String: Any?] else {
            print("[LiveKit] arguments must be a dictionary")
            result(FlutterMethodNotImplemented)
            return
        }

        switch call.method {
        case "configureNativeAudio":
            handleConfigureNativeAudio(args: args, result: result)
        case "startVisualizer":
            handleStartAudioVisualizer(args: args, result: result)
        case "stopVisualizer":
            handleStopAudioVisualizer(args: args, result: result)
        case "osVersionString":
            result(LiveKitPlugin.osVersionString())
        default:
            print("[LiveKit] method not found: ", call.method)
            result(FlutterMethodNotImplemented)
        }
    }
}
