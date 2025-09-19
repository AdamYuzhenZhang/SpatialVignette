//
//  Untitled.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/15/25.
//

import UIKit

extension SpatialVignette {
    /// Convert depth array (meters) into a grayscale UIImage for preview.
    func depthPreviewImage() -> UIImage? {
        let w = resolution.width
        let h = resolution.height
        guard depthMeters.count == w * h else { return nil }

        // Normalize depths: find min/max ignoring zeros
        let valid = depthMeters.filter { $0 > 0 && $0.isFinite }
        guard let minVal = valid.min(), let maxVal = valid.max() else { return nil }
        let range = maxVal - minVal

        var pixels = [UInt8](repeating: 0, count: w * h)
        for i in 0..<depthMeters.count {
            let d = depthMeters[i]
            if d > 0, d.isFinite {
                let norm = (d - minVal) / range // 0...1
                pixels[i] = UInt8(clamping: Int(norm * 255))
            } else {
                pixels[i] = 0 // black for missing
            }
        }

        // Build CGImage from grayscale bytes
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        guard let cg = CGImage(width: w, height: h,
                               bitsPerComponent: 8, bitsPerPixel: 8,
                               bytesPerRow: w,
                               space: colorSpace,
                               bitmapInfo: CGBitmapInfo(rawValue: 0),
                               provider: provider,
                               decode: nil, shouldInterpolate: false,
                               intent: .defaultIntent) else { return nil }

        return UIImage(cgImage: cg, scale: 1, orientation: .right)
    }
    
    func confidencePreviewImage() -> UIImage? {
        guard let confidence = confidence else { return nil }
        let w = resolution.width
        let h = resolution.height
        guard confidence.count == w * h else { return nil }
        
        // RGBA (4 bytes per pixel)
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        
        for i in 0..<confidence.count {
            let c = confidence[i]
            let base = i * 4
            switch c {
            case 0: // low -> red
                pixels[base + 0] = 255 // R
                pixels[base + 1] = 0   // G
                pixels[base + 2] = 0   // B
                pixels[base + 3] = 255 // A
            case 1: // medium -> yellow
                pixels[base + 0] = 255
                pixels[base + 1] = 255
                pixels[base + 2] = 0
                pixels[base + 3] = 255
            case 2: // high -> green
                pixels[base + 0] = 0
                pixels[base + 1] = 255
                pixels[base + 2] = 0
                pixels[base + 3] = 255
            default: // unknown -> black
                pixels[base + 0] = 0
                pixels[base + 1] = 0
                pixels[base + 2] = 0
                pixels[base + 3] = 255
            }
        }
        
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        guard let cg = CGImage(width: w, height: h,
                               bitsPerComponent: 8, bitsPerPixel: 32,
                               bytesPerRow: w * 4,
                               space: CGColorSpaceCreateDeviceRGB(),
                               bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                               provider: provider,
                               decode: nil,
                               shouldInterpolate: false,
                               intent: .defaultIntent) else { return nil }
        
        return UIImage(cgImage: cg, scale: 1, orientation: .right)
    }
}
