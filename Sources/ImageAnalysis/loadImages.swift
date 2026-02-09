//
//  loadimages.swift
//  ImageAnalysis
//
//  Created by William Norland on 2026-01-26.
//

import Foundation
import ImageIO

@available(macOS 13.0, *)
public func batchLoadImages(from: URL, fromIndex: Int, toIndex: Int) throws -> [CGImage] {
    
    // Start a file manager
    let fileManager = FileManager.default
    
    // Get all file URLS
    guard let fileURLs = try? fileManager
        .contentsOfDirectory(atPath: from.path)
        .sorted(by: {$0 < $1}) else {
        return []
    }
    
    // from is inclusive to is inclusive
    if (fromIndex < 0 || toIndex > fileURLs.count || fromIndex > toIndex) {
        throw NSError(domain: "ImageAnalysis", code: 1001, userInfo: [NSLocalizedDescriptionKey : "Bad indices provided \(fromIndex), \(toIndex)"])
    }
    
    // Define batch
    let urlBatch = fileURLs[fromIndex...toIndex]
    
    // Disable cache
    let options = [kCGImageSourceShouldCache: false] as CFDictionary
    
    // Load batch
    let imageBatch = try urlBatch.compactMap { imagePath -> CGImage? in
        
        let imageURL = from.appending(path: imagePath)
        
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, options) else {
            throw NSError(domain: "ImageAnalysis", code: 1002, userInfo: [NSLocalizedDescriptionKey : "Failed to create image source for: \(imageURL)"])
        }
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NSError(domain: "ImageAnalysis", code: 1003, userInfo: [NSLocalizedDescriptionKey : "Failed to decode image at index 0 for: \(imageURL)"])
        }

        return image
    }
    
    return imageBatch
}
