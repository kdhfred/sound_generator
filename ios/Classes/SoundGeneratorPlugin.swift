import Flutter
import UIKit
import AudioKit

public class SwiftSoundGeneratorPlugin: NSObject, FlutterPlugin {
  var onChangeIsPlaying: BetterEventChannel?
  var onOneCycleDataHandler: BetterEventChannel?
  var sampleRate: Int = 48000
  var isPlaying: Bool = false

  // AudioKit components
  var oscillator: AKMorphingOscillator?
  var panner: AKPanner?
  var mixer: AKMixer?

  public static func register(with registrar: FlutterPluginRegistrar) {
    _ = SwiftSoundGeneratorPlugin(registrar: registrar)
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
      initializeAudioKit(call, result: result)

    case "release":
      releaseAudioKit(result: result)

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

  // Initialize AudioKit only when the `init` method is called
  private func initializeAudioKit(_ call: FlutterMethodCall, result: FlutterResult) {
    let args = call.arguments as! [String: Any]
    self.sampleRate = args["sampleRate"] as? Int ?? 48000

    self.oscillator = AKMorphingOscillator(waveformArray: [
      AKTable(.sine),
      AKTable(.square),
      AKTable(.triangle),
      AKTable(.sawtooth)
    ])
    self.panner = AKPanner(self.oscillator!, pan: 0.0)
    self.mixer = AKMixer(self.panner!)
    self.mixer?.volume = 1.0
    
    AKSettings.disableAVAudioSessionCategoryManagement = true
    AKSettings.disableAudioSessionDeactivationOnStop = true
    AKManager.output = self.mixer

    do {
      try AKManager.start()
      result(true)
    } catch {
      result(FlutterError(code: "init_error", message: "Unable to start AKManager", details: error.localizedDescription))
    }
  }

  // Release AudioKit resources
  private func releaseAudioKit(result: FlutterResult?) {
    if isPlaying {
      self.oscillator?.stop()
      self.isPlaying = false
      onChangeIsPlaying?.sendEvent(event: false)
    }
    
    do {
      if AKManager.engine.isRunning {
        self.oscillator?.detach()
        self.panner?.detach()
        self.mixer?.detach()
        try AKManager.stop()
      }
      
      self.oscillator = nil
      self.panner = nil
      self.mixer = nil
      
      result?(nil)
    } catch {
      result?(FlutterError(code: "release_error", message: "Unable to stop AKManager", details: error.localizedDescription))
    }
  }

  public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
    releaseAudioKit(result: nil)
    onChangeIsPlaying = nil
    onOneCycleDataHandler = nil
  }

  private func startPlaying(result: FlutterResult) {
    guard let oscillator = self.oscillator else {
      result(FlutterError(code: "not_initialized", message: "Sound generator not initialized", details: nil))
      return
    }
    oscillator.start()
    self.isPlaying = true
    onChangeIsPlaying?.sendEvent(event: true)
    result(nil)
  }

  private func stopPlaying(result: FlutterResult) {
    guard let oscillator = self.oscillator else {
      result(FlutterError(code: "not_initialized", message: "Sound generator not initialized", details: nil))
      return
    }
    oscillator.stop()
    self.isPlaying = false
    onChangeIsPlaying?.sendEvent(event: false)
    result(nil)
  }

  private func setFrequency(_ args: [String: Any], result: FlutterResult) {
    guard let oscillator = self.oscillator else {
      result(FlutterError(code: "not_initialized", message: "Sound generator not initialized", details: nil))
      return
    }
    oscillator.frequency = args["frequency"] as? Double ?? 400.0
    result(nil)
  }

  private func setWaveform(_ args: [String: Any], result: FlutterResult) {
    guard let oscillator = self.oscillator else {
      result(FlutterError(code: "not_initialized", message: "Sound generator not initialized", details: nil))
      return
    }
    let waveType = args["waveType"] as? String ?? "SINUSOIDAL"
    switch waveType {
    case "SINUSOIDAL":
      oscillator.index = 0
    case "SQUAREWAVE":
      oscillator.index = 1
    case "TRIANGLE":
      oscillator.index = 2
    case "SAWTOOTH":
      oscillator.index = 3
    default:
      oscillator.index = 0
    }
    result(nil)
  }

  private func setBalance(_ args: [String: Any], result: FlutterResult) {
    guard let panner = self.panner else {
      result(FlutterError(code: "not_initialized", message: "Sound generator not initialized", details: nil))
      return
    }
    panner.pan = args["balance"] as? Double ?? 0.0
    result(nil)
  }

  private func setVolume(_ args: [String: Any], result: FlutterResult) {
    guard let mixer = self.mixer else {
      result(FlutterError(code: "not_initialized", message: "Sound generator not initialized", details: nil))
      return
    }
    mixer.volume = args["volume"] as? Double ?? 1.0
    result(nil)
  }

  private func getVolume(result: FlutterResult) {
    guard let mixer = self.mixer else {
      result(FlutterError(code: "not_initialized", message: "Sound generator not initialized", details: nil))
      return
    }
    result(mixer.volume)
  }

  private func setDecibel(_ args: [String: Any], result: FlutterResult) {
    guard let mixer = self.mixer else {
      result(FlutterError(code: "not_initialized", message: "Sound generator not initialized", details: nil))
      return
    }
    mixer.volume = pow(10, args["decibel"] as? Double ?? 0.0 / 20.0)
    result(nil)
  }

  private func getDecibel(result: FlutterResult) {
    guard let mixer = self.mixer else {
      result(FlutterError(code: "not_initialized", message: "Sound generator not initialized", details: nil))
      return
    }
    result(mixer.volume)
  }

}
