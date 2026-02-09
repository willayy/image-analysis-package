//
//  ImageAnalysis.swift
//  ImageAnalysis
//
//  Created by William Norland on 2026-01-25.
//

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
	
