//
//  StorageManager.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/4/25.
//

import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

public enum StorageError: Error {
    case cannotCreateDirectory(URL)
    case imageWriteFailed(URL)
    case depthWriteFailed(URL)
    case confidenceWriteFailed(URL)
    case jsonWriteFailed(URL)
    case fileMissing(URL)
    case imageReadFailed(URL)
    case depthReadFailed(URL)
    case confidenceReadFailed(URL)
    case jsonReadFailed(URL)
}

final class StorageManager {
    public static let shared = StorageManager()
    public let baseURL: URL  // Base directory
    public var vignettesURL: URL {
        baseURL.appendingPathComponent("Vignettes", isDirectory: true)
    }
    public init() {
        self.baseURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    }
    
    
    // MARK: Relative/absolute path utilities
    func relativePath(for child: URL, base: URL) -> String {
        child.path.replacingOccurrences(of: base.path + "/", with: "")
    }
    func resolve(relative: String, base: URL) -> URL {
        base.appendingPathComponent(relative)
    }
    
    public func folderURL(for id: UUID) -> URL {
        vignettesURL.appendingPathComponent(id.uuidString, isDirectory: true)
    }
    
    
    // MARK: Save / Load APIs
    
    // Save a vignette. Save its json, rgb, depth, (ply)
    @discardableResult
    public func save(vignette: SpatialVignette) throws -> VignetteData {
        // Ensure folders
        try ensureDirectory(vignettesURL)
        let dir = folderURL(for: vignette.id)
        try ensureDirectory(dir)
        
        // get vignette data
        let data = vignette.toVignetteData()
        
        // Save rgb image
        let rgbURL = dir.appendingPathComponent(data.paths.rgb)
        try writeRGB(vignette.rgbImage, to: rgbURL)
        // Save depth
        let depthURL = dir.appendingPathComponent(data.paths.depth)
        try writeDepthPNG(
            depthMeters: vignette.depthMeters,
            width: vignette.resolution.width,
            height: vignette.resolution.height,
            to: depthURL
        )
        // Save confidence if available
        if let conf = vignette.confidence, let confName = data.paths.confidence {
            let confURL = dir.appendingPathComponent(confName)
            try writeConfidencePNG(confidence: conf,
                                   width: vignette.resolution.width,
                                   height: vignette.resolution.height,
                                   to: confURL)
        }
        // Save Points TODO
        
        // Save JSON
        let jsonURL = dir.appendingPathComponent("vignette.json")
        do {
            let encoded = try JSONEncoder.prettyISO8601.encode(data)
            try encoded.write(to: jsonURL, options: .atomic)
        } catch {
            throw StorageError.jsonWriteFailed(jsonURL)
        }
        return data
    }
    
    public func loadVignette(id: UUID) throws -> SpatialVignette {
        let dir = folderURL(for: id)
        let jsonURL = dir.appendingPathComponent("vignette.json")
        guard FileManager.default.fileExists(atPath: jsonURL.path) else {
            throw StorageError.fileMissing(jsonURL)
        }
        let data: VignetteData
        do {
            data = try JSONDecoder.iso8601.decode(VignetteData.self, from: Data(contentsOf: jsonURL))
        } catch {
            throw StorageError.jsonReadFailed(jsonURL)
        }
        return try loadVignette(from: data)
    }
    public func loadVignette(from data: VignetteData) throws -> SpatialVignette {
        let dir = folderURL(for: data.id)
        // load RGB
        let rgbURL = dir.appendingPathComponent(data.paths.rgb)
        guard let rgb = Self.readCGImage(from: rgbURL) else {
            throw StorageError.imageReadFailed(rgbURL)
        }
        // load depth
        let depthURL = dir.appendingPathComponent(data.paths.depth)
        guard let (depthMeters, w, h) = readDepthPNG(from: depthURL) else {
            throw StorageError.depthReadFailed(depthURL)
        }
        // Load confidence if available
        var confidenceArr: [UInt8]? = nil
        if let confName = data.paths.confidence {
            let confURL = dir.appendingPathComponent(confName)
            guard let (conf, cw, ch) = readConfidencePNG(from: confURL) else {
                throw StorageError.confidenceReadFailed(confURL)
            }
            confidenceArr = conf
        }
        
        // Load point cloud TODO
        
        // Load SAM Mask
        var loadedMask: CodableMLMultiArray? = nil
        if let maskName = data.paths.samMask {
            let maskURL = dir.appendingPathComponent(maskName)
            if FileManager.default.fileExists(atPath: maskURL.path) {
                loadedMask = try readSAMMask(from: maskURL)
            }
        }
        
        // build live vignette
        return SpatialVignette.fromVignetteData(
            data, rgbImage: rgb,
            depthMeters: depthMeters,
            confidence: confidenceArr,
            codableSAMMask: loadedMask
        )
    }
    
