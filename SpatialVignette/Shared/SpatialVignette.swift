//
//  SpatialVignette.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/8/25.
//

import Foundation
import UIKit
import simd
import ARKit
import ImageIO
import MobileCoreServices
import Accelerate

// live class
public final class SpatialVignette {
    public let id: UUID
    public let createdAt: Date
    
    public let rgbImage: CGImage
    public let depthMeters: [Float] // depth in meters
    public let confidence: [UInt8]? // 0 low 1 mid 2 high
    public let resolution: Resolution
    public let cameraIntrinsics: simd_float3x3
    public let cameraExtrinsics: simd_float4x4
    
    public let deviceModel: String
    public var gps: GPS?
    public let note: String?
    
    // Generated Values
    public var codableSamMask: CodableMLMultiArray?
    public var samMaskThreshold: Float?
    private var _transientRawMask: MLMultiArray? = nil // Used by raw mask
    public var rawMaskLogits: MLMultiArray? {
        // Reconstruct from the codable data
        if _transientRawMask == nil {
            _transientRawMask = codableSamMask?.toMLMultiArray()
        }
        return _transientRawMask
    }
    
    public init(id: UUID = UUID(),
                createdAt: Date = .now,
                rgbImage: CGImage,
                depthMeters: [Float],
                confidence: [UInt8]? = nil,
                resolution: Resolution,
                cameraIntrinsics: simd_float3x3,
                cameraExtrinsics: simd_float4x4,
                deviceModel: String = UIDevice.current.model + " " + UIDevice.current.systemVersion,
                gps: GPS? = nil,
                note: String? = nil,
                codableSamMask: CodableMLMultiArray? = nil,
                samMaskThreshold: Float? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rgbImage = rgbImage
        self.depthMeters = depthMeters
        self.confidence = confidence
        self.resolution = resolution
        self.cameraIntrinsics = cameraIntrinsics
        self.cameraExtrinsics = cameraExtrinsics
        self.deviceModel = deviceModel
        self.gps = gps
        self.note = note
        self.codableSamMask = codableSamMask
        self.samMaskThreshold = samMaskThreshold
    }
}

public extension SpatialVignette {
    convenience init?(frame: ARFrame, gps: GPS? = nil) {
        guard let depthBuffer = frame.sceneDepth?.depthMap else {
            print("[SpatialVignette] sceneDepth is nil")
            return nil
        }
        let width = CVPixelBufferGetWidth(depthBuffer)
        let height = CVPixelBufferGetHeight(depthBuffer)
        print("[SpatialVignette] Depth buffer size: \(width)x\(height), format: \(CVPixelBufferGetPixelFormatType(depthBuffer))")
        
        // get [Float] from CVPixelBuffer
        guard let depthArray = SpatialVignette.pixelBufferFloat32ToArray(depthBuffer) else {
            print("[SpatialVignette] pixelBufferFloat32ToArray failed")
            return nil
        }
        print("[SpatialVignette] Depth array count: \(depthArray.count)")
        
        guard let rgb = SpatialVignette.makeCGImage(from: frame.capturedImage) else {
            print("[SpatialVignette] makeCGImage(capturedImage) failed")
            return nil
        }
        print("[SpatialVignette] RGB image created, size: \(rgb.width)x\(rgb.height)")
        
        let res = Resolution(width: width, height: height)
        
        // Get confidence
        let confBuffer = frame.sceneDepth?.confidenceMap
        var confArray: [UInt8]? = nil
        if let confPB = confBuffer {
            confArray = SpatialVignette.pixelBufferUInt8ToArray(confPB)
            if let c = confArray {
                print("[SpatialVignette] Confidence array count: \(c.count)")
            } else {
                print("[SpatialVignette] Failed to read confidence map")
            }
        } else {
            print("[SpatialVignette] No confidence map available on this frame")
        }
        
        self.init(
            rgbImage: rgb,
            depthMeters: depthArray,
            confidence: confArray,
            resolution: res,
            cameraIntrinsics: frame.camera.intrinsics,
            cameraExtrinsics: frame.camera.viewMatrix(for: .landscapeRight).inverse, // worldFromCamera
            deviceModel: UIDevice.current.model + " " + UIDevice.current.systemVersion,
            gps: gps,
            note: nil
        )
        print("[SpatialVignette] Successfully built vignette \(self.id)")
        if gps == nil { self.attachCurrentLocation() }
    }
    func attachCurrentLocation() {
        LocationService.shared.requestOneShot(withReverseGeocoding: true) { [weak self] newGPS in
            guard let self, let newGPS else { return }
            DispatchQueue.main.async { self.gps = newGPS }
        }
    }
}

