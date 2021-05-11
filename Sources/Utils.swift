//
//  Utils.swift
//  DownloadToGo
//
//  Created by Noam Tamim on 27/12/2018.
//

import Foundation
import XCGLogger
import AVFoundation
import VideoToolbox
import PlayKitUtils


typealias TaskProgress = (total: Int64, completed: Int64)

func calcCompletedFraction(downloadedBytes: Int64, estimatedTotalBytes: Int64, completedTaskCount: Int64?, totalTaskCount: Int64?) -> Float {
    if let total = totalTaskCount, let completed = completedTaskCount, total > 0 {
        return Float(completed) / Float(total)
    }
    
    return estimatedTotalBytes > 0 ? Float(downloadedBytes) / Float(estimatedTotalBytes) : 0
}

extension RandomAccessCollection {
    
    /// - Parameter areInIncreasingOrder: return nil when two element are equal
    /// - Returns: the sorted collection
    public func stableSorted(by areInIncreasingOrder: (Iterator.Element, Iterator.Element) -> Bool?) -> [Iterator.Element] {
        
        let sorted = self.enumerated().sorted { (one, another) -> Bool in
            if let result = areInIncreasingOrder(one.element, another.element) {
                return result
            } else {
                return one.offset < another.offset
            }
        }
        return sorted.map{ $0.element }
    }
}

class SafeSet<T: Hashable> {
    private var set = Set<T>()
    private let accessQueue = DispatchQueue(label: "SafeSet.accessQueue")

    func add(_ member: T) -> Bool {
        let oldMember = accessQueue.sync {
            set.update(with: member)
        }
        return oldMember == nil
    }

    func remove(_ member: T) {
        let removed = accessQueue.sync {
            set.remove(member)
        }
        if removed == nil {
            log.error("SafeSet.remove(): \(member) is missing from the set")
        }
    }
}

class SafeMap<Key: Hashable, Value: Any> {
    private var map = [Key: Value]()
    private let accessQueue = DispatchQueue(label: "SafeMap.accessQueue")
    
    subscript(key: Key) -> Value? {
        get {
            return self.accessQueue.sync {
                map[key]
            }
        }
        set {
            self.accessQueue.sync {
                map[key] = newValue
            }
        }
    }
    
    func first(where predicate: ((key: Key, value: Value)) throws -> Bool) rethrows -> (key: Key, value: Value)? {
        return try self.accessQueue.sync {
            try map.first(where: predicate)
        }
    }
}

public let log: XCGLogger = {
    #if DEBUG
    let logLevel: XCGLogger.Level = .debug
    #else
    let logLevel: XCGLogger.Level = .info
    #endif
    
    let logger = XCGLogger(identifier: "DTG")
    logger.setup(level: logLevel, showLogIdentifier: true, showLevel: false, showFileNames: true, showLineNumbers: true, showDate: false)
    return logger
}()



struct CodecSupport {
    // AC-3 (Dolby Atmos)
    static let ac3: Bool = AVURLAsset.audiovisualTypes().contains(AVFileType.ac3)
    
    // Enhanced AC-3 is supported only since iOS 9 (but not on all devices)
    static let ec3: Bool = {
        if #available(iOS 9.0, *) {
            return AVURLAsset.audiovisualTypes().contains(AVFileType.eac3)
        } else {
            return false
        }
    }()
    
    // HEVC is supported from iOS11, but by default we don't want to use it without hardware support
    static let hardwareHEVC: Bool = {
        if #available(iOS 11.0, *) {
            return VTIsHardwareDecodeSupported(kCMVideoCodecType_HEVC)
        } else {
            return false
        }
    }()
    
    static let softwareHEVC: Bool = {
        if #available(iOS 11.0, *) {
            return !hardwareHEVC
        } else {
            return false
        }
    }()
}

/************************************************************/
// MARK: - DownloadItemTaskType
/************************************************************/

enum DownloadItemTaskType: CustomStringConvertible {
        
    case video
    case audio
    case text
    case key
    
    static var allTypes: [DownloadItemTaskType] {
        return [.video, .audio, .text, .key]
    }
    
    init?(type: String) {
        switch type {
        case "video": self = .video
        case "audio": self = .audio
        case "text": self = .text
        case "key": self = .key
        default: return nil
        }
    }
    
    func asString() -> String {
        switch self {
        case .video: return "video"
        case .audio: return "audio"
        case .text: return "text"
        case .key: return "key"
        }
    }
    
    var description: String {
        return asString()
    }
}

/************************************************************/
// MARK: - DTGError
/************************************************************/

