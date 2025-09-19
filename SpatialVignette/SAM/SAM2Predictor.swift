//
//  SAM2Predictor.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/15/25.
//

import CoreML
import CoreGraphics
import VideoToolbox

// MARK: - 1. Main Predictor Class

/// A standalone class for running the 3-stage SAM2 model pipeline.
/// This class is self-contained and does not depend on any other project files.
public final class StandaloneSAMPredictor {

    public static let shared = try? StandaloneSAMPredictor()
    
    // MARK: Properties
    private let imageEncoder: SAM2TinyImageEncoderFLOAT16
    private let promptEncoder: SAM2TinyPromptEncoderFLOAT16
    private let maskDecoder: SAM2TinyMaskDecoderFLOAT16
    
    private let modelInputSize = CGSize(width: 1024, height: 1024)
    
    // MARK: Initialization
    private init() throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let cpuAndGpuConfig = MLModelConfiguration()
        cpuAndGpuConfig.computeUnits = .cpuAndGPU
        
        do {
            imageEncoder = try SAM2TinyImageEncoderFLOAT16(configuration: configuration)
            promptEncoder = try SAM2TinyPromptEncoderFLOAT16(configuration: configuration)
            maskDecoder = try SAM2TinyMaskDecoderFLOAT16(configuration: cpuAndGpuConfig)
        } catch {
            print("Failed to load SAM models: \(error)")
            throw SAMError.modelLoadingFailed(error)
        }
    }
    
    // MARK: Public API
    
    /// Generates a segmentation mask for an image given prompt points.
    /// - Parameters:
    ///   - image: The input `CGImage` to segment.
    ///   - points: An array of `SAMPoint` objects to prompt the model.
    /// - Returns: A `CGImage` of the resulting mask, resized to the original image's dimensions.
    public func generateRawMaskLogits(for image: CGImage, points: [SAMPoint]) throws -> MLMultiArray? {
        let originalSize = CGSize(width: image.width, height: image.height)
        
        // Step 1: Convert CGImage to a CVPixelBuffer of the correct size.
        print("[SAMPredictor] Step 1: Creating PixelBuffer...")
        guard let pixelBuffer = image.toPixelBuffer(size: modelInputSize) else {
            throw SAMError.preprocessingFailed("Could not create CVPixelBuffer.")
        }
        
        // Step 2: Run the Image Encoder.
        print("[SAMPredictor] Step 2: Running Image Encoder...")
        let imageEncodings = try imageEncoder.prediction(image: pixelBuffer)
        
        // Step 3: Run the Prompt Encoder.
        print("[SAMPredictor] Step 3: Running Prompt Encoder...")
        let promptEncodings = try encodePrompts(points: points, originalSize: originalSize)
        
        // Step 4: Run the Mask Decoder with embeddings from the previous steps.
        print("[SAMPredictor] Step 4: Running Mask Decoder...")
        let decoderOutput = try maskDecoder.prediction(
            image_embedding: imageEncodings.image_embedding,
            sparse_embedding: promptEncodings.sparse_embeddings,
            dense_embedding: promptEncodings.dense_embeddings,
            feats_s0: imageEncodings.feats_s0,
            feats_s1: imageEncodings.feats_s1
        )
        
        // Step 5: Find the mask with the highest score from the output.
        print("[SAMPredictor] Step 5: Finding best mask...")
        let bestMaskMultiArray = findBestMask(from: decoderOutput)
        
        return bestMaskMultiArray
        /*
        // debugPrint(mask: bestMaskMultiArray)
        
        // Step 6: Convert the raw MLMultiArray data into a CGImage.
        print("[SAMPredictor] Step 6: Converting MLMultiArray to CGImage...")
        guard let maskCGImage = bestMaskMultiArray.toCGImage() else {
            throw SAMError.postprocessingFailed("Could not convert MLMultiArray to CGImage.")
        }
        print("[SAMPredictor] Generated raw mask with size: \(maskCGImage.width) x \(maskCGImage.height)")
        
        // Step 7: Resize the mask back to the original image's dimensions and return it.
        print("[SAMPredictor] Step 7: Resizing mask...")
        return maskCGImage.resized(to: originalSize)
         */
    }
    
    
    private func debugPrint(mask: MLMultiArray) {
        guard mask.shape.count == 2, mask.count > 0 else {
            print("[SAMPredictor Debug] Mask is empty or has wrong dimensions.")
            return
        }
        
        // Use the existing helper to get min and max values
        guard let (minVal, maxVal) = mask.getMinMax() else {
            print("[SAMPredictor Debug] Could not calculate min/max.")
            return
        }
        
        // Calculate the average value
        var sum: Double = 0
        let ptr = mask.dataPointer.bindMemory(to: Float16.self, capacity: mask.count)
        for i in 0..<mask.count {
            sum += Double(ptr[i])
        }
        let average = sum / Double(mask.count)
        
        print("--- Mask Data Debug ---")
        print(String(format: "[SAMPredictor Debug] Min Value: %.4f", minVal))
        print(String(format: "[SAMPredictor Debug] Max Value: %.4f", maxVal))
        print(String(format: "[SAMPredictor Debug] Avg Value: %.4f", average))
        
        // Print a 10x10 sample from the top-left corner
        print("[SAMPredictor Debug] Top-Left 10x10 Sample:")
        var sampleString = ""
        let height = mask.shape[0].intValue
        let width = mask.shape[1].intValue
        for i in 0..<min(10, height) {
            for j in 0..<min(10, width) {
                let val = mask[[i as NSNumber, j as NSNumber]].floatValue
                sampleString += String(format: "%6.2f ", val)
            }
            sampleString += "\n"
        }
        print(sampleString)
        print("-------------------------")
    }

    // MARK: Private Pipeline Logic
    private func encodePrompts(points: [SAMPoint], originalSize: CGSize) throws -> SAM2TinyPromptEncoderFLOAT16Output {
        let pointCount = NSNumber(value: points.count)
        guard pointCount.intValue > 0 else {
            throw SAMError.preprocessingFailed("At least one prompt point is required.")
        }
        
        let pointsMultiArray = try MLMultiArray(shape: [1, pointCount, 2], dataType: .float32)
        let labelsMultiArray = try MLMultiArray(shape: [1, pointCount], dataType: .int32)
        
        for (index, point) in points.enumerated() {
            let scaledX = (point.coordinates.x / originalSize.width) * modelInputSize.width
            let scaledY = (point.coordinates.y / originalSize.height) * modelInputSize.height
            
            pointsMultiArray[[0, index, 0] as [NSNumber]] = NSNumber(value: Float(scaledX))
            pointsMultiArray[[0, index, 1] as [NSNumber]] = NSNumber(value: Float(scaledY))
            labelsMultiArray[[0, index] as [NSNumber]] = NSNumber(value: point.category.type.rawValue)
        }
        
        return try promptEncoder.prediction(points: pointsMultiArray, labels: labelsMultiArray)
    }

    private func findBestMask(from output: SAM2TinyMaskDecoderFLOAT16Output) -> MLMultiArray {
        var bestScore: Float = -Float.infinity
        var bestMaskIndex = 0
        
        for i in 0..<output.scores.count {
            let score = output.scores[i].floatValue
            if score > bestScore {
                bestScore = score
                bestMaskIndex = i
            }
        }
        
        let masks = output.low_res_masks
        let (h, w) = (masks.shape[2].intValue, masks.shape[3].intValue)
        let bestMask = try! MLMultiArray(shape: [NSNumber(value: h), NSNumber(value: w)], dataType: masks.dataType)
        
        for i in 0..<h {
            for j in 0..<w {
                let val = masks[[0, bestMaskIndex, i, j] as [NSNumber]]
                bestMask[[i as NSNumber, j as NSNumber]] = val
            }
        }
        return bestMask
    }
}

