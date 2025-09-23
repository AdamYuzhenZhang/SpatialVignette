//
//  ServerAPIService.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/22/25.
//

import Foundation
import UIKit
import CoreGraphics
import simd

// MARK: - Server Communication Service
// This class handles all networking with the Python server.
final class ServerAPIService {
    static let shared = ServerAPIService()
    
    // Change this to Mac's local network IP address.
    // System Settings > Wi-Fi > Details...
    private let baseURL = "https://inquirable-tien-veeringly.ngrok-free.dev" //"http://10.66.165.166:8000"
    
    // Custom errors for better debugging
    enum APIError: Error {
        case invalidURL
        case invalidImageData
        case invalidDepthData
        case requestFailed(Error)
        case invalidResponse
        case serverError(message: String)
        case decodingError(Error)
        case base64DecodingFailed
    }
    
    // MARK: - Result Structs
    struct LogitsResult {
        let data: Data // Raw Float32 data
        let height: Int
        let width: Int
    }

    // MARK: - Codable Structs for Server Payloads
    // These structs match the Pydantic models in main.py file.
    // Matches the server's `CameraIntrinsics` model
    private struct ServerCameraIntrinsics: Codable {
        let columns: [[Float]]
    }

    // Matches the server's `VignetteMetadata` model
    private struct ServerVignetteMetadata: Codable {
        let resolution: [Int]
        let camera_intrinsics: ServerCameraIntrinsics
        let subject_uv: [Float]
    }
    
    // Matches the server's `SegmentationThreshold` model
    private struct SegmentationThresholdPayload: Codable {
        let threshold: Float
    }
    
    // Server responses
    private struct UploadResponse: Codable { let vignette_id: String }
    private struct StatusResponse: Codable { let status: String, detail: String? }
        
    // Matches the server's `LogitsResponse` model
    private struct LogitsResponse: Codable {
        let logits_base64: String
        let mask_shape: [Int] // [height, width]
    }
    
    // MARK: - Main API Methods
    
    /// Step 1: Uploads the raw vignette data to the server.
    public func uploadVignette(_ vignette: SpatialVignette, uv: CGPoint) async throws -> String {
        guard let url = URL(string: "\(baseURL)/vignettes/") else { throw APIError.invalidURL }

        // 1. Convert image and depth data to binary `Data`
        guard let imageData = UIImage(cgImage: vignette.rgbImage).pngData() else { throw APIError.invalidImageData }
        
        // Convert [Float] to raw Data
        var depthArray = vignette.depthMeters
        let depthData = Data(buffer: UnsafeBufferPointer(start: &depthArray, count: depthArray.count))
        
        // confidence data
        var confidenceData: Data? = nil
        if var confidenceArray = vignette.confidence, !confidenceArray.isEmpty {
            confidenceData = Data(buffer: UnsafeBufferPointer(start: &confidenceArray, count: confidenceArray.count))
        }
        
        // 2. Prepare metadata JSON
        let metadata = try createMetadataPayload(for: vignette, uv: uv)
        let metadataJSON = try JSONEncoder().encode(metadata)
        guard let metadataString = String(data: metadataJSON, encoding: .utf8) else {
            throw APIError.decodingError(URLError(.cannotDecodeContentData))
        }

        // 3. Construct multipart/form-data request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = createMultipartBody(
            boundary: boundary,
            imageData: imageData,
            depthData: depthData,
            confidenceData: confidenceData,
            metadataString: metadataString
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else { throw APIError.invalidResponse }
        let result = try JSONDecoder().decode(UploadResponse.self, from: data)
        return result.vignette_id
    }
    
    /// Step 2: Tell the server to generate the segmentation logits.
    public func getLogits(for vignetteID: String) async throws -> LogitsResult {
        guard let url = URL(string: "\(baseURL)/vignettes/\(vignetteID)/segmentation/logits/") else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Logits failed. Server response: \(String(data: data, encoding: .utf8) ?? "No data")")
            throw APIError.invalidResponse
        }
        
