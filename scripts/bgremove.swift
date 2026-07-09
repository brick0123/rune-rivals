// 캐릭터 배경 제거(누끼) — Apple Vision 전경 마스크.
// 사용: swiftc bgremove.swift -o bgremove && ./bgremove <in.png> <out.png>
// 원본 크기 유지 + 배경 투명 PNG(RGBA) 출력.
import Foundation
import Vision
import CoreImage
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

func loadCGImage(_ path: String) -> CGImage? {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
    return img
}

let args = CommandLine.arguments
guard args.count == 3 else { FileHandle.standardError.write("usage: bgremove <in> <out>\n".data(using: .utf8)!); exit(2) }
let inPath = args[1], outPath = args[2]

guard let cg = loadCGImage(inPath) else {
    FileHandle.standardError.write("load fail: \(inPath)\n".data(using: .utf8)!); exit(1)
}

let handler = VNImageRequestHandler(cgImage: cg, options: [:])
let req = VNGenerateForegroundInstanceMaskRequest()

do {
    try handler.perform([req])
    guard let obs = req.results?.first else {
        FileHandle.standardError.write("no-foreground: \(inPath)\n".data(using: .utf8)!); exit(3)
    }
    let buffer = try obs.generateMaskedImage(ofInstances: obs.allInstances, from: handler, croppedToInstancesExtent: false)
    let ci = CIImage(cvPixelBuffer: buffer)
    let ctx = CIContext()
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    try ctx.writePNGRepresentation(of: ci, to: URL(fileURLWithPath: outPath), format: .RGBA8, colorSpace: cs)
    print("ok")
} catch {
    FileHandle.standardError.write("err \(inPath): \(error)\n".data(using: .utf8)!); exit(1)
}
