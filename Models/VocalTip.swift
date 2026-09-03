//
//  VocalTip.swift
//  5VocalMaster
//
//  Data model for Vocal Tips extracted and structured from OhVocal 48 Shorts
//

import Foundation

public struct VocalTip: Codable, Identifiable, Hashable {
    public let id: Int
    public let category: VocalCategory
    public let title: String
    public let shortsSummary: String
    public let beginnerAnalogy: String
    public let howTo: String
    public let youtubeId: String
    public let viewCount: Int
    public let relatedShorts: [Int]
    public let keyActionWord: String
    
    public var youtubeURL: URL? {
        guard !youtubeId.isEmpty else { return nil }
        return URL(string: "https://www.youtube.com/shorts/\(youtubeId)")
    }
    
    public var formattedViewCount: String {
        if viewCount >= 10000 {
            let formatted = Double(viewCount) / 10000.0
            return String(format: "%.1f만회", formatted)
        } else if viewCount >= 1000 {
            let formatted = Double(viewCount) / 1000.0
            return String(format: "%.1f천회", formatted)
        } else {
            return "\(viewCount)회"
        }
    }
}
