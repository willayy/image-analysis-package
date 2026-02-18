//
//  ImageAnalysis.swift
//  ImageAnalysis
//
//  Created by William Norland on 2026-01-25.
//

#if canImport(Accelerate)
import Accelerate

public func laplacianVariance(images: [IdMatrix<Float, Int>]) -> [(IdMatrix<Float, Int>, Float)] {
    
    // Laplacian kernel df/dx^2 + df/dy^2
    let kernel = Matrix<Float, vDSP_Length>(
        3, 3, [0,  1, 0,
               1, -4, 1,
               0,  1, 0])
    
    // Create two reusable buffers for image data IO, these buffers should be large
    // to be able to accept any image size without reallocating
    let maxPixels = 48_000_000
    var inputBuffer = vImage_Buffer(
        data: UnsafeMutablePointer<Float>.allocate(
            capacity: MemoryLayout<Float>.size * maxPixels // n amount of floats, where n is the number of pixels in the image
        ),
        height: vImagePixelCount(0),    // Set height to 0 initially
        width: vImagePixelCount(0),     // Set width to 0 initially
        rowBytes: 0                     // Set bytes per row to 0 initially
    )
    var outputBuffer = vImage_Buffer(
        data: UnsafeMutablePointer<Float>.allocate(
            capacity: MemoryLayout<Float>.size * maxPixels
        ),
        height: vImagePixelCount(0),
        width: vImagePixelCount(0),
        rowBytes: 0
    )
    
    // Creata a list to hold the resulting scores
    var scores: [(IdMatrix<Float,Int>,Float)] = []
    
    for image in images {
        
        let bytes = image.columns * image.rows * MemoryLayout<Float>.size // Number of bytes of data in the current image
        
        // Copy over data from image to buffer
        inputBuffer.data.copyMemory(
            from: image.data,
            byteCount: bytes
        )
        inputBuffer.height = vImagePixelCount(image.rows)
        inputBuffer.width = vImagePixelCount(image.columns)
        inputBuffer.rowBytes = MemoryLayout<Float>.stride * image.columns
        
        // Transform pixels by convolving the image matrix with the laplacian
        let error = vImageConvolve_PlanarF(
            &inputBuffer,                   // Source Buffer
            &outputBuffer,                  // Destination Buffer
            nil,                            // Temp storage (nil lets vImage handle it)
            0, 0,                           // Top/Left offsets
            kernel.data,                    // The 1D representation of our 3x3 kernel
            3,                              // Kernel Height
            3,                              // Kernel Width
            0,                              // Background color (ignored due to flags)
            vImage_Flags(kvImageEdgeExtend) // Extend edges
        )
        
        if error != kvImageNoError {
            // TODO: Fix fatal error
            fatalError("Error performing convolution: \(error)")
        }
        
        var variance: Float = Float(0)
        
        // Compute variance of transformed pixels
        vDSP_measqv(
            outputBuffer.data.assumingMemoryBound(
                to: Float.self
            ),                         // The pointer, tell compiler to assume float
            1,                         // Stride length, set to 1 since we want to compute using all pixels
            &variance,                 // Output pointer
            vDSP_Length(image.count)   // Length of the data
        )
        
        scores.append((image,variance))
        
    }
    
    // Free allocated buffers
    inputBuffer.data.deallocate()
    outputBuffer.data.deallocate()
    
    return scores
}

/// Analyzes the darkness of multiple images by calculating their average pixel brightness.
///
/// This function is designed to detect images taken in poor lighting conditions,
/// such as photos captured with a phone camera in low light. It processes images
/// in batch for optimal performance using the Accelerate framework.
///
/// - Parameter images: An array of CGImages to analyze.
///
/// - Returns: An array of tuples, each containing:
///   - The original CGImage
///   - A Float brightness value between 0.0 (dark) and 1.0 (bright)
///     - 0.0 indicates a completely dark/black image
///     - 0.5 indicates medium brightness
///     - 1.0 indicates a completely bright/white image
///     - Values closer to 0.0 suggest poor lighting conditions
///
/// # Example Usage
/// ```swift
/// let results = imageBrightness(images: myImages)
/// for (image, brightness) in results {
///     if brightness < 0.3 {
///         print("Image was taken in poor lighting conditions")
///     }
/// }
/// ```
///
/// # Implementation Details
/// The function uses the Accelerate framework for high-performance computation:
/// 1. Converts CGImage pixel data to grayscale using ITU-R BT.709 luminance weights (0.2126*R + 0.7152*G + 0.0722*B)
/// 2. Uses vDSP functions to compute mean pixel values efficiently
/// 3. Normalizes results to a 0.0-1.0 scale
/// 4. Reuses buffers across images for memory efficiency
///
public func imageBrightness(images: [CGImage]) -> [(CGImage, Float)] {
    
    // Create reusable buffer for pixel data processing
    let maxPixels = 48_000_000
    var pixelBuffer = UnsafeMutablePointer<Float>.allocate(capacity: maxPixels)
    defer { pixelBuffer.deallocate() }
    
    var results: [(CGImage, Float)] = []
    
    for image in images {
        let width = image.width
        let height = image.height
        let totalPixels = width * height
        
        // Validate image and check buffer capacity
        guard totalPixels > 0,
              totalPixels <= maxPixels,
              let dataProvider = image.dataProvider,
              let pixelData = dataProvider.data,
              let data = CFDataGetBytePtr(pixelData) else {
            // Return 0.0 for invalid images or images exceeding buffer capacity
            // Note: 0.0 indicates both completely dark and invalid/skipped images
            results.append((image, 0.0))
            continue
        }
        
        let bytesPerPixel = image.bitsPerPixel / 8
        let bytesPerRow = image.bytesPerRow
        
        // Convert pixels to grayscale float values
        for row in 0..<height {
            for col in 0..<width {
                let pixelOffset = row * bytesPerRow + col * bytesPerPixel
                let pixelIndex = row * width + col
                
                let grayscaleValue: Float
                if bytesPerPixel == 1 {
                    // Grayscale image
                    grayscaleValue = Float(data[pixelOffset])
                } else if bytesPerPixel >= 3 {
                    // Color image - use ITU-R BT.709 luminance formula
                    let r = Float(data[pixelOffset])
                    let g = Float(data[pixelOffset + 1])
                    let b = Float(data[pixelOffset + 2])
                    grayscaleValue = 0.2126 * r + 0.7152 * g + 0.0722 * b
                } else {
                    // Unsupported format
                    grayscaleValue = 0.0
                }
                
                pixelBuffer[pixelIndex] = grayscaleValue
            }
        }
        
        // Use Accelerate framework to compute mean brightness
        var meanBrightness: Float = 0.0
        vDSP_meanv(
            pixelBuffer,                    // Input array
            1,                              // Stride
            &meanBrightness,                // Output mean
            vDSP_Length(totalPixels)        // Length
        )
        
        // Normalize to 0.0-1.0 range (assuming 8-bit color depth)
        let normalizedBrightness = meanBrightness / 255.0
        
        results.append((image, normalizedBrightness))
    }
    
    return results
}
#endif
	
