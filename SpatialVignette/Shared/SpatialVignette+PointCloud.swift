//
//  SpatialVignette+PointCloud.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/9/25.
//

import CoreGraphics
import simd

public struct PointXYZRGB {
    var x,y,z: Float
    var r,g,b: UInt8
}

public extension SpatialVignette {
    // This spatial vignette to array of points
    func generatePointCloud(sampleStride: Int = 1, maxDepth: Float? = nil) -> [PointXYZRGB] {
        let wDepth = resolution.width
        let hDepth = resolution.height
        precondition(depthMeters.count == wDepth * hDepth, "[PointCloud] depth size mismatch")

        // Prepare an RGBA8 buffer from the CGImage
        guard let rgbBuf = Self.makeRGBA8(from: rgbImage) else {
            print("[PointCloud] Failed to make RGBA8 buffer from RGB image")
            return []
        }
        let wRGB = rgbBuf.width
        let hRGB = rgbBuf.height
        let rowBytesRGB = rgbBuf.bytesPerRow
        
        let scaleX = Float(wRGB) / Float(wDepth)
        let scaleY = Float(hRGB) / Float(hDepth)
        let sX = Float(wDepth) / Float(wRGB)
        let sY = Float(hDepth) / Float(hRGB)

        // Intrinsics K = [[fx, 0, cx],[0, fy, cy],[0,0,1]]
        let fxD = cameraIntrinsics[0,0] * sX
        let fyD = cameraIntrinsics[1,1] * sY
        //let cxD = cameraIntrinsics[0,2] * sX
        //let cyD = cameraIntrinsics[1,2] * sY

        var points: [PointXYZRGB] = []
        points.reserveCapacity((wDepth/sampleStride) * (hDepth/sampleStride))

        for y in stride(from: 0, to: hDepth, by: sampleStride) {
            let yF = Float(y)
            for x in stride(from: 0, to: wDepth, by: sampleStride) {
                let xF = Float(x)
                let z = depthMeters[y * wDepth + x]
                if !z.isFinite || z <= 0 { continue }
                if let md = maxDepth, z > md { continue }

                // Unproject to camera coordinates
                let zCam = -z
                let Xc = -(xF - (Float(wDepth) / 2.0)) / fxD * zCam
                let Yc = (yF - (Float(hDepth) / 2.0)) / fyD * zCam
                let Zc = zCam

                // Map depth pixel to RGB pixel (nearest neighbor)
                let rx = min(max(Int(round(xF * scaleX)), 0), wRGB - 1)
                let ry = min(max(Int(round(yF * scaleY)), 0), hRGB - 1)
                let base = ry * rowBytesRGB + rx * 4
                // RGBA8 (premultiplied last). Take RGB.
                let r = rgbBuf.data[base + 0]
                let g = rgbBuf.data[base + 1]
                let b = rgbBuf.data[base + 2]

                points.append(PointXYZRGB(x: Xc, y: Yc, z: Zc, r: r, g: g, b: b))
            }
        }
        return points
    }
}

// MARK: - RGBA8 helper for fast CPU sampling
private extension SpatialVignette {
    struct RGBABuffer {
        let data: [UInt8]
        let width: Int
        let height: Int
        let bytesPerRow: Int
    }

    /// Convert an arbitrary CGImage into an RGBA8 buffer suitable for CPU sampling.
    static func makeRGBA8(from image: CGImage) -> RGBABuffer? {
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: bytesPerRow * height)

        guard let colorSpace = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        guard let ctx = CGContext(data: &buffer,
                                  width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bytesPerRow: bytesPerRow,
                                  space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil
        }
        // Draw into RGBA8 context (handles format conversions)
        ctx.interpolationQuality = .none
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return RGBABuffer(data: buffer, width: width, height: height, bytesPerRow: bytesPerRow)
    }
}
