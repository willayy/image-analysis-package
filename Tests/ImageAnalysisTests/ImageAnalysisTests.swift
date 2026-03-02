import Testing
import Foundation
@testable import ImageAnalysis
import ImageIO


nonisolated(unsafe) var blurredImages: [CGImage]? = nil
nonisolated(unsafe) var sharpImages: [CGImage]? = nil

@Test func testLoadImages() async throws {
    guard let rootURL = Bundle.module.url(
        forResource: "TestData",
        withExtension: nil
    ) else {
        return
    }

    let blurredImageFolderURL = rootURL.appendingPathComponent("blurred")
    let sharpImageFolderURL = rootURL.appendingPathComponent("sharp")
    
    blurredImages = batchLoadImages(
        from: blurredImageFolderURL,
        fromIndex: 0,
        toIndex: 5
    )
    sharpImages = batchLoadImages(
        from: sharpImageFolderURL,
        fromIndex: 0,
        toIndex: 5
    )
        
    let fileManager = FileManager.default
    let blurryFilesCount = try fileManager.contentsOfDirectory(
        at: blurredImageFolderURL,
        includingPropertiesForKeys: nil,
        options: []
    ).count
    let sharpFilesCount = try fileManager.contentsOfDirectory(
        at: sharpImageFolderURL,
        includingPropertiesForKeys: nil,
        options: []
    ).count
    
    // Check that there is 6 image
    #expect(blurredImages?.count == blurryFilesCount && sharpImages?.count == sharpFilesCount)
    
    
    for image in blurredImages! + sharpImages! {
        #expect(image.width > 0 && image.height > 0)
        let data = image.dataProvider!.data!.self as Data
        #expect(!(data.prefix(100).allSatisfy {$0 == 0}))
    }
    
}

@Test func testBrightnessSingleImage() async throws {
    guard let rootURL = Bundle.module.url(
        forResource: "TestData",
        withExtension: nil
    ) else {
        return
    }
    
    let sharpImageFolderURL = rootURL.appendingPathComponent("sharp")
    guard let images = try? batchLoadImages(
        from: sharpImageFolderURL,
        fromIndex: 0,
        toIndex: 0
    ), let testImage = images.first else {
        return
    }
    
    // Test single image brightness using batch function
    let results = imageBrightness(images: [testImage])
    
    #expect(results.count == 1)
    let (_, brightness) = results[0]
    
    // Brightness should be between 0.0 and 1.0
    #expect(brightness >= 0.0 && brightness <= 1.0)
    
    // Sharp images from phone cameras should typically have reasonable brightness
    // Not too dark (> 0.1) and not completely white (< 0.95)
    #expect(brightness > 0.1 && brightness < 0.95)
}

@Test func testBrightnessMultipleImages() async throws {
    guard let rootURL = Bundle.module.url(
        forResource: "TestData",
        withExtension: nil
    ) else {
        return
    }
    
    let blurredImageFolderURL = rootURL.appendingPathComponent("blurred")
    let sharpImageFolderURL = rootURL.appendingPathComponent("sharp")
    
    guard let blurImages = try? batchLoadImages(
        from: blurredImageFolderURL,
        fromIndex: 0,
        toIndex: 2
    ) else {
        return
    }
    
    guard let sharpImages = try? batchLoadImages(
        from: sharpImageFolderURL,
        fromIndex: 0,
        toIndex: 2
    ) else {
        return
    }
    
    // Test batch processing
    let blurResults = imageBrightness(images: blurImages)
    let sharpResults = imageBrightness(images: sharpImages)
    
    // Check that we get results for all images
    #expect(blurResults.count == blurImages.count)
    #expect(sharpResults.count == sharpImages.count)
    
    // Check all brightness values are in valid range
    for (_, brightness) in blurResults {
        #expect(brightness >= 0.0 && brightness <= 1.0)
    }
    
    for (_, brightness) in sharpResults {
        #expect(brightness >= 0.0 && brightness <= 1.0)
    }
}

