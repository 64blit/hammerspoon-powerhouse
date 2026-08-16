// OCR helper for window_translator.lua
// Reads an image file path, performs Vision text recognition, prints JSON to stdout.
// Usage: ocr_helper <image_path> [comma_separated_langs]

import Foundation
import Vision
import AppKit

let args = CommandLine.arguments
guard args.count >= 2 else {
    FileHandle.standardError.write("usage: ocr_helper <image_path> [langs]\n".data(using: .utf8)!)
    exit(1)
}

let path = args[1]
let langs: [String] = args.count >= 3
    ? args[2].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    : []

guard let nsImg = NSImage(contentsOfFile: path),
      let cgImg = nsImg.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    FileHandle.standardError.write("cannot load image: \(path)\n".data(using: .utf8)!)
    exit(2)
}

let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
req.usesLanguageCorrection = true
if !langs.isEmpty { req.recognitionLanguages = langs }

let handler = VNImageRequestHandler(cgImage: cgImg, options: [:])
do {
    try handler.perform([req])
} catch {
    FileHandle.standardError.write("vision failed: \(error)\n".data(using: .utf8)!)
    exit(3)
}

let w = Double(cgImg.width)
let h = Double(cgImg.height)
var results: [[String: Any]] = []

for case let obs as VNRecognizedTextObservation in (req.results ?? []) {
    guard let top = obs.topCandidates(1).first else { continue }
    let text = top.string.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { continue }
    let bb = obs.boundingBox
    // Vision boundingBox: origin bottom-left, normalized 0..1
    let x = Double(bb.minX) * w
    let y = (1.0 - Double(bb.maxY)) * h
    let ww = Double(bb.width) * w
    let hh = Double(bb.height) * h
    results.append([
        "text": text,
        "confidence": Double(top.confidence),
        "x": x, "y": y, "w": ww, "h": hh
    ])
}

let data = try JSONSerialization.data(withJSONObject: results, options: [])
FileHandle.standardOutput.write(data)