        let result = try JSONDecoder().decode(LogitsResponse.self, from: data)
        guard let logitsData = Data(base64Encoded: result.logits_base64) else {
            throw APIError.base64DecodingFailed
        }
        guard result.mask_shape.count == 2 else {
            throw APIError.decodingError(URLError(.badServerResponse))
        }
        return LogitsResult(
            data: logitsData,
            height: result.mask_shape[0],
            width: result.mask_shape[1]
        )
    }

    /// Step 3: Tell the server to generate a mask from the logits with a specific threshold.
    public func getMask(for vignetteID: String, threshold: Float) async throws {
        guard let url = URL(string: "\(baseURL)/vignettes/\(vignetteID)/segmentation/mask/") else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(SegmentationThresholdPayload(threshold: threshold))
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            print("Mask failed. Server response: \(String(data: data, encoding: .utf8) ?? "No data")")
            throw APIError.invalidResponse
        }
        
        _ = try JSONDecoder().decode(StatusResponse.self, from: data)
    }
    
    // MARK: - Private Helpers
    
    private func createMetadataPayload(for vignette: SpatialVignette, uv: CGPoint) throws -> ServerVignetteMetadata {
        // Convert simd_float3x3 to the [[Float]] format the server expects
        let intrinsicsMatrix = vignette.cameraIntrinsics
        let intrinsicsColumns = [
            [intrinsicsMatrix.columns.0.x, intrinsicsMatrix.columns.0.y, intrinsicsMatrix.columns.0.z],
            [intrinsicsMatrix.columns.1.x, intrinsicsMatrix.columns.1.y, intrinsicsMatrix.columns.1.z],
            [intrinsicsMatrix.columns.2.x, intrinsicsMatrix.columns.2.y, intrinsicsMatrix.columns.2.z]
        ]
        
        return ServerVignetteMetadata(
            resolution: [vignette.resolution.width, vignette.resolution.height],
            camera_intrinsics: ServerCameraIntrinsics(columns: intrinsicsColumns),
            subject_uv: [Float(uv.x), Float(uv.y)]
        )
    }
    
    private func createMultipartBody(boundary: String, imageData: Data, depthData: Data, confidenceData: Data?, metadataString: String) -> Data {
        var body = Data()
        
        // -- RGB Image Part --
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"rgb_image\"; filename=\"rgb.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        
        // -- Depth Data Part --
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"depth_data\"; filename=\"depth.bin\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
        body.append(depthData)
        body.append("\r\n".data(using: .utf8)!)
        
        // -- Confidence Data Part --
        if let confidenceData = confidenceData {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"confidence_data\"; filename=\"confidence.bin\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: application/octet-stream\r\n\r\n".data(using: .utf8)!)
            body.append(confidenceData)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        // -- Metadata String Part --
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"metadata\"\r\n\r\n".data(using: .utf8)!)
        body.append(metadataString.data(using: .utf8)!)
        body.append("\r\n".data(using: .utf8)!)
        
        // -- Final boundary --
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        return body
    }
}


// MARK: - Integration with AppModel

// Add this extension to your AppModel file or here for testing.
extension AppModel {
    
    func testServerConnection() {
        // Ensure we have a vignette to send
        guard let vignette = self.lastVignette else {
            print("Error: No vignette captured yet.")
            return
        }
        
        // Simulate a user tap in the center of the image
        let tapUV = CGPoint(x: 0.5, y: 0.5)
        
        // The threshold from the slider (e.g., 0.0)
        let maskThreshold: Float = 0.0
        
        print("Starting server test...")
        
        Task {
            do {
                // 1. Upload the vignette
                print("Step 1: Uploading vignette...")
                let vignetteID = try await ServerAPIService.shared.uploadVignette(vignette, uv: tapUV)
                print("Vignette uploaded successfully! ID: \(vignetteID)")
                
                // 2. Request logits
                print("\nStep 2: Requesting segmentation logits...")
                try await ServerAPIService.shared.getLogits(for: vignetteID)
                print("Logits generated on server!")
                
                // 3. Request mask
                print("\nStep 3: Requesting mask with threshold \(maskThreshold)...")
                try await ServerAPIService.shared.getMask(for: vignetteID, threshold: maskThreshold)
                print("Mask generated on server!")
                
                print("\nServer test complete!")
                
            } catch let error as ServerAPIService.APIError {
                print("API Error: \(error)")
            } catch {
                print("An unexpected error occurred: \(error.localizedDescription)")
            }
        }
    }
}
