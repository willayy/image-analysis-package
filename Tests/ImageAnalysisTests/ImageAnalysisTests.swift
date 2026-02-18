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

@Test func testConvertImages() async throws {
    // Ensure images are loaded first by calling testLoadImages
    guard let blurred = blurredImages, let sharp = sharpImages else {
        // If images aren't loaded yet, load them
        try await testLoadImages()
    }
    
    // Prepare images with identifiers for conversion
    var imagesToConvert: [(CGImage, String)] = []
    for (index, image) in (blurredImages ?? []).enumerated() {
        imagesToConvert.append((image, "blurred_\(index)"))
    }
    for (index, image) in (sharpImages ?? []).enumerated() {
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
