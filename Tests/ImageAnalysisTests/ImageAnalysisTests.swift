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

// Helper function to convert CGImage to IdMatrix for testing
private func cgImageToIdMatrix(_ cgImage: CGImage, identity: String) -> IdMatrix<Float, Int>? {
    let width = cgImage.width
    let height = cgImage.height
    
    guard let dataProvider = cgImage.dataProvider,
          let data = dataProvider.data as Data? else {
        return nil
    }
    
    let bytesPerPixel = cgImage.bitsPerPixel / 8
    let bytesPerRow = cgImage.bytesPerRow
    
    var floatData: [Float] = []
    floatData.reserveCapacity(width * height)
    
    for y in 0..<height {
        for x in 0..<width {
            let offset = y * bytesPerRow + x * bytesPerPixel
            if offset < data.count {
                let pixelValue = data[offset]
                // Normalize to 0.0-1.0 range
                floatData.append(Float(pixelValue) / 255.0)
            } else {
                floatData.append(0.0)
            }
        }
    }
    
    return IdMatrix<Float, Int>(Int(height), Int(width), floatData, identity)
}

@Test func testDuplicateImageDetection() async throws {
    // Load test images first
    guard let rootURL = Bundle.module.url(
        forResource: "TestData",
        withExtension: nil
    ) else {
        throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot find test data"])
    }
    
    let blurredImageFolderURL = rootURL.appendingPathComponent("blurred")
    let sharpImageFolderURL = rootURL.appendingPathComponent("sharp")
    
    let blurredImages = try batchLoadImages(
        from: blurredImageFolderURL,
        fromIndex: 0,
        toIndex: 1  // Load 2 images (indices 0-1)
    )
    let sharpImages = try batchLoadImages(
        from: sharpImageFolderURL,
        fromIndex: 0,
        toIndex: 1  // Load 2 images (indices 0-1)
    )
    
    // Convert to IdMatrix
    guard let blurred1 = cgImageToIdMatrix(blurredImages[0], identity: "blurred_0"),
          let blurred2 = cgImageToIdMatrix(blurredImages[1], identity: "blurred_1"),
          let sharp1 = cgImageToIdMatrix(sharpImages[0], identity: "sharp_0"),
          let sharp2 = cgImageToIdMatrix(sharpImages[1], identity: "sharp_1") else {
        throw NSError(domain: "TestError", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot convert images"])
    }
    
    // Test 1: Compare same image with itself (should have very high similarity)
    let identicalImages = [blurred1, blurred1]
    let identicalDuplicates = findDuplicateImages(images: identicalImages)
    #expect(identicalDuplicates.count > 0, "Should find duplicate when comparing image with itself")
    if identicalDuplicates.count > 0 {
        #expect(identicalDuplicates[0].similarity > 0.99, "Identical images should have similarity > 0.99")
    }
    
    // Test 2: Compare different images (should have lower similarity)
    let differentImages = [blurred1, sharp1]
    let differentDuplicates = findDuplicateImages(images: differentImages)
    // Different images might or might not be flagged as duplicates depending on similarity
    // But if they are found as duplicates, similarity should be lower than identical images
    if !differentDuplicates.isEmpty && !identicalDuplicates.isEmpty {
        #expect(differentDuplicates[0].similarity < identicalDuplicates[0].similarity,
                "Different images should have lower similarity than identical images")
    }
    
    // Test 3: Test with multiple images
    let multipleImages = [blurred1, blurred2, sharp1, sharp2]
    let multipleDuplicates = findDuplicateImages(images: multipleImages)
    // Should return results sorted by similarity
    for i in 0..<(multipleDuplicates.count - 1) {
        #expect(multipleDuplicates[i].similarity >= multipleDuplicates[i + 1].similarity,
                "Results should be sorted by similarity in descending order")
    }
}

@Test func testGroupDuplicateImages() async throws {
    // Create some simple test images with known characteristics
    let size = 100
    let imageData1 = [Float](repeating: 0.5, count: size * size)
    let imageData2 = [Float](repeating: 0.5, count: size * size)
    let imageData3 = [Float](repeating: 0.3, count: size * size)
    
    let img1 = IdMatrix<Float, Int>(size, size, imageData1, "image1")
    let img2 = IdMatrix<Float, Int>(size, size, imageData2, "image2")
    let img3 = IdMatrix<Float, Int>(size, size, imageData3, "image3")
    
    // Test grouping with high threshold
    let images = [img1, img2, img3]
    let groups = groupDuplicateImages(images: images, threshold: 0.95)
    
    // img1 and img2 are identical, so they should be in the same group
    #expect(groups.count > 0, "Should find at least one group of duplicates")
    
    // Verify that groups contain the expected images
    if groups.count > 0 {
        let firstGroup = groups[0]
        #expect(firstGroup.count >= 2, "First group should contain at least 2 images")
        
        // Check that img1 and img2 are in the same group
        let identities = Set(firstGroup.map { $0.identity })
        let hasImg1 = identities.contains("image1")
        let hasImg2 = identities.contains("image2")
        #expect(hasImg1 && hasImg2, "image1 and image2 should be in the same group")
    }
}

@Test func testDuplicatePairStruct() {
    let imageData = [Float](repeating: 0.5, count: 100)
    let img1 = IdMatrix<Float, Int>(10, 10, imageData, "test1")
    let img2 = IdMatrix<Float, Int>(10, 10, imageData, "test2")
    
    let pair = DuplicatePair(image1: img1, image2: img2, similarity: 0.95)
    
    #expect(pair.image1.identity == "test1")
    #expect(pair.image2.identity == "test2")
    #expect(pair.similarity == 0.95)
}

@Test func testEmptyImageList() {
    let emptyImages: [IdMatrix<Float, Int>] = []
    let duplicates = findDuplicateImages(images: emptyImages)
    #expect(duplicates.isEmpty, "Empty image list should return no duplicates")
    
    let groups = groupDuplicateImages(images: emptyImages)
    #expect(groups.isEmpty, "Empty image list should return no groups")
}

@Test func testSingleImage() {
    let imageData = [Float](repeating: 0.5, count: 100)
    let img = IdMatrix<Float, Int>(10, 10, imageData, "single")
    
    let duplicates = findDuplicateImages(images: [img])
    #expect(duplicates.isEmpty, "Single image should return no duplicates")
    
    let groups = groupDuplicateImages(images: [img])
    #expect(groups.isEmpty, "Single image should return no groups")
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
