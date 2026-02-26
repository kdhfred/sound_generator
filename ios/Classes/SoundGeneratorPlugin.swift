import Flutter
import UIKit
import AVFoundation

public class SwiftSoundGeneratorPlugin: NSObject, FlutterPlugin {
  private static var instance: SwiftSoundGeneratorPlugin?
  var onChangeIsPlaying: BetterEventChannel?
  var onOneCycleDataHandler: BetterEventChannel?
  var sampleRate: Int = 48000
  var isPlaying: Bool = false

  // AVAudioEngine components (replaces AudioKit)
  private var engine: AVAudioEngine?
  private var sourceNode: AVAudioSourceNode?

  // Oscillator state (accessed from audio render thread)
  private var frequency: Double = 440.0
  private var volume: Double = 1.0
  private var pan: Double = 0.0 // -1.0 to 1.0
  private var waveformIndex: Int = 0 // 0=sine, 1=square, 2=triangle, 3=sawtooth
  private var phase: Double = 0.0

  public static func register(with registrar: FlutterPluginRegistrar) {
    if let existingInstance = instance {
      existingInstance.releaseEngine(result: nil)
      existingInstance.onChangeIsPlaying = nil
      existingInstance.onOneCycleDataHandler = nil
    }
    instance = SwiftSoundGeneratorPlugin(registrar: registrar)
  }

