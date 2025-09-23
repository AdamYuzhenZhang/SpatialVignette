//
//  ImageUtils.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/23/25.
//

import Foundation
import CoreGraphics
import VideoToolbox // For CGImage conversion

final class ImageUtils {
    
    /// Creates a black and white CGImage from raw Float32 data based on a threshold.
    ///
    /// - Parameters:
    ///   - logits: The raw `Data` object containing the Float32 array.
    ///   - width: The width of the mask.
    ///   - height: The height of the mask.
    ///   - threshold: The value to compare against. Pixels with a logit value > threshold will be white.
    /// - Returns: An optional `CGImage`.
    static func createMaskImage(from logits: Data, width: Int, height: Int, threshold: Float) -> CGImage? {
        // Ensure the data size is correct. Each Float32 is 4 bytes.
        guard logits.count == width * height * 4 else {
            print("Error: Logits data size does not match expected size.")
            return nil
        }
        
        // Create a buffer to hold the 8-bit grayscale pixel data (0 for black, 255 for white).
        var pixelBuffer = [UInt8](repeating: 0, count: width * height)
        
        // Iterate through the Float32 data and fill the pixel buffer.
        logits.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
            // Get a typed pointer to the Float32 values.
            let float32Pointer = pointer.bindMemory(to: Float32.self)
            
            for i in 0..<(width * height) {
                // If the logit value is greater than the threshold, set the pixel to white (255).
                // Otherwise, it remains black (0).
                if float32Pointer[i] > threshold {
                    pixelBuffer[i] = 255
                }
            }
        }
        
        // Now, convert the raw pixel buffer into a CGImage.
        let bitsPerComponent = 8
        let bitsPerPixel = 8
        let bytesPerRow = width
        let colorSpace = CGColorSpaceCreateDeviceGray()
        
        guard let dataProvider = CGDataProvider(data: Data(pixelBuffer) as CFData) else {
            return nil
        }
        
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: bitsPerComponent,
            bitsPerPixel: bitsPerPixel,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: dataProvider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
        
        return cgImage
    }
}
