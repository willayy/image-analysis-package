//
//  Matrix.swift
//  ImageAnalysis
//
//  Created by William Norland on 2026-01-26.
//

import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

public class Matrix<T: Numeric, D: Numeric> {
    let rows: D
    let columns: D
    let count: D
    var data: [T]
    
    init(_ rows: D, _ columns: D, _ data: [T]) {
        self.rows = rows
        self.columns = columns
        self.count = rows * columns
        self.data = data
    }
    
}

public class IdMatrix<T: Numeric, D: Numeric>: Matrix<T, D> {
    let identity: String
    
    init(_ rows: D, _ columns: D, _ data: [T], _ identity: String) {
        self.identity = identity
        super.init(rows, columns, data)
    }
    
}

/// Converts an array of CGImages with identifiers to an array of IdMatrix objects.
/// 
/// This function extracts monochrome pixel data from CGImages and creates IdMatrix objects
/// containing the pixel values. Each image must be in grayscale (monochrome) color space.
///
/// - Parameter cgImages: An array of tuples containing CGImage objects and their identifier strings
/// - Returns: An array of IdMatrix objects, where each matrix contains the pixel data from the corresponding image
/// - Throws: An error if any image is not in monochrome/grayscale color space, missing required data, or has invalid dimensions
///
/// - Note: The pixel data is extracted row by row and stored in the matrix's data array
#if canImport(CoreGraphics)
public func cgimagesToIdMatrices<T: Numeric, D: Numeric>(_ cgImages: [(CGImage, String)]) throws -> [IdMatrix<T, D>] {
    var matrices: [IdMatrix<T, D>] = []
    
    for (image, id) in cgImages {
        let rows = image.height
        let columns = image.width
        let bytesPerRow = image.bytesPerRow
        
        guard let colorSpace = image.colorSpace else {
            throw NSError(domain: "ImageAnalysis", code: 2003, userInfo: [NSLocalizedDescriptionKey: "Image '\(id)' is missing color space information."])
        }
        if colorSpace.model != .monochrome {
            throw NSError(domain: "ImageAnalysis", code: 2001, userInfo: [NSLocalizedDescriptionKey : "All input images must be in grayscale."])
        }
        guard let dataProvider = image.dataProvider else {
            throw NSError(domain: "ImageAnalysis", code: 2004, userInfo: [NSLocalizedDescriptionKey: "Image '\(id)' is missing data provider."])
        }
        guard let data = dataProvider.data else {
            throw NSError(domain: "ImageAnalysis", code: 2005, userInfo: [NSLocalizedDescriptionKey: "Image '\(id)' data provider has no data."])
        }
        guard let dataBuffer = CFDataGetBytePtr(data) else {
            throw NSError(domain: "ImageAnalysis", code: 2006, userInfo: [NSLocalizedDescriptionKey: "Image '\(id)' could not get data buffer pointer."])
        }
        
        // Extract pixel data from the buffer, accounting for row padding
        var pixelData: [T] = []
        let pixelCount = rows * columns
        pixelData.reserveCapacity(pixelCount)
        
        // Iterate through each row and column, using bytesPerRow to handle padding
        for row in 0..<rows {
            for col in 0..<columns {
                let index = row * bytesPerRow + col
                let pixelValue = dataBuffer[index]
                // Convert UInt8 pixel value to generic numeric type T
                guard let numericValue = T.init(exactly: pixelValue) else {
                    throw NSError(domain: "ImageAnalysis", code: 2002, userInfo: [NSLocalizedDescriptionKey: "Failed to convert pixel value to target numeric type."])
                }
                pixelData.append(numericValue)
            }
        }
        
        // Create IdMatrix with the extracted data
        guard let rowsD = D.init(exactly: rows), let columnsD = D.init(exactly: columns) else {
            throw NSError(domain: "ImageAnalysis", code: 2007, userInfo: [NSLocalizedDescriptionKey: "Image '\(id)' dimensions (\(rows)x\(columns)) cannot be converted to target dimension type."])
        }
        let matrix = IdMatrix(rowsD, columnsD, pixelData, id)
        matrices.append(matrix)
    }
    
    return matrices
}
#endif
