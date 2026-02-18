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

@Test func convertImages

@Test func testBlurDetection() async throws {
    
    
}
