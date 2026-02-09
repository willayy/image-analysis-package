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

public func cgimagesToIdMatrices<T: Numeric, D: Numeric>(_ cgImages: [(CGImage, String)]) throws -> [IdMatrix<T, D>] {
    for (image,id) in cgImages {
        let rows = image.height
        let columns = image.width
        guard let colorSpace = image.colorSpace else { continue }
        if colorSpace.model != .monochrome {
            throw NSError(domain: "ImageAnalysis", code: 2001, userInfo: [NSLocalizedDescriptionKey : "All input images must be in grayscale."])
        }
        guard let dataProvider = image.dataProvider else { continue }
        guard let data = dataProvider.data else { continue }
        let bufferLength = CFDataGetLength(data)
        let dataBuffer = CFDataGetBytePtr(data)
        
    }
}