    public func listVignettes() -> [UUID] {
        guard let sub = try? FileManager.default.contentsOfDirectory(at: vignettesURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return sub.compactMap { url in
            guard let id = UUID(uuidString: url.lastPathComponent) else { return nil }
            let json = url.appendingPathComponent("vignette.json")
            return FileManager.default.fileExists(atPath: json.path) ? id : nil
        }
    }
    public func deleteVignette(id: UUID) throws {
        let dir = folderURL(for: id)
        if FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.removeItem(at: dir)
        }
    }
    
    // MARK: - Low-level helpers
    
    private func ensureDirectory(_ url: URL) throws {
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) {
            do {
                try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw StorageError.cannotCreateDirectory(url)
            }
        }
    }
    
    private func writeRGB(_ cgImage: CGImage, to url: URL) throws {
        let type: UTType = .png
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
            throw StorageError.imageWriteFailed(url)
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        if !CGImageDestinationFinalize(dest) {
            throw StorageError.imageWriteFailed(url)
        }
    }
    
    private func writeDepthPNG(depthMeters: [Float], width: Int, height: Int, to url: URL) throws {
        guard depthMeters.count == width * height else {
            throw StorageError.depthWriteFailed(url)
        }
        // meters to millimeters
        var milliBE = [UInt16](repeating: 0, count: depthMeters.count)
        for i in 0..<depthMeters.count {
            let m = depthMeters[i]
            if m.isFinite && m > 0 {
                let mm = Int(round(m * 1000.0))
                milliBE[i] = CFSwapInt16HostToBig(UInt16(clamping: mm))
            } else {
                milliBE[i] = 0
            }
        }
        // 16 bit CG Image
        let bitsPerComponent = 16
        let bitsPerPixel = 16
        let bytesPerRow = width * 2
        let dataLen = milliBE.count * MemoryLayout<UInt16>.size
        let nsData = NSData(bytes: &milliBE, length: dataLen)
        guard let provider = CGDataProvider(data: nsData) else {
            throw StorageError.depthWriteFailed(url)
        }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        
        guard let cg = CGImage(width: width,
                               height: height,
                               bitsPerComponent: bitsPerComponent,
                               bitsPerPixel: bitsPerPixel,
                               bytesPerRow: bytesPerRow,
                               space: colorSpace,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider,
                               decode: nil,
                               shouldInterpolate: false,
                               intent: .defaultIntent) else {
            throw StorageError.depthWriteFailed(url)
        }
        
        // Write PNG
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw StorageError.depthWriteFailed(url)
        }
        
        CGImageDestinationAddImage(dest, cg, nil)
        
        if !CGImageDestinationFinalize(dest) {
            throw StorageError.depthWriteFailed(url)
        }
    }
    private func readDepthPNG(from url: URL) -> ([Float], Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return nil
        }
        
        // Expect 16-bit, single-channel grayscale, no alpha
        guard cg.bitsPerComponent == 16,
              cg.bitsPerPixel == 16,
              cg.alphaInfo == .none else {
            return nil
        }
        
        let w = cg.width
        let h = cg.height
        let count = w * h
        
        // Access pixel data
        guard let providerData = cg.dataProvider?.data as Data? else { return nil }
        let u16Count = providerData.count / MemoryLayout<UInt16>.size
        guard u16Count == count else { return nil }
        
        var depthMeters = [Float](repeating: 0, count: count)
        providerData.withUnsafeBytes { raw in
            let bePtr = raw.bindMemory(to: UInt16.self)
            for i in 0..<count {
                // Convert big-endian -> host, then mm -> meters
                let mmBE = bePtr[i]
                let mm = CFSwapInt16BigToHost(mmBE)
                if mm == 0 {
                    depthMeters[i] = 0
                } else {
                    depthMeters[i] = Float(mm) * 0.001
                }
            }
        }
        return (depthMeters, w, h)
    }
    
    private func writeConfidencePNG(confidence: [UInt8], width: Int, height: Int, to url: URL) throws {
        guard confidence.count == width * height else {
            throw StorageError.confidenceWriteFailed(url)
        }
        let bitsPerComponent = 8
        let bitsPerPixel = 8
        let bytesPerRow = width * 1
        var bytes = confidence // make a mutable copy
        let nsData = NSData(bytes: &bytes, length: bytes.count)
        guard let provider = CGDataProvider(data: nsData) else {
            throw StorageError.confidenceWriteFailed(url)
        }
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let cg = CGImage(width: width,
                               height: height,
                               bitsPerComponent: bitsPerComponent,
                               bitsPerPixel: bitsPerPixel,
                               bytesPerRow: bytesPerRow,
                               space: colorSpace,
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
                               provider: provider,
                               decode: nil,
                               shouldInterpolate: false,
                               intent: .defaultIntent) else {
            throw StorageError.confidenceWriteFailed(url)
        }
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw StorageError.confidenceWriteFailed(url)
        }
        CGImageDestinationAddImage(dest, cg, nil)
        if !CGImageDestinationFinalize(dest) {
            throw StorageError.confidenceWriteFailed(url)
        }
    }
    private func readConfidencePNG(from url: URL) -> ([UInt8], Int, Int)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
            return nil
        }
        guard cg.bitsPerComponent == 8,
              cg.bitsPerPixel == 8,
              cg.alphaInfo == .none else {
            return nil
        }
        let w = cg.width
        let h = cg.height
        let count = w * h
        guard let providerData = cg.dataProvider?.data as Data? else { return nil }
        guard providerData.count == count else { return nil }
        var out = [UInt8](repeating: 0, count: count)
        providerData.copyBytes(to: &out, count: count)
        return (out, w, h)
    }
    
    private static func readCGImage(from url: URL) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(src, 0, nil)
    }
    
}