// MARK: - Live <-> Data
public extension SpatialVignette {
    func toVignetteData(
        rgbFileName: String = "rgb.png",
        depthFileName: String = "depth.png",
        confidenceFileName: String = "confidence.png",
        samMaskFileName: String = "sam_mask.bin",
        subjectCropFileName: String = "subject_crop.png"
    ) -> VignetteData {
        let cam = CameraBlock(resolution: resolution, intrinsics: Self.flattenRowMajor(cameraIntrinsics), extrinsics: Self.flattenRowMajor(cameraExtrinsics))
        let paths = VignettePaths(
            rgb: rgbFileName, depth: depthFileName,
            confidence: (self.confidence != nil ? confidenceFileName : nil),
            points: nil,
            samMask: (self.codableSamMask != nil ? samMaskFileName : nil),
            samSubjectCrop: (self.samMaskThreshold != nil) ? subjectCropFileName : nil
        )
        let cap = CaptureBlock(deviceModel: deviceModel, gps: gps, note: note)
        return VignetteData(id: id, createdAt: createdAt, paths: paths, camera: cam, capture: cap, samMaskThreshold: self.samMaskThreshold)
    }
    
    static func fromVignetteData(
        _ data: VignetteData,
        rgbImage: CGImage,
        depthMeters: [Float],
        confidence: [UInt8]? = nil,
        codableSAMMask: CodableMLMultiArray? = nil
    ) -> SpatialVignette {
        SpatialVignette(
            id: data.id,
            createdAt: data.createdAt,
            rgbImage: rgbImage,
            depthMeters: depthMeters,
            confidence: confidence,
            resolution: data.camera.resolution,
            cameraIntrinsics: inflate3x3(data.camera.intrinsics),
            cameraExtrinsics: inflate4x4(data.camera.extrinsics),
            deviceModel: data.capture.deviceModel,
            gps: data.capture.gps,
            note: data.capture.note,
            codableSamMask: codableSAMMask,
            samMaskThreshold: data.samMaskThreshold
        )
    }

    private static func flattenRowMajor(_ m: simd_float3x3) -> [Float] {
        // Row-major: r0,r1,r2
        return [
            m[0,0], m[0,1], m[0,2],
            m[1,0], m[1,1], m[1,2],
            m[2,0], m[2,1], m[2,2],
        ]
    }
    private static func flattenRowMajor(_ m: simd_float4x4) -> [[Float]] {
        return [
            [m[0,0], m[0,1], m[0,2], m[0,3]],
            [m[1,0], m[1,1], m[1,2], m[1,3]],
            [m[2,0], m[2,1], m[2,2], m[2,3]],
            [m[3,0], m[3,1], m[3,2], m[3,3]],
        ]
    }
    private static func inflate3x3(_ a: [Float]) -> simd_float3x3 {
        precondition(a.count == 9)
        return simd_float3x3(rows: [
            SIMD3<Float>(a[0], a[1], a[2]),
            SIMD3<Float>(a[3], a[4], a[5]),
            SIMD3<Float>(a[6], a[7], a[8]),
        ])
    }
    private static func inflate4x4(_ a: [[Float]]) -> simd_float4x4 {
        precondition(a.count == 4 && a.allSatisfy { $0.count == 4 })
        return simd_float4x4(rows: [
            SIMD4<Float>(a[0][0], a[0][1], a[0][2], a[0][3]),
            SIMD4<Float>(a[1][0], a[1][1], a[1][2], a[1][3]),
            SIMD4<Float>(a[2][0], a[2][1], a[2][2], a[2][3]),
            SIMD4<Float>(a[3][0], a[3][1], a[3][2], a[3][3]),
        ])
    }
}

