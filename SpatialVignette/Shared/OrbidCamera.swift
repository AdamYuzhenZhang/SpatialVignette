//
//  OrbidCamera.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/9/25.
//


import Foundation
import simd
import CoreGraphics

public final class OrbitCamera {

    // MARK: - Public state

    /// Point the camera orbits around (world space).
    public var target: SIMD3<Float> = .zero

    /// Distance from target (meters, arbitrary units).
    public var distance: Float = 1.5 {
        didSet { distance = max(0.05, distance) } // avoid singularity
    }

    /// Horizontal rotation around target (radians). 0 looks down -Z.
    public var yaw: Float = 0

    /// Vertical rotation (radians). Clamp to avoid flipping.
    public var pitch: Float = 0 {
        didSet {
            // Lock pitch to just under ±90° to keep up vector sane.
            let limit: Float = (.pi / 2) - 0.01
            pitch = min(max(pitch, -limit), limit)
        }
    }

    /// Vertical field of view for the perspective projection (radians).
    public var fovY: Float = 60 * .pi / 180

    /// Aspect ratio (width / height). Keep this synced with your MTKView.
    public var aspect: Float = 1.0

    /// Near / far clip planes.
    public var nearZ: Float = 0.01
    public var farZ: Float = 100.0

    // MARK: - Matrices

    /// Standard right-handed view matrix (world → camera).
    /// Eye position is derived from (target, distance, yaw, pitch).
    public func viewMatrix() -> simd_float4x4 {
        let eye = position
        return lookAtRH(eye: eye, target: target, up: SIMD3<Float>(0, 1, 0))
    }

    /// Standard right-handed perspective projection (Metal NDC).
    public func projectionMatrix() -> simd_float4x4 {
        perspectiveRH(fovy: fovY, aspect: aspect, nearZ: nearZ, farZ: farZ)
    }

    // MARK: - Derived values

    /// The current camera position in world space.
    public var position: SIMD3<Float> {
        // Spherical coordinates around target
        // yaw rotates around Y, pitch tilts up/down.
        let x = distance * cos(pitch) * sin(yaw)
        let y = distance * sin(pitch)
        let z = distance * cos(pitch) * cos(yaw)
        return target + SIMD3<Float>(x, y, z)
    }

    // MARK: - Gesture helpers (call from your SwiftUI/UIKit gestures)

    /// Pan the orbit camera: change yaw (horizontal) and pitch (vertical)
    /// - Parameters:
    ///   - delta:   2D drag in screen points (dx, dy)
    ///   - size:    current view size (points) to normalize sensitivity
    ///   - speed:   scalar multiplier for sensitivity (default tuned)
    public func pan(by delta: CGPoint, in size: CGSize, speed: Float = 1.2) {
        guard size.width > 0, size.height > 0 else { return }
        let dx = Float(delta.x / size.width)
        let dy = Float(delta.y / size.height)
        yaw   -= dx * speed * .pi          // drag right -> look right
        pitch -= dy * speed * .pi * 0.5    // drag up -> look up
    }

    /// Dolly (zoom) in/out by a scalar multiplier (e.g., from pinch gesture).
    /// - Parameter scale: >1 zooms in, <1 zooms out (UIKit pinch scale).
    public func zoom(by scale: CGFloat) {
        guard scale > 0 else { return }
        let s = Float(scale)
        // Exponential feel: halve/double at typical pinch ranges.
        distance /= pow(2.0, (s - 1.0))
    }

    /// Dolly (zoom) by delta in points (e.g., trackpad scroll or wheel).
    /// Positive delta zooms in, negative zooms out.
    public func zoom(delta: CGFloat, sensitivity: Float = 0.002) {
        distance *= exp(-Float(delta) * sensitivity)
    }

    // MARK: - Private math helpers

    /// Right-handed lookAt (world → camera) matrix.
    private func lookAtRH(eye: SIMD3<Float>, target: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - target)          // camera forward (points from target to eye)
        let x = simd_normalize(simd_cross(up, z))     // camera right
        let y = simd_cross(z, x)                      // camera up
        let t = SIMD3<Float>(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye))
        return simd_float4x4(
            SIMD4<Float>(x.x, y.x, z.x, 0),
            SIMD4<Float>(x.y, y.y, z.y, 0),
            SIMD4<Float>(x.z, y.z, z.z, 0),
            SIMD4<Float>(t.x, t.y, t.z, 1)
        )
    }

    /// Right-handed perspective projection (Metal clip: z in [0,1]).
    private func perspectiveRH(fovy: Float, aspect: Float, nearZ: Float, farZ: Float) -> simd_float4x4 {
        let f = 1.0 / tanf(fovy * 0.5)
        let nf = 1.0 / (nearZ - farZ)
        // Column-major simd_float4x4 with Metal's clip space
        return simd_float4x4(
            SIMD4<Float>( f / aspect, 0,  0,                           0),
            SIMD4<Float>( 0,          f,  0,                           0),
            SIMD4<Float>( 0,          0,  (farZ + nearZ) * nf,        -1),
            SIMD4<Float>( 0,          0,  (2 * farZ * nearZ) * nf,     0)
        )
    }
}
