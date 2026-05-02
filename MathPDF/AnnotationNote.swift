//
//  AnnotationNote.swift
//  MathPDF
//
//  Created by Zihong Lin on 4/5/26.
//

import CoreGraphics
import Foundation

struct AnnotationNote: Identifiable, Equatable {
    let id: String
    let pageIndex: Int
    let annotationIndex: Int
    let annotationType: String
    let contents: String
    let bounds: CGRect

    var trimmedContents: String {
        contents.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
