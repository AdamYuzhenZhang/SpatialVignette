//
//  CGImage+Extension.swift
//  SpatialVignette
//
//  Created by Yuzhen Zhang on 9/16/25.
//

import CoreImage
import CoreImage.CIFilterBuiltins

// Add this extension to your project
extension CGImage {
    /// Cleans up a binary mask image by removing small, scattered white pixels.
    /// This function performs a "morphological opening" operation.
    /// - Parameter radius: The size of the kernel to use. A larger radius removes larger noise.
    /// - Returns: A cleaned CGImage, or nil if processing fails.
    func cleaningUpMask(radius: Float = 5.0) -> CGImage? {
        let ciContext = CIContext()
        let sourceImage = CIImage(cgImage: self)

        // 1. Erosion: Shrinks white areas, removing small speckles.
        let erodeFilter = CIFilter.morphologyMinimum()
        erodeFilter.inputImage = sourceImage
        erodeFilter.radius = radius
        guard let erodedImage = erodeFilter.outputImage else { return nil }
        
        // 2. Dilation: Expands the remaining white areas back to their original size.
        let dilateFilter = CIFilter.morphologyMaximum()
        dilateFilter.inputImage = erodedImage
        dilateFilter.radius = radius
        guard let dilatedImage = dilateFilter.outputImage else { return nil }

        // 3. Convert back to CGImage to be used as a mask.
        return ciContext.createCGImage(dilatedImage, from: dilatedImage.extent)
    }
    
    func applyMaskManually(mask: CGImage) -> CGImage? {
        // Ensure the mask and image have the same dimensions.
        guard self.width == mask.width && self.height == mask.height else {
            print("[Manual Mask] Error: Image and mask dimensions do not match.")
            return nil
        }
        
        let width = self.width
        let height = self.height
        
        // Create a new pixel buffer for the output image (RGBA).
        var maskedPixels = [UInt8](repeating: 0, count: width * height * 4)
        
        // Get the raw pixel data from the original RGB image and the mask.
        guard let imageDataProvider = self.dataProvider,
              let imageData = imageDataProvider.data as Data?,
              let maskDataProvider = mask.dataProvider,
              let maskData = maskDataProvider.data as Data? else {
            return nil
        }
        
        let imageBytes = [UInt8](imageData)
        let maskBytes = [UInt8](maskData)
        
        // Iterate through every pixel.
        for i in 0..<(width * height) {
            let imagePixelIndex = i * 4 // 4 bytes per pixel (RGBA) for the source
            let maskPixelIndex = i      // 1 byte per pixel for the grayscale mask
            
            // Copy the RGB values from the source image.
            maskedPixels[imagePixelIndex] = imageBytes[imagePixelIndex]         // Red
            maskedPixels[imagePixelIndex + 1] = imageBytes[imagePixelIndex + 1] // Green
            maskedPixels[imagePixelIndex + 2] = imageBytes[imagePixelIndex + 2] // Blue
            
            // Set the Alpha channel from the mask's brightness.
            // A white pixel in the mask (255) becomes fully opaque.
            // A black pixel in the mask (0) becomes fully transparent.
            maskedPixels[imagePixelIndex + 3] = maskBytes[maskPixelIndex]       // Alpha
        }
        
        // Create a new CGImage from our manually constructed pixel data.
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let provider = CGDataProvider(data: Data(maskedPixels) as CFData) else { return nil }
        
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )
    }
    
    func standardizedForMasking() -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceGray()
        let context = CGContext(
            data: nil,
            width: self.width,
            height: self.height,
            bitsPerComponent: 8,
            bytesPerRow: self.width, // 1 byte per pixel for 8-bit grayscale
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        
        guard let context = context else { return nil }
        
        context.draw(self, in: CGRect(x: 0, y: 0, width: self.width, height: self.height))
        
        return context.makeImage()
    }
}


extension CGImage {
    /// Converts the CGImage to a Base64 encoded JPEG string.
    func toBase64() -> String? {
        guard let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(mutableData, "public.jpeg" as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(destination, self, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        return (mutableData as Data).base64EncodedString()
    }
}
