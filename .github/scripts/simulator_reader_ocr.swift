// Host-side inspection of original simulator PNGs. No application hooks.
import Foundation
import ImageIO
import Vision

guard CommandLine.arguments.count == 2,
      let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
  fatalError("Expected a simulator PNG")
}
let request = VNRecognizeTextRequest()
request.recognitionLevel = .accurate
request.recognitionLanguages = ["en-US"]
request.usesLanguageCorrection = false
request.minimumTextHeight = 0.003
try VNImageRequestHandler(cgImage: image).perform([request])
var deny: [String: Double]?
var zoom: String?
var zoomBounds: [String: Double]?
for observation in request.results ?? [] {
  guard let candidate = observation.topCandidates(1).first?.string else { continue }
  let text = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
  let normalized = text.lowercased().filter { $0.isLetter || $0.isNumber }
  let box = observation.boundingBox
  if normalized == "dontallow" {
    deny = ["x": Double(box.midX), "y": Double(1 - box.midY)]
  }
  if text.range(of: #"^\d{2,3}\s*[%％]$"#, options: .regularExpression) != nil {
    zoom = text
    zoomBounds = ["x": Double(box.midX), "y": Double(1 - box.midY)]
  }
}
var result: [String: Any] = ["width": image.width, "height": image.height]
if let deny { result["denyNotification"] = deny }
if let zoom { result["zoom"] = zoom }
if let zoomBounds { result["zoomBounds"] = zoomBounds }
let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
print(String(decoding: data, as: UTF8.self))