public enum DTGError: LocalizedError {
    case itemNotFound(itemId: String)
    /// Thrown when item cannot be started (caused when item state is other than metadata loaded)
    case invalidState(itemId: String)
    /// Thrown when item is already in the process of loading metadata
    case metadataLoading(itemId: String)
    /// insufficient disk space to start or continue the download
    case insufficientDiskSpace(freeSpaceInMegabytes: Int)
    /// Network timeout
    case networkTimeout(url: String)
    /// Invalid URL
    case invalidUrl(url: String)
    /// Server down
    case internalServerDown
    
    public var errorDescription: String? {
        switch self {
        case .itemNotFound(let itemId):
            return "The item (id: \(itemId)) of the action was not found"
        case .invalidState(let itemId):
            return "try to make an action with an invalid state (item id: \(itemId))"
        case .metadataLoading(let itemId):
            return "Item \(itemId) is already in the process of loading metadata"
        case .insufficientDiskSpace(let freeSpaceInMegabytes):
            return "insufficient disk space to start or continue the download, only have \(freeSpaceInMegabytes)MB free..."
        case .networkTimeout:
            return "Network timeout"
        case .invalidUrl:
            return "Invalid URL"
        case .internalServerDown:
            return "Internal Server is Down"
        }
    }
}

/* ***********************************************************/
// MARK: - DownloadItem
/* ***********************************************************/

struct DownloadItem: DTGItem {
    
    let id: String 
    let remoteUrl: URL
    var state: DTGItemState = .new 
    var estimatedSize: Int64?
    var downloadedSize: Int64 = 0
    var totalTaskCount: Int64?
    var completedTaskCount: Int64?
    var duration: TimeInterval?
    var availableTextTracks: [TrackInfo] = [] 
    var availableAudioTracks: [TrackInfo] = [] 
    var selectedTextTracks: [TrackInfo] = [] 
    var selectedAudioTracks: [TrackInfo] = []
    
    var completedFraction: Float {
        DownloadToGo.calcCompletedFraction(
            downloadedBytes: downloadedSize, estimatedTotalBytes: estimatedSize ?? 0, 
            completedTaskCount: completedTaskCount, totalTaskCount: totalTaskCount)
    }
    
    init(id: String, url: URL) {
        self.id = id
        self.remoteUrl = url
    }
}

public struct TrackInfo: Hashable {
    public let type: TrackType          // TYPE in M3U8
    public let languageCode: String?    // LANGUAGE in M3U8
    public let title: String            // NAME in M3U8
    
    var id_: String {
        return "\(self.languageCode ?? "<unknown>"):\(self.title)"
    }
    
    public enum TrackType: String {
        case audio
        case text
    }
}

/* ***********************************************************/
// MARK: - DTGFilePaths
/* ***********************************************************/

class DTGFilePaths {
    
    private static let mainDirName = "KalturaDTG"
    private static let itemsDirName = "items"
    
    static let storagePath: URL = {
        let libraryDir = try! FileManager.default.url(for: .libraryDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
        return libraryDir.appendingPathComponent(mainDirName, isDirectory: true)
    }()
    
    class var itemsDirUrl: URL {
        return ContentManager.shared.storagePath.appendingPathComponent(itemsDirName, isDirectory: true)
    }
    
    static func itemDirUrl(forItemId id: String) -> URL {
        return ContentManager.shared.storagePath.appendingPathComponent(itemsDirName, isDirectory: true).appendingPathComponent(id.safeItemPathName(), isDirectory: true)
    }
}


// From https://stackoverflow.com/a/24029847/38557
extension MutableCollection {
    /// Shuffles the contents of this collection.
    mutating func shuffle() {
        let c = count
        guard c > 1 else { return }
        
        for (firstUnshuffled, unshuffledCount) in zip(indices, stride(from: c, to: 1, by: -1)) {
            // Change `Int` in the next line to `IndexDistance` in < Swift 4.1
            let d: Int = numericCast(arc4random_uniform(numericCast(unshuffledCount)))
            let i = index(firstUnshuffled, offsetBy: d)
            swapAt(firstUnshuffled, i)
        }
    }
}

class PlayManifestDTGRequestParamsAdapter: DTGRequestParamsAdapter {
    var sessionId: String = ""
    var referrer: String = ""
    
    func adapt(_ params: DTGRequestParams) -> DTGRequestParams {
        let altUrl = PlayManifestRequestAdapter(url: params.url, sessionId: sessionId, clientTag: ContentManager.clientTag, 
            referrer: referrer, playbackType: "offline").adapt()
        return (altUrl, params.headers)
    }
}