  public init(registrar: FlutterPluginRegistrar) {
    super.init()
    let methodChannel = FlutterMethodChannel(name: "sound_generator", binaryMessenger: registrar.messenger())
    self.onChangeIsPlaying = BetterEventChannel(name: "io.github.mertguner.sound_generator/onChangeIsPlaying", messenger: registrar.messenger())
    self.onOneCycleDataHandler = BetterEventChannel(name: "io.github.mertguner.sound_generator/onOneCycleDataHandler", messenger: registrar.messenger())
    registrar.addMethodCallDelegate(self, channel: methodChannel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getPlatformVersion":
      result("iOS " + UIDevice.current.systemVersion)

    case "init":
      initializeEngine(call, result: result)

    case "release":
      releaseEngine(result: result)

    case "play":
      startPlaying(result: result)

    case "stop":
      stopPlaying(result: result)

    case "setFrequency":
      let args = call.arguments as! [String: Any]
      setFrequency(args, result: result)

    case "setWaveform":
      let args = call.arguments as! [String: Any]
      setWaveform(args, result: result)

    case "setBalance":
      let args = call.arguments as! [String: Any]
      setBalance(args, result: result)

    case "setVolume":
      let args = call.arguments as! [String: Any]
      setVolume(args, result: result)

    case "setDecibel":
      let args = call.arguments as! [String: Any]
      setDecibel(args, result: result)

    case "getDecibel":
      getDecibel(result: result)

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Waveform generation

  private func generateSample(phase: Double) -> Double {
    switch waveformIndex {
    case 0: // Sine
      return sin(phase * 2.0 * .pi)
    case 1: // Square
      return phase < 0.5 ? 1.0 : -1.0
    case 2: // Triangle
      if phase < 0.25 {
        return phase * 4.0
      } else if phase < 0.75 {
        return 2.0 - phase * 4.0
      } else {
        return phase * 4.0 - 4.0
      }
    case 3: // Sawtooth
      return 2.0 * phase - 1.0
    default:
      return sin(phase * 2.0 * .pi)
    }
  }

  // MARK: - Engine lifecycle

  private func initializeEngine(_ call: FlutterMethodCall, result: FlutterResult) {
    let args = call.arguments as! [String: Any]
    self.sampleRate = args["sampleRate"] as? Int ?? 48000

    // Clean up any existing engine
    if let engine = self.engine, engine.isRunning {
      engine.stop()
    }
    self.sourceNode = nil
    self.engine = nil
    self.phase = 0.0

    // Only store sampleRate here. The actual AVAudioEngine and AVAudioSession
    // are created lazily in ensureEngine(), called from startPlaying().
    result(true)
  }

  /// Creates the AVAudioEngine and AVAudioSession if not already running.
  private func ensureEngine() throws {
    if let engine = self.engine, engine.isRunning { return }

    // Clean up stale engine if it exists but isn't running
    if let sourceNode = self.sourceNode, let engine = self.engine {
      engine.detach(sourceNode)
    }
    self.sourceNode = nil
    self.engine = nil
    self.phase = 0.0

    let engine = AVAudioEngine()
    let sampleRate = Double(self.sampleRate)

    let sourceNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
      guard let self = self else { return noErr }

      let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
      let freq = self.frequency
      let vol = self.volume
      let pan = self.pan
      var currentPhase = self.phase

      let phaseIncrement = freq / sampleRate

      for frame in 0..<Int(frameCount) {
        let sample = self.generateSample(phase: currentPhase) * vol

        // Stereo panning: equal-power panning
        let leftGain = cos((pan + 1.0) * .pi / 4.0)
        let rightGain = sin((pan + 1.0) * .pi / 4.0)

        // Write to all channels (typically stereo)
        for bufferIndex in 0..<ablPointer.count {
          let buffer = ablPointer[bufferIndex]
          let frames = buffer.mData!.assumingMemoryBound(to: Float32.self)
          if ablPointer.count >= 2 {
            // Stereo: apply panning
            frames[frame] = Float32(sample * (bufferIndex == 0 ? leftGain : rightGain))
          } else {
            // Mono
            frames[frame] = Float32(sample)
          }
        }

        currentPhase += phaseIncrement
        if currentPhase >= 1.0 {
          currentPhase -= 1.0
        }
      }

      self.phase = currentPhase
      return noErr
    }

    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!

    engine.attach(sourceNode)
    engine.connect(sourceNode, to: engine.mainMixerNode, format: format)
    engine.mainMixerNode.outputVolume = 0

    self.sourceNode = sourceNode
    self.engine = engine

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
    try session.setActive(true)
    try engine.start()
  }

  private func releaseEngine(result: FlutterResult?) {
    if isPlaying {
      self.engine?.mainMixerNode.outputVolume = 0
      self.isPlaying = false
      onChangeIsPlaying?.sendEvent(event: false)
    }

    if let engine = self.engine, engine.isRunning {
      engine.stop()
    }

    if let sourceNode = self.sourceNode, let engine = self.engine {
      engine.detach(sourceNode)
    }

    self.sourceNode = nil
    self.engine = nil
    self.phase = 0.0

    result?(nil)
  }

  private func startPlaying(result: FlutterResult) {
    do {
      try ensureEngine()
    } catch {
      result(FlutterError(code: "engine_error", message: "Unable to start audio engine", details: error.localizedDescription))
      return
    }
    self.engine?.mainMixerNode.outputVolume = Float(self.volume)
    self.isPlaying = true
    onChangeIsPlaying?.sendEvent(event: true)
    result(nil)
  }

  private func stopPlaying(result: FlutterResult) {
    self.engine?.mainMixerNode.outputVolume = 0
    self.isPlaying = false
    onChangeIsPlaying?.sendEvent(event: false)
    result(nil)
  }

  private func setFrequency(_ args: [String: Any], result: FlutterResult) {
    self.frequency = args["frequency"] as? Double ?? 400.0
    result(nil)
  }

  private func setWaveform(_ args: [String: Any], result: FlutterResult) {
    let waveType = args["waveType"] as? String ?? "SINUSOIDAL"
    switch waveType {
    case "SINUSOIDAL":
      waveformIndex = 0
    case "SQUAREWAVE":
      waveformIndex = 1
    case "TRIANGLE":
      waveformIndex = 2
    case "SAWTOOTH":
      waveformIndex = 3
    default:
      waveformIndex = 0
    }
    result(nil)
  }

  private func setBalance(_ args: [String: Any], result: FlutterResult) {
    self.pan = args["balance"] as? Double ?? 0.0
    result(nil)
  }

  private func setVolume(_ args: [String: Any], result: FlutterResult) {
    self.volume = args["volume"] as? Double ?? 1.0
    if isPlaying {
      self.engine?.mainMixerNode.outputVolume = Float(self.volume)
    }
    result(nil)
  }

  private func getVolume(result: FlutterResult) {
    result(self.volume)
  }

  private func setDecibel(_ args: [String: Any], result: FlutterResult) {
    self.volume = pow(10, (args["decibel"] as? Double ?? 0.0) / 20.0)
    if isPlaying {
      self.engine?.mainMixerNode.outputVolume = Float(self.volume)
    }
    result(nil)
  }

  private func getDecibel(result: FlutterResult) {
    result(self.volume)
  }
}
