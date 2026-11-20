//
//  Song.swift
//  InTune_442
//
//  Created by Collin Le on 10/3/26.
//

import Foundation


struct Song: Identifiable, Codable, Equatable {
    let trackId: Int
    let trackName: String
    let artistName: String
    let artworkUrl100: String?
    let previewUrl: String?
    
    var id: Int {
        trackId
    }
}
