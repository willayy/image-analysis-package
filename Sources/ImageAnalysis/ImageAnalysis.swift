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

/// Represents a pair of potentially duplicate images with their similarity score.
///
/// The similarity score ranges from 0.0 to 1.0, where:
/// - 1.0 indicates identical images
/// - Values above 0.95 typically indicate duplicates
/// - Lower values indicate increasingly different images
public struct DuplicatePair {
    /// The first image in the comparison
    public let image1: IdMatrix<Float, Int>
    /// The second image in the comparison
    public let image2: IdMatrix<Float, Int>
    /// Similarity score between 0.0 and 1.0
    public let similarity: Float
    
    public init(image1: IdMatrix<Float, Int>, image2: IdMatrix<Float, Int>, similarity: Float) {
        self.image1 = image1
        self.image2 = image2
        self.similarity = similarity
    }
}

/// Classifies pairs of images as duplicates based on perceptual similarity.
///
/// This function uses a combination of histogram comparison and structural similarity
/// to detect duplicate images. It compares each pair of images and returns similarity scores.
///
/// The algorithm works by:
/// 1. Computing normalized histograms for each image
/// 2. Calculating histogram correlation between image pairs
/// 3. Computing mean squared error for structural similarity
/// 4. Combining metrics into a final similarity score
///
/// - Parameter images: An array of grayscale images represented as IdMatrix objects
/// - Returns: An array of DuplicatePair objects containing image pairs with similarity >= 0.80
///
/// # Example
/// ```swift
/// let images = [image1, image2, image3]
/// let duplicates = findDuplicateImages(images: images)
/// for pair in duplicates {
///     if pair.similarity > 0.95 {
///         print("High confidence duplicate: \(pair.image1.identity) and \(pair.image2.identity)")
///     }
/// }
/// ```
///
/// - Note: This function assumes all input images are grayscale and of similar dimensions.
///   Performance scales as O(n²) where n is the number of images.
public func findDuplicateImages(images: [IdMatrix<Float, Int>]) -> [DuplicatePair] {
    
    var duplicatePairs: [DuplicatePair] = []
    
    // Early return if less than 2 images
    guard images.count >= 2 else {
        return duplicatePairs
    }
    
    // Compare each pair of images
    for i in 0..<images.count {
        for j in (i+1)..<images.count {
            let img1 = images[i]
            let img2 = images[j]
            
            // Skip if images have different dimensions
            if img1.rows != img2.rows || img1.columns != img2.columns {
                continue
            }
            
            let similarity = calculateImageSimilarity(img1, img2)
            
            // Only include pairs with similarity above threshold (0.80 = 80% similar)
            if similarity >= 0.80 {
                duplicatePairs.append(DuplicatePair(
                    image1: img1,
                    image2: img2,
                    similarity: similarity
                ))
            }
        }
    }
    
    // Sort by similarity (highest first)
    duplicatePairs.sort { $0.similarity > $1.similarity }
    
    return duplicatePairs
}

/// Calculates similarity between two images using histogram correlation and MSE.
///
/// - Parameters:
///   - img1: First image
///   - img2: Second image
/// - Returns: Similarity score between 0.0 and 1.0
private func calculateImageSimilarity(_ img1: IdMatrix<Float, Int>, _ img2: IdMatrix<Float, Int>) -> Float {
    
    let pixelCount = Int(img1.count)
    
    // Calculate histogram correlation
    let histogramSimilarity = compareHistograms(img1.data, img2.data, count: pixelCount)
    
    // Calculate structural similarity using normalized MSE
    var mse: Float = 0.0
    vDSP_distancesq(
        img1.data, 1,
        img2.data, 1,
        &mse,
        vDSP_Length(pixelCount)
    )
    mse = mse / Float(pixelCount)
    
    // Normalize MSE to similarity score (assuming pixel values are 0-1)
    // We use exponential decay to convert MSE to similarity
    // The scaling factor of 10.0 was chosen empirically: it maps MSE of 0.1 to ~37% similarity,
    // and MSE of 0.3 to ~5% similarity, which provides good discrimination for normalized images
    let mseScalingFactor: Float = 10.0
    let structuralSimilarity = exp(-mse * mseScalingFactor)
    
    // Combine both metrics (weighted average)
    let combinedSimilarity = 0.6 * histogramSimilarity + 0.4 * structuralSimilarity
    
    return min(max(combinedSimilarity, 0.0), 1.0) // Clamp to [0, 1]
}