@Test func testBrightnessConsistency() async throws {
    guard let rootURL = Bundle.module.url(
        forResource: "TestData",
        withExtension: nil
    ) else {
        return
    }
    
    let sharpImageFolderURL = rootURL.appendingPathComponent("sharp")
    guard let images = try? batchLoadImages(
        from: sharpImageFolderURL,
        fromIndex: 0,
        toIndex: 0
    ), let testImage = images.first else {
        return
    }
    
    // Test that analyzing the same image multiple times gives same result
    let results1 = imageBrightness(images: [testImage])
    let results2 = imageBrightness(images: [testImage])
    
    let (_, brightness1) = results1[0]
    let (_, brightness2) = results2[0]
    
    #expect(brightness1 == brightness2)
}

@Test func testConvertImages() async throws {
    // Ensure images are loaded first by calling testLoadImages
    if blurredImages == nil || sharpImages == nil {
        // If images aren't loaded yet, load them
        try await testLoadImages()
    }
    
    // At this point, images should be loaded
    guard let blurred = blurredImages, let sharp = sharpImages else {
        throw NSError(domain: "ImageAnalysisTests", code: 3001, userInfo: [NSLocalizedDescriptionKey: "Failed to load test images"])
    }
    
    // Prepare images with identifiers for conversion
    var imagesToConvert: [(CGImage, String)] = []
    for (index, image) in blurred.enumerated() {
        imagesToConvert.append((image, "blurred_\(index)"))
    }
    for (index, image) in sharp.enumerated() {
        imagesToConvert.append((image, "sharp_\(index)"))
    }
    
    // Convert images to IdMatrix
    let matrices: [IdMatrix<UInt8, Int>] = try cgimagesToIdMatrices(imagesToConvert)
    
    // Verify that conversion worked
    #expect(matrices.count == imagesToConvert.count)
    
    // Verify each matrix has correct dimensions and data
    for (index, matrix) in matrices.enumerated() {
        let (image, id) = imagesToConvert[index]
        
        // Check dimensions match the original image
        #expect(matrix.rows == image.height)
        #expect(matrix.columns == image.width)
        
        // Check identity is correct
        #expect(matrix.identity == id)
        
        // Check that data is not all zeros (should contain actual pixel data)
        #expect(!matrix.data.allSatisfy { $0 == 0 })
        
        // Check data count matches expected size
        #expect(matrix.data.count > 0)
    }
}

@Test func testBlurDetection() async throws {
    
    
}

// MARK: - Laplacian Variance Tests

@Test func testLaplacianVarianceWithEmptyArray() async throws {
    // Test that the function handles an empty array correctly
    let emptyImages: [IdMatrix<Float, Int>] = []
    let result = laplacianVariance(images: emptyImages)
    
    #expect(result.isEmpty)
}

@Test func testLaplacianVarianceWithSingleImage() async throws {
    // Create a simple 3x3 test image with known values
    // Using a simple pattern that should produce a calculable variance
    let imageData: [Float] = [
        1.0, 2.0, 1.0,
        2.0, 4.0, 2.0,
        1.0, 2.0, 1.0
    ]
    let testImage = IdMatrix<Float, Int>(3, 3, imageData, "test-single")
    
    let result = laplacianVariance(images: [testImage])
    
    // Verify we get exactly one result
    #expect(result.count == 1)
    
    // Verify the original image is preserved in the result
    let (returnedImage, variance) = result[0]
    #expect(returnedImage.identity == "test-single")
    #expect(returnedImage.rows == 3)
    #expect(returnedImage.columns == 3)
    
    // Variance should be non-negative
    #expect(variance >= 0.0)
}

