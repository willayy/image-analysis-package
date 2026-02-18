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
#endif

/// Analyzes the darkness of an image by calculating the average pixel brightness.
///
/// This function is designed to detect images taken in poor lighting conditions,
/// such as photos captured with a phone camera in low light. It works by computing
/// the mean brightness value across all pixels in the image.
///
/// - Parameter image: A CGImage to analyze. The image can be in any color space,
///   though grayscale images are processed more efficiently.
///
/// - Returns: A Float value between 0.0 and 1.0 representing the average brightness:
///   - 0.0 indicates a completely dark/black image
///   - 0.5 indicates medium brightness
///   - 1.0 indicates a completely bright/white image
///   Values closer to 0.0 suggest poor lighting conditions.
///
/// - Throws: An error if the image data cannot be accessed or processed.
///
/// # Example Usage
/// ```swift
/// let brightness = try imageBrightness(image: myImage)
/// if brightness < 0.3 {
///     print("Image was taken in poor lighting conditions")
/// }
/// ```
///
/// # Implementation Details
/// The function analyzes pixel data by:
/// 1. Extracting raw pixel data from the CGImage
/// 2. Converting color pixels to grayscale if needed (using standard luminance weights)
/// 3. Computing the mean value of all pixels
/// 4. Normalizing the result to a 0.0-1.0 scale
///
public func imageBrightness(image: CGImage) throws -> Float {
    let width = image.width
    let height = image.height
    let totalPixels = width * height
    
    guard totalPixels > 0 else {
        throw NSError(
            domain: "ImageAnalysis",
            code: 3001,
            userInfo: [NSLocalizedDescriptionKey: "Image has zero pixels"]
        )
    }
    
    guard let dataProvider = image.dataProvider,
          let pixelData = dataProvider.data else {
        throw NSError(
            domain: "ImageAnalysis",
            code: 3002,
            userInfo: [NSLocalizedDescriptionKey: "Failed to access image pixel data"]
        )
    }
    
    let data = CFDataGetBytePtr(pixelData)
    guard let data = data else {
        throw NSError(
            domain: "ImageAnalysis",
            code: 3003,
            userInfo: [NSLocalizedDescriptionKey: "Failed to get pixel data pointer"]
        )
    }
    
    let bytesPerPixel = image.bitsPerPixel / 8
    let bytesPerRow = image.bytesPerRow
    
    var totalBrightness: Double = 0.0
    
    // Process each pixel
    for row in 0..<height {
        for col in 0..<width {
            let pixelOffset = row * bytesPerRow + col * bytesPerPixel
            
            let brightness: Double
            if bytesPerPixel == 1 {
                // Grayscale image
                brightness = Double(data[pixelOffset])
            } else if bytesPerPixel >= 3 {
                // Color image - use luminance formula (ITU-R BT.709)
                let r = Double(data[pixelOffset])
                let g = Double(data[pixelOffset + 1])
                let b = Double(data[pixelOffset + 2])
                brightness = 0.2126 * r + 0.7152 * g + 0.0722 * b
            } else {
                // Unsupported format, skip pixel
                continue
            }
            
            totalBrightness += brightness
        }
    }
    
    // Calculate average brightness and normalize to 0.0-1.0 range
    let averageBrightness = totalBrightness / Double(totalPixels)
    let normalizedBrightness = Float(averageBrightness / 255.0)
    
    return normalizedBrightness
}

/// Analyzes the darkness of multiple images by calculating their average pixel brightness.
///
/// This is a batch processing version of `imageBrightness(image:)` that processes
/// multiple images efficiently. Each image is analyzed independently and paired with
/// its brightness score.
///
/// - Parameter images: An array of CGImages to analyze.
///
/// - Returns: An array of tuples, each containing:
///   - The original CGImage
///   - A Float brightness value between 0.0 (dark) and 1.0 (bright)
///
/// - Throws: An error if any image's data cannot be accessed or processed.
///
/// # Example Usage
/// ```swift
/// let results = try imageBrightness(images: myImages)
/// for (image, brightness) in results {
///     if brightness < 0.3 {
///         print("Found a dark image with brightness: \(brightness)")
///     }
/// }
/// ```
///
public func imageBrightness(images: [CGImage]) throws -> [(CGImage, Float)] {
    var results: [(CGImage, Float)] = []
    
    for image in images {
        let brightness = try imageBrightness(image: image)
        results.append((image, brightness))
    }
    
    return results
}
	