// MARK: - 2. Supporting Data Structures & Errors

public enum SAMCategoryType: Int {
    case background = 0
    case foreground = 1
}

public struct SAMCategory {
    let type: SAMCategoryType
    public static let foreground = SAMCategory(type: .foreground)
    public static let background = SAMCategory(type: .background)
}

public struct SAMPoint {
    let coordinates: CGPoint
    let category: SAMCategory
}

public enum SAMError: Error {
    case modelLoadingFailed(Error)
    case preprocessingFailed(String)
    case postprocessingFailed(String)
}


// MARK: - 3. Essential Extensions (Implemented From Scratch)

extension CGImage {
    /// Resizes a CGImage to a new size.
    func resized(to size: CGSize) -> CGImage? {
        guard let colorSpace = self.colorSpace else { return nil }
        guard let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: self.bitsPerComponent,
            bytesPerRow: 0, // Automatically calculates
            space: colorSpace,
            bitmapInfo: self.bitmapInfo.rawValue
        ) else { return nil }
        
        context.interpolationQuality = .high
        context.draw(self, in: CGRect(origin: .zero, size: size))
        
        return context.makeImage()
    }
    
    /// Creates a CVPixelBuffer from a CGImage.
    func toPixelBuffer(size: CGSize) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferCGImageCompatibilityKey: kCFBooleanTrue,
            kCVPixelBufferCGBitmapContextCompatibilityKey: kCFBooleanTrue
        ] as CFDictionary
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault, Int(size.width), Int(size.height),
            kCVPixelFormatType_32ARGB, attributes, &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
        
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: Int(size.width), height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return nil }
        
        context.draw(self, in: CGRect(origin: .zero, size: size))
        return buffer
    }
}

