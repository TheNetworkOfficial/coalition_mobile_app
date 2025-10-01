import AVFoundation
import Flutter
import UIKit

private let channelName = "video_native"

final class VideoNative: NSObject {
  private static var shared: VideoNative?

  static func register(with messenger: FlutterBinaryMessenger) {
    if let existing = shared {
      existing.channel.setMethodCallHandler(nil)
    }
    let instance = VideoNative(messenger: messenger)
    shared = instance
  }

  private let channel: FlutterMethodChannel
  private let workQueue = DispatchQueue(label: "video_native.queue")
  private let fileManager = FileManager.default
  private var exportSession: AVAssetExportSession?

  private override init() {
    fatalError("Use register(with:) instead")
  }

  private init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    super.init()
    channel.setMethodCallHandler(handle)
  }

  deinit {
    channel.setMethodCallHandler(nil)
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "generateCoverImage":
      guard
        let args = call.arguments as? [String: Any],
        let filePath = args["filePath"] as? String,
        let seconds = args["seconds"] as? Double
      else {
        result(FlutterError(code: "bad_args", message: "Missing filePath or seconds", details: nil))
        return
      }

      workQueue.async {
        self.perform(result: result) {
          try self.generateCoverImage(filePath: filePath, seconds: seconds)
        }
      }

    case "exportEdits":
      guard
        let args = call.arguments as? [String: Any],
        let filePath = args["filePath"] as? String,
        let targetBitrate = args["targetBitrateBps"] as? Int
      else {
        result(FlutterError(code: "bad_args", message: "Missing export arguments", details: nil))
        return
      }

      NSLog("VideoNative(iOS): exportEdits called - filePath=\(filePath) targetBitrate=\(targetBitrate) rawTimeline=")

      // timelineJson may be sent as a JSON string or as a map.
      var timeline: [String: Any]? = nil
      if let t = args["timelineJson"] as? [String: Any] {
        timeline = t
      } else if let tstr = args["timelineJson"] as? String {
        if let data = tstr.data(using: .utf8) {
          timeline = (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any]
        }
      }

      guard timeline != nil else {
        result(FlutterError(code: "bad_args", message: "Missing export arguments (timeline)", details: nil))
        return
      }

      workQueue.async {
        self.perform(result: result) {
          NSLog("VideoNative(iOS): exportEdits starting for filePath=\(filePath), output will be temporary file")
          let out = try self.exportEdits(filePath: filePath, timeline: timeline, targetBitrate: targetBitrate)
          NSLog("VideoNative(iOS): exportEdits completed, output=\(out)")
          return out
        }
      }

    case "cancelExport":
      workQueue.async {
        self.exportSession?.cancelExport()
        self.exportSession = nil
        DispatchQueue.main.async {
          result(nil)
        }
      }

    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func perform(result: @escaping FlutterResult, block: () throws -> String) {
    do {
      let value = try block()
      DispatchQueue.main.async {
        result(value)
      }
    } catch {
      DispatchQueue.main.async {
        result(FlutterError(code: "error", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func generateCoverImage(filePath: String, seconds: Double) throws -> String {
    let asset = AVURLAsset(url: URL(fileURLWithPath: filePath))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true

    let time = CMTime(seconds: seconds, preferredTimescale: 600)
    let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
    let image = UIImage(cgImage: cgImage)

    guard let data = image.pngData() else {
      throw NSError(domain: "video_native", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to encode PNG"])
    }

    let outputURL = try makeTemporaryURL(prefix: "cover_", ext: "png")
    try data.write(to: outputURL, options: .atomic)
    return outputURL.path
  }

  private func exportEdits(filePath: String, timeline: [String: Any], targetBitrate: Int) throws -> String {
    let url = URL(fileURLWithPath: filePath)
    let asset = AVURLAsset(url: url)

    let preset = selectPreset(for: asset, targetBitrate: targetBitrate)
    guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
      throw NSError(domain: "video_native", code: -2, userInfo: [NSLocalizedDescriptionKey: "Unable to create export session"])
    }

    let outputURL = try makeTemporaryURL(prefix: "export_", ext: "mp4")
    if fileManager.fileExists(atPath: outputURL.path) {
      try fileManager.removeItem(at: outputURL)
    }

    session.outputURL = outputURL
    session.outputFileType = .mp4

    if let timeRange = buildTimeRange(from: timeline, duration: asset.duration) {
      session.timeRange = timeRange
    }

    if let composition = buildVideoComposition(asset: asset, timeline: timeline) {
      session.videoComposition = composition
    }

    exportSession?.cancelExport()
    exportSession = session

    let semaphore = DispatchSemaphore(value: 0)
    session.exportAsynchronously {
      semaphore.signal()
    }
    semaphore.wait()

    defer { exportSession = nil }

    if let error = session.error {
      throw error
    }

    guard session.status == .completed else {
      throw NSError(domain: "video_native", code: -3, userInfo: [NSLocalizedDescriptionKey: "Export did not complete"])
    }

    return outputURL.path
  }

  private func selectPreset(for asset: AVAsset, targetBitrate: Int) -> String {
    let compatible = AVAssetExportSession.exportPresets(compatibleWith: asset)
    if targetBitrate >= 5_000_000, compatible.contains(AVAssetExportPreset1920x1080) {
      return AVAssetExportPreset1920x1080
    }
    if compatible.contains(AVAssetExportPreset1280x720) {
      return AVAssetExportPreset1280x720
    }
    return compatible.first ?? AVAssetExportPresetMediumQuality
  }

  private func buildTimeRange(from timeline: [String: Any], duration: CMTime) -> CMTimeRange? {
    guard let trim = timeline["trim"] as? [String: Any] else {
      return nil
    }

    let startSeconds = (trim["startSeconds"] as? NSNumber)?.doubleValue ?? 0
    let endSeconds = (trim["endSeconds"] as? NSNumber)?.doubleValue ?? duration.seconds

    let start = CMTime(seconds: startSeconds, preferredTimescale: 600)
    let end = CMTime(seconds: endSeconds, preferredTimescale: 600)
    let clampedEnd = end.isValid && end <= duration ? end : duration
    let effectiveStart = start.isValid && start >= .zero ? start : .zero
    if clampedEnd <= effectiveStart {
      return nil
    }
    return CMTimeRange(start: effectiveStart, end: clampedEnd)
  }

  private func buildVideoComposition(asset: AVAsset, timeline: [String: Any]) -> AVMutableVideoComposition? {
    guard let track = asset.tracks(withMediaType: .video).first else {
      return nil
    }

    let composition = AVMutableVideoComposition()
    let instruction = AVMutableVideoCompositionInstruction()
    instruction.timeRange = CMTimeRange(start: .zero, duration: asset.duration)

    let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
    var transform = track.preferredTransform

    if let scale = timeline["scale"] as? [String: Any] {
      let sx = (scale["scaleX"] as? NSNumber)?.doubleValue
        ?? (scale["x"] as? NSNumber)?.doubleValue
        ?? (scale["width"] as? NSNumber)?.doubleValue
        ?? 1.0
      let sy = (scale["scaleY"] as? NSNumber)?.doubleValue
        ?? (scale["y"] as? NSNumber)?.doubleValue
        ?? (scale["height"] as? NSNumber)?.doubleValue
        ?? 1.0
      let rotationDegrees = (scale["rotationDegrees"] as? NSNumber)?.doubleValue ?? 0
      let rotation = CGFloat(rotationDegrees * .pi / 180.0)

      transform = transform.concatenating(CGAffineTransform(scaleX: CGFloat(sx), y: CGFloat(sy)))
      if rotationDegrees != 0 {
        transform = transform.concatenating(CGAffineTransform(rotationAngle: rotation))
      }
    }

    layerInstruction.setTransform(transform, at: .zero)

    var renderSize = track.naturalSize

    if let crop = timeline["crop"] as? [String: Any] {
      let left = CGFloat((crop["left"] as? NSNumber)?.doubleValue ?? 0)
      let top = CGFloat((crop["top"] as? NSNumber)?.doubleValue ?? 0)
      let right = CGFloat((crop["right"] as? NSNumber)?.doubleValue ?? 1)
      let bottom = CGFloat((crop["bottom"] as? NSNumber)?.doubleValue ?? 1)

      let width = max((right - left) * track.naturalSize.width, 1)
      let height = max((bottom - top) * track.naturalSize.height, 1)
      let cropRect = CGRect(
        x: left * track.naturalSize.width,
        y: top * track.naturalSize.height,
        width: width,
        height: height
      )
      layerInstruction.setCropRectangle(cropRect, at: .zero)
      renderSize = CGSize(width: width, height: height)
    }

    composition.renderSize = renderSize
    let frameRate = track.nominalFrameRate > 0 ? track.nominalFrameRate : 30
    composition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(frameRate))
    instruction.layerInstructions = [layerInstruction]
    composition.instructions = [instruction]

    return composition
  }

  private func makeTemporaryURL(prefix: String, ext: String) throws -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("video_native", isDirectory: true)
    if !fileManager.fileExists(atPath: directory.path) {
      try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    return directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(ext)
  }
}