// MARK: - Private Helpers
private extension SpatialVignette {
    // CVPixelBuffer -> [Float} row-major
    static func pixelBufferFloat32ToArray(_ pb: CVPixelBuffer) -> [Float]? {
        /*
        guard CVPixelBufferGetPixelFormatType(pb) == kCVPixelFormatType_OneComponent32Float else {
            print("[DepthArray] Unexpected pixel format: \(CVPixelBufferGetPixelFormatType(pb)) (expected \(kCVPixelFormatType_OneComponent32Float))")
            return nil
        }*/
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let rowBytes = CVPixelBufferGetBytesPerRow(pb)
        print("[DepthArray] width=\(w), height=\(h), rowBytes=\(rowBytes), bytesPerPixel=\(MemoryLayout<Float>.size)")
        
        var out = [Float](repeating: 0, count: w * h)
        for y in 0..<h {
            let srcRow = base.advanced(by: y * rowBytes).assumingMemoryBound(to: Float.self)
            out.withUnsafeMutableBufferPointer { dst in
                let dstRow = dst.baseAddress! + y * w
                dstRow.update(from: srcRow, count: w)
            }
        }
        print("[DepthArray] Successfully converted to [Float], count=\(out.count)")
        return out
    }
    // CVPixelBuffer (one-component 8-bit) -> [UInt8] row-major
    static func pixelBufferUInt8ToArray(_ pb: CVPixelBuffer) -> [UInt8]? {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pb) else { return nil }
        let w = CVPixelBufferGetWidth(pb)
        let h = CVPixelBufferGetHeight(pb)
        let rowBytes = CVPixelBufferGetBytesPerRow(pb)
        var out = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            let src = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            out.withUnsafeMutableBufferPointer { dst in
                let dstRow = dst.baseAddress! + y * w
                dstRow.update(from: src, count: w)
            }
        }
        return out
    }
    // CVPixelBuffer -> Core Image
    private static func makeCGImage(from pixelBuffer: CVPixelBuffer) -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let ctx = CIContext(options: [.useSoftwareRenderer: false])
        return ctx.createCGImage(ciImage, from: ciImage.extent)
    }
}


extension SpatialVignette {
    public func generateSAMMask() async throws {
        // 1. get shared predictor
        guard let predictor = StandaloneSAMPredictor.shared else {
            print("[SAMPredictor] Shared predictor is not available.")
            throw SAMError.modelLoadingFailed(NSError(domain: "SAMPredictor", code: -1, userInfo: [NSLocalizedDescriptionKey: "Shared predictor is not available."]))
        }
        // 2. get center
        let centerPoint = CGPoint(x: self.rgbImage.width / 2, y: self.rgbImage.height / 2)
        let samPoints = [SAMPoint(coordinates: centerPoint, category: .foreground)]
        // 3. call predictor
        print("[SAMPredictor] Generating mask")
        let rawLogits = try await Task.detached {
            try predictor.generateRawMaskLogits(for: self.rgbImage, points: samPoints)
        }.value
        if let rawLogits = rawLogits {
            self.codableSamMask = CodableMLMultiArray(from: rawLogits)
            // Clear the transient cache
            self._transientRawMask = nil
        }
        
        if let codableSamMask {
            print("[SAM] Mask generated, saving mask...")
            try StorageManager.shared.saveMask(for: self)
        }
    }
    
    public func createMask(withThreshold threshold: Float) -> CGImage? {
        // 1. Safely unwrap the raw logit data. If it doesn't exist, we can't create a mask.
        guard let logits = rawMaskLogits else { return nil }
        
        // 2. Call the helper function on the MLMultiArray to create a binary (black & white) mask.
        guard let mask = logits.toBinaryMask(threshold: Float16(threshold)) else { return nil }
        
        // 3. Resize the final mask to match the original RGB image's dimensions.
        return mask.resized(to: CGSize(width: self.rgbImage.width, height: self.rgbImage.height))
    }
    
    public func createMaskedImage(withThreshold threshold: Float) -> CGImage? {
        print("[Vignette] createMaskedImage called.")
        // 1. create mask with threshold
        guard let rawMask = createMask(withThreshold: threshold) else { return nil }
        print("[Vignette] Step 1 Succeeded: Created raw mask.")
        // 2. clean up mask
        guard let cleanedMask = rawMask.cleaningUpMask() else { return nil }
        print("[Vignette] Step 2 Succeeded: Cleaned the mask.")
        guard let standardMask = cleanedMask.standardizedForMasking() else {
            return nil
        }
        print("[Vignette] Step 2.5 Succeeded: Standardized the mask format.")
        // 3. apply the mask
        guard let finalImage = self.rgbImage.masking(standardMask) else {
            print("[Vignette] Step 3 Failed: Applying the mask (CGImage.masking) returned nil.")
            return nil
        }
        print("[Vignette] Step 3 Succeeded: Applied mask to RGB image.")
        return finalImage
    }
}
