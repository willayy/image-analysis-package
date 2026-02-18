//
//  Matrix.swift
//  ImageAnalysis
//
//  Created by William Norland on 2026-01-26.
//

import ImageIO
import Foundation

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
/// - Throws: An error if any image is not in monochrome/grayscale color space
///
/// - Note: The pixel data is extracted row by row and stored in the matrix's data array
public func cgimagesToIdMatrices<T: Numeric, D: Numeric>(_ cgImages: [(CGImage, String)]) throws -> [IdMatrix<T, D>] {
    var matrices: [IdMatrix<T, D>] = []
    
    for (image, id) in cgImages {
        let rows = image.height
        let columns = image.width
        guard let colorSpace = image.colorSpace else { continue }
        if colorSpace.model != .monochrome {
            throw NSError(domain: "ImageAnalysis", code: 2001, userInfo: [NSLocalizedDescriptionKey : "All input images must be in grayscale."])
        }
        guard let dataProvider = image.dataProvider else { continue }
        guard let data = dataProvider.data else { continue }
        guard let dataBuffer = CFDataGetBytePtr(data) else { continue }
        
        // Extract pixel data from the buffer
        var pixelData: [T] = []
        let pixelCount = rows * columns
        pixelData.reserveCapacity(pixelCount)
        
        // Only iterate through actual pixel data, not padding bytes
        for i in 0..<pixelCount {
            let pixelValue = dataBuffer[i]
            // Convert UInt8 pixel value to generic numeric type T
            guard let numericValue = T.init(exactly: pixelValue) else {
                throw NSError(domain: "ImageAnalysis", code: 2002, userInfo: [NSLocalizedDescriptionKey: "Failed to convert pixel value to target numeric type."])
            }
            pixelData.append(numericValue)
        }
        
        // Create IdMatrix with the extracted data
        guard let rowsD = D.init(exactly: rows), let columnsD = D.init(exactly: columns) else {
            continue
        }
        let matrix = IdMatrix(rowsD, columnsD, pixelData, id)
        matrices.append(matrix)
    }
    
    return matrices
}