extension MLMultiArray {
    /// Calculates the minimum and maximum values in the multi-array.
    func getMinMax() -> (min: Double, max: Double)? {
        guard self.count > 0 else { return nil }
        
        var minVal = Double.greatestFiniteMagnitude
        var maxVal = -Double.greatestFiniteMagnitude
        
        let ptr = self.dataPointer.bindMemory(to: Float16.self, capacity: self.count)
        
        for i in 0..<self.count {
            let val = Double(ptr[i])
            if val < minVal { minVal = val }
            if val > maxVal { maxVal = val }
        }
        return (minVal, maxVal)
    }
    
    /// Converts a 2D MLMultiArray representing a grayscale mask into a CGImage.
    func toCGImage() -> CGImage? {
        guard self.shape.count == 2 else { return nil }
        guard let (min, max) = getMinMax() else { return nil }
        
        let height = self.shape[0].intValue
        let width = self.shape[1].intValue
        let range = max - min
        
        let ptr = self.dataPointer.bindMemory(to: Float16.self, capacity: self.count)
        
        // Create an array to hold the grayscale pixel data.
        var pixels = [UInt8](repeating: 0, count: width * height)
        
        for i in 0..<pixels.count {
            let floatVal = Double(ptr[i])
            // Normalize the value from [min, max] to [0, 255]
            let normalized = (floatVal - min) / range
            pixels[i] = UInt8(clamping: Int(round(normalized * 255.0)))
        }
        
        // Create a CGImage from the raw grayscale pixel data.
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider,
            decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }
    

    
    func toBinaryMask(threshold: Float16 = 0.0) -> CGImage? {
        guard self.shape.count == 2 else { return nil }
        
        let height = self.shape[0].intValue
        let width = self.shape[1].intValue
        
        let ptr = self.dataPointer.bindMemory(to: Float16.self, capacity: self.count)
        
        // Create an array to hold the binary pixel data (0 for black, 255 for white).
        var pixels = [UInt8](repeating: 0, count: width * height)
        
        for i in 0..<pixels.count {
            let logit = ptr[i]
            // Apply the threshold
            if logit > threshold {
                pixels[i] = 255 // White
            }
        }
        
        // Create a CGImage from the raw grayscale pixel data.
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        
        return CGImage(
            width: width, height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: 0),
            provider: provider,
            decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

public struct CodableMLMultiArray: Codable {
    private let data: Data
    private let shape: [Int]
    
    // We assume Float16 for this specific implementation
    private static let dataType: MLMultiArrayDataType = .float16
    
    /// Initializes the wrapper from an existing MLMultiArray.
    public init?(from multiArray: MLMultiArray) {
        // Ensure the data type is what we expect
        guard multiArray.dataType == Self.dataType else {
            print("Error: Unexpected MLMultiArray data type. Expected Float16.")
            return nil
        }
        
        let byteCount = multiArray.count * MemoryLayout<Float16>.stride
        self.data = Data(bytes: multiArray.dataPointer, count: byteCount)
        self.shape = multiArray.shape.map { $0.intValue }
    }
    
    /// Reconstructs the MLMultiArray from the stored data.
    public func toMLMultiArray() -> MLMultiArray? {
        guard let multiArray = try? MLMultiArray(shape: shape as [NSNumber], dataType: Self.dataType) else {
            return nil
        }
        
        let byteCount = multiArray.count * MemoryLayout<Float16>.stride
        guard data.count == byteCount else {
            print("Error: Mismatched data size during MLMultiArray reconstruction.")
            return nil
        }
        
        data.withUnsafeBytes { buffer in
            if let baseAddress = buffer.baseAddress {
                multiArray.dataPointer.copyMemory(from: baseAddress, byteCount: byteCount)
            }
        }
        
        return multiArray
    }
}