extension StorageManager {
    public func saveMask(for vignette: SpatialVignette) throws {
        // 1. Ensure there is actually a mask to save.
        guard let codableMask = vignette.codableSamMask else {
            print("No SAM mask to save for vignette \(vignette.id).")
            return
        }
        
        // 2. Get the correct directory for the vignette.
        let dir = folderURL(for: vignette.id)
        let maskURL = dir.appendingPathComponent("sam_mask.json")
        
        // 3. Write the raw mask data to the file.
        try saveSAMMask(codableMask, to: maskURL)
        
        // 4. Update the main JSON file to include the path to the new mask.
        // This reuses your existing updateJSON method.
        try updateJSON(for: vignette)
        
        print("Successfully saved SAM mask and updated JSON for vignette \(vignette.id).")
    }
    
    public func saveSubjectMask(for vignette: SpatialVignette, withThreshold threshold: Float) throws {
        print("Saving subject mask with threshold: \(threshold)...")
        
        // 1. Generate the final masked image using the vignette's own method.
        guard let finalImage = vignette.createMaskedImage(withThreshold: threshold) else {
            // Define a new StorageError for this case if you wish
            throw StorageError.imageWriteFailed(URL(fileURLWithPath: "in-memory-final-image"))
        }
        
        // 2. Set the threshold on the vignette object so it gets saved in the JSON.
        vignette.samMaskThreshold = threshold
        
        // 3. Get the destination URL and save the image file.
        let dir = folderURL(for: vignette.id)
        let imageURL = dir.appendingPathComponent("subject_mask.png")
        try writeRGB(finalImage, to: imageURL) // The writeRGB helper works for PNGs with transparency
        
        // 4. Update the main JSON file. This will now include the new path and threshold.
        try updateJSON(for: vignette)
        
        print("Subject mask saved and JSON updated successfully.")
    }
    @discardableResult
    public func updateJSON(for vignette: SpatialVignette) throws -> VignetteData {
        let dir = folderURL(for: vignette.id)
        let jsonURL = dir.appendingPathComponent("vignette.json")
        let data = vignette.toVignetteData()
        
        do {
            let data = try JSONEncoder.prettyISO8601.encode(data)
            try data.write(to: jsonURL, options: .atomic)
        } catch {
            throw StorageError.jsonWriteFailed(jsonURL)
        }
        return data
    }
    
    // just save the raw mask & update json
    private func saveSAMMask(_ mask: CodableMLMultiArray, to url: URL) throws {
        do {
            let data = try JSONEncoder().encode(mask)
            try data.write(to: url, options: .atomic)
        } catch {
            print("Error writing raw mask: \(error)")
            throw error
        }
    }
    private func readSAMMask(from url: URL) throws -> CodableMLMultiArray? {
            do {
                let data = try Data(contentsOf: url)
                return try JSONDecoder().decode(CodableMLMultiArray.self, from: data)
            } catch {
                // You should define a StorageError case for this
                print("Error reading raw mask: \(error)")
                throw error
            }
        }
}

// MARK: - JSON coder helpers
fileprivate extension JSONEncoder {
    static var prettyISO8601: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
fileprivate extension JSONDecoder {
    static var iso8601: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