/// Compares two image histograms using correlation.
///
/// - Parameters:
///   - data1: First image pixel data
///   - data2: Second image pixel data
///   - count: Number of pixels
/// - Returns: Correlation coefficient between 0.0 and 1.0
private func compareHistograms(_ data1: [Float], _ data2: [Float], count: Int) -> Float {
    
    // Create histogram bins (64 bins for grayscale)
    let numBins = 64
    var hist1 = [Float](repeating: 0, count: numBins)
    var hist2 = [Float](repeating: 0, count: numBins)
    
    // Build histograms
    for i in 0..<count {
        let bin1 = min(Int(data1[i] * Float(numBins - 1)), numBins - 1)
        let bin2 = min(Int(data2[i] * Float(numBins - 1)), numBins - 1)
        hist1[bin1] += 1.0
        hist2[bin2] += 1.0
    }
    
    // Normalize histograms
    let countFloat = Float(count)
    vDSP_vsdiv(hist1, 1, &countFloat, &hist1, 1, vDSP_Length(numBins))
    vDSP_vsdiv(hist2, 1, &countFloat, &hist2, 1, vDSP_Length(numBins))
    
    // Calculate correlation coefficient
    var mean1: Float = 0.0
    var mean2: Float = 0.0
    vDSP_meanv(hist1, 1, &mean1, vDSP_Length(numBins))
    vDSP_meanv(hist2, 1, &mean2, vDSP_Length(numBins))
    
    // Calculate correlation using Accelerate
    var correlation: Float = 0.0
    var variance1: Float = 0.0
    var variance2: Float = 0.0
    
    // Calculate covariance and variances
    var temp1 = [Float](repeating: 0, count: numBins)
    var temp2 = [Float](repeating: 0, count: numBins)
    
    // Subtract means
    var negMean1 = -mean1
    var negMean2 = -mean2
    vDSP_vsadd(hist1, 1, &negMean1, &temp1, 1, vDSP_Length(numBins))
    vDSP_vsadd(hist2, 1, &negMean2, &temp2, 1, vDSP_Length(numBins))
    
    // Calculate dot product for covariance
    vDSP_dotpr(temp1, 1, temp2, 1, &correlation, vDSP_Length(numBins))
    
    // Calculate variances
    vDSP_dotpr(temp1, 1, temp1, 1, &variance1, vDSP_Length(numBins))
    vDSP_dotpr(temp2, 1, temp2, 1, &variance2, vDSP_Length(numBins))
    
    // Calculate correlation coefficient
    let denominator = sqrt(variance1 * variance2)
    if denominator > 0.0001 {
        correlation = correlation / denominator
        // Normalize to [0, 1] range from [-1, 1] range
        correlation = (correlation + 1.0) / 2.0
    } else {
        // If one or both histograms have near-zero variance (nearly uniform),
        // we can't compute correlation, so default to high similarity
        correlation = 1.0
    }
    
    return min(max(correlation, 0.0), 1.0)
}

/// Groups images into sets of duplicates.
///
/// This function analyzes all images and groups them into clusters where each cluster
/// contains images that are duplicates of each other based on a similarity threshold.
///
/// - Parameters:
///   - images: An array of grayscale images represented as IdMatrix objects
///   - threshold: Minimum similarity score (0.0-1.0) to consider images as duplicates. Default is 0.95.
/// - Returns: An array of arrays, where each inner array contains duplicate images
///
/// # Example
/// ```swift
/// let images = [image1, image2, image3, image4]
/// let groups = groupDuplicateImages(images: images, threshold: 0.95)
/// for group in groups {
///     print("Duplicate group:")
///     for image in group {
///         print("  - \(image.identity)")
///     }
/// }
/// ```
public func groupDuplicateImages(images: [IdMatrix<Float, Int>], threshold: Float = 0.95) -> [[IdMatrix<Float, Int>]] {
    
    guard images.count >= 2 else {
        return []
    }
    
    // Find all duplicate pairs above threshold
    let allPairs = findDuplicateImages(images: images)
    let duplicatePairs = allPairs.filter { $0.similarity >= threshold }
    
    // Build adjacency list for graph of duplicates
    var adjacencyList: [Int: Set<Int>] = [:]
    for i in 0..<images.count {
        adjacencyList[i] = Set<Int>()
    }
    
    // Add edges for duplicate pairs
    for pair in duplicatePairs {
        if let idx1 = images.firstIndex(where: { $0.identity == pair.image1.identity }),
           let idx2 = images.firstIndex(where: { $0.identity == pair.image2.identity }) {
            adjacencyList[idx1]?.insert(idx2)
            adjacencyList[idx2]?.insert(idx1)
        }
    }
    
    // Find connected components (groups of duplicates) using DFS
    var visited = Set<Int>()
    var groups: [[IdMatrix<Float, Int>]] = []
    
    for i in 0..<images.count {
        if !visited.contains(i) {
            var component: [IdMatrix<Float, Int>] = []
            var stack = [i]
            
            while !stack.isEmpty {
                let current = stack.removeLast()
                if !visited.contains(current) {
                    visited.insert(current)
                    component.append(images[current])
                    
                    if let neighbors = adjacencyList[current] {
                        for neighbor in neighbors {
                            if !visited.contains(neighbor) {
                                stack.append(neighbor)
                            }
                        }
                    }
                }
            }
            
            // Only add groups with more than one image
            if component.count > 1 {
                groups.append(component)
            }
        }
    }
    
    return groups
}
	