@Test func testLaplacianVarianceWithMultipleImages() async throws {
    // Create multiple test images
    let image1Data: [Float] = [
        1.0, 1.0, 1.0,
        1.0, 1.0, 1.0,
        1.0, 1.0, 1.0
    ]
    let image1 = IdMatrix<Float, Int>(3, 3, image1Data, "uniform-image")
    
    let image2Data: [Float] = [
        0.0, 1.0, 0.0,
        1.0, 0.0, 1.0,
        0.0, 1.0, 0.0
    ]
    let image2 = IdMatrix<Float, Int>(3, 3, image2Data, "checkerboard-image")
    
    let result = laplacianVariance(images: [image1, image2])
    
    // Verify we get results for both images
    #expect(result.count == 2)
    
    // Verify original images are preserved and in correct order
    #expect(result[0].0.identity == "uniform-image")
    #expect(result[1].0.identity == "checkerboard-image")
    
    // Verify all variances are non-negative
    for (_, variance) in result {
        #expect(variance >= 0.0)
    }
}

@Test func testLaplacianVarianceUniformImageHasLowVariance() async throws {
    // A uniform image (all pixels same value) should have very low variance
    // because the Laplacian will produce near-zero values everywhere
    let uniformData = [Float](repeating: 5.0, count: 25) // 5x5 uniform image
    let uniformImage = IdMatrix<Float, Int>(5, 5, uniformData, "uniform")
    
    let result = laplacianVariance(images: [uniformImage])
    
    #expect(result.count == 1)
    let variance = result[0].1
    
    // Uniform image should have very low variance (close to 0)
    // Due to floating point arithmetic, we check if it's very small
    #expect(variance < 1.0)
}

@Test func testLaplacianVarianceHighContrastImageHasHigherVariance() async throws {
    // Create two images: one uniform (low variance) and one with edges (higher variance)
    let uniformData = [Float](repeating: 5.0, count: 25) // 5x5 uniform
    let uniformImage = IdMatrix<Float, Int>(5, 5, uniformData, "uniform")
    
    // Create an image with a sharp edge (high contrast)
    let edgeData: [Float] = [
        0.0, 0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0, 0.0,
        0.0, 0.0, 0.0, 0.0, 0.0,
        10.0, 10.0, 10.0, 10.0, 10.0,
        10.0, 10.0, 10.0, 10.0, 10.0
    ]
    let edgeImage = IdMatrix<Float, Int>(5, 5, edgeData, "edge")
    
    let result = laplacianVariance(images: [uniformImage, edgeImage])
    
    #expect(result.count == 2)
    
    let uniformVariance = result[0].1
    let edgeVariance = result[1].1
    
    // Image with edge should have higher variance than uniform image
    #expect(edgeVariance > uniformVariance)
}

@Test func testLaplacianVariancePreservesImageData() async throws {
    // Verify that the original image data is not modified
    let originalData: [Float] = [
        1.0, 2.0, 3.0,
        4.0, 5.0, 6.0,
        7.0, 8.0, 9.0
    ]
    let testImage = IdMatrix<Float, Int>(3, 3, originalData, "preserve-test")
    
    let result = laplacianVariance(images: [testImage])
    
    #expect(result.count == 1)
    let returnedImage = result[0].0
    
    // Verify all properties are preserved
    #expect(returnedImage.identity == "preserve-test")
    #expect(returnedImage.rows == 3)
    #expect(returnedImage.columns == 3)
    #expect(returnedImage.count == 9)
    
    // Verify data is preserved
    #expect(returnedImage.data == originalData)
}

@Test func testLaplacianVarianceLargerImage() async throws {
    // Test with a larger image to ensure the function handles different sizes
    let width = 10
    let height = 10
    
    // Create a gradient image
    var gradientData: [Float] = []
    for y in 0..<height {
        for x in 0..<width {
            gradientData.append(Float(x + y))
        }
    }
    
    let gradientImage = IdMatrix<Float, Int>(
        height,
        width,
        gradientData,
        "gradient-10x10"
    )
    
    let result = laplacianVariance(images: [gradientImage])
    
    #expect(result.count == 1)
    #expect(result[0].0.identity == "gradient-10x10")
    #expect(result[0].1 >= 0.0)
}
