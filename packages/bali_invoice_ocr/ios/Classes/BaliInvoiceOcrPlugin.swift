import Flutter
import UIKit
import Vision

public class BaliInvoiceOcrPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "bali_invoice_ocr", binaryMessenger: registrar.messenger())
    let instance = BaliInvoiceOcrPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "recognizeImage" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard
      let arguments = call.arguments as? [String: Any],
      let imagePath = arguments["imagePath"] as? String,
      !imagePath.isEmpty
    else {
      result(FlutterError(code: "INVALID_IMAGE", message: "Image path is required", details: nil))
      return
    }

    DispatchQueue.global(qos: .userInitiated).async {
      guard let image = UIImage(contentsOfFile: imagePath), let cgImage = image.cgImage else {
        DispatchQueue.main.async {
          result(FlutterError(code: "INVALID_IMAGE", message: "Unable to open invoice image", details: nil))
        }
        return
      }

      var recognizedText = ""
      var recognitionError: Error?
      let request = VNRecognizeTextRequest { request, error in
        if let error = error {
          recognitionError = error
          return
        }
        let observations = request.results as? [VNRecognizedTextObservation] ?? []
        recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
      }
      request.recognitionLevel = .accurate
      request.usesLanguageCorrection = true
      request.recognitionLanguages = ["ru-RU", "en-US"]

      do {
        try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        if let error = recognitionError {
          throw error
        }
        DispatchQueue.main.async {
          result(recognizedText)
        }
      } catch {
        // Some older iOS language packs may not expose Russian to Vision.
        // Retry with the device's default supported language set rather than
        // failing the entire delivery workflow.
        recognizedText = ""
        recognitionError = nil
        let fallback = VNRecognizeTextRequest { request, requestError in
          if let requestError = requestError {
            recognitionError = requestError
            return
          }
          let observations = request.results as? [VNRecognizedTextObservation] ?? []
          recognizedText = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }
        fallback.recognitionLevel = .accurate
        fallback.usesLanguageCorrection = true
        do {
          try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([fallback])
          if let fallbackError = recognitionError { throw fallbackError }
          DispatchQueue.main.async { result(recognizedText) }
        } catch {
          DispatchQueue.main.async {
            result(FlutterError(code: "OCR_ERROR", message: error.localizedDescription, details: nil))
          }
        }
      }
    }
  }
}
