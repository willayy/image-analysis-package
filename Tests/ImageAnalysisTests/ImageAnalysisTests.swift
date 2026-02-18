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
func cgImageToIdMatrix(_ cgImage: CGImage, identity: String) -> IdMatrix<Float, Int>? {
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
        toIndex: 1  // Load just 2 images
    )
    let sharpImages = try batchLoadImages(
        from: sharpImageFolderURL,
        fromIndex: 0,
        toIndex: 1  // Load just 2 images
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
