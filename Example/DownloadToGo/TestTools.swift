//
//  TestTools.swift
//  DownloadToGo
//
//  Created by Noam Tamim on 17/03/2019.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import PlayKit
import PlayKitProviders
import DownloadToGo

//let setSmallerOfflineDRMExpirationMinutes: Int? = 5
let setSmallerOfflineDRMExpirationMinutes: Int? = nil


let defaultEnv = "http://cdnapi.kaltura.com"

struct ItemOTTParamsJSON: Codable {
    let format: String?
}

struct ItemJSON: Codable {
    let id: String
    let title: String?
    let partnerId: Int?
    let ks: String?
    let env: String?
    
    let url: String?
    
    let options: OptionsJSON?
    
    let expected: ExpectedValues?
    
    let ott: Bool?
    let ottParams: ItemOTTParamsJSON?
}

struct ExpectedValues: Codable {
    let estimatedSize: Int64?
    let downloadedSize: Int64?
    let audioLangs: [String]?
    let textLangs: [String]?
}

struct OptionsJSON: Codable {
    let audioLangs: [String]?
    let allAudioLangs: Bool?
    let textLangs: [String]?
    let allTextLangs: Bool?
    let videoCodecs: [String]?
    let audioCodecs: [String]?
    let videoWidth: Int?
    let videoHeight: Int?
    let videoBitrates: [String:Int]?
    let allowInefficientCodecs: Bool?
    
    func toOptions() -> DTGSelectionOptions {
        let opts = DTGSelectionOptions()
        
        opts.allAudioLanguages = allAudioLangs ?? false
        opts.audioLanguages = audioLangs
        
        opts.allTextLanguages = allTextLangs ?? false
        opts.textLanguages = textLangs
        
        opts.allowInefficientCodecs = allowInefficientCodecs ?? false
        
        if let codecs = audioCodecs {
            opts.videoCodecs = codecs.compactMap({ (tag) -> DTGSelectionOptions.TrackCodec? in
                switch tag {
                case "mp4a": return .mp4a
                case "ac3": return .ac3
                case "eac3", "ec3": return .eac3
                default: return nil
                }
            })
        }
        
        if let codecs = videoCodecs {
            opts.videoCodecs = codecs.compactMap({ (tag) -> DTGSelectionOptions.TrackCodec? in
                switch tag {
                case "avc1": return .avc1
                case "hevc", "hvc1": return .hevc
                default: return nil
                }
            })
        }
        
        opts.videoWidth = videoWidth
        opts.videoHeight = videoHeight
        
        if let bitrates = videoBitrates {
            for (codecId, bitrate) in bitrates {
                let codec: DTGSelectionOptions.TrackCodec
                switch codecId {
                case "avc1": codec = .avc1
                case "hevc", "hvc1": codec = .hevc
                default: continue
                }
                
                opts.setMinVideoBitrate(codec, bitrate)
            }
        }
        
        return opts
    }
}

