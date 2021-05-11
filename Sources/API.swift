// ===================================================================================================
// Copyright (C) 2017 Kaltura Inc.
//
// Licensed under the AGPLv3 license, unless a different license for a 
// particular library is specified in the applicable library path.
//
// You may obtain a copy of the License at
// https://www.gnu.org/licenses/agpl-3.0.html
// ===================================================================================================


import Foundation
import XCGLogger

/// Main entry point of the library, used to control item download and get their playback URL.
public protocol DTGContentManager: class {
    
    /// The storage path for directories and files.
    var storagePath: URL { get }
    
    /// Delegate that will receive download events.
    var delegate: ContentManagerDelegate? { get set }
    
    /// set log level for viewing logs.
    func setLogLevel(_ logLevel: LogLevel)
    
    /// Start the content manager. This also starts the playback server.
    func start(completionHandler: (() -> Void)?) throws
    
    /// Stop the content manager, including the playback server.
    func stop()
    
    /// Return all items in the specified state.
    func itemsByState(_ state: DTGItemState) throws -> [DTGItem]
    
    /// Find an existing item.
    /// - Parameter id: the item's unique id.
    /// - Returns: an item, or nil if not found.
    func itemById(_ id: String) throws -> DTGItem?
    
    /// Add a new item.
    /// - Parameters:
    ///     - id: a unique id for the new item
    ///     - url: the remote URL of the item.
    /// - Returns: the newly allocated item or nil if already exists.
    func addItem(id: String, url: URL) throws -> DTGItem?
    
    /// Load metadata for the given item id.
    /// - Attention:
    /// This method executes on the thread it is called and takes time to finish,
    /// the **best practice is to call this method from a background queue**.
    /// - Parameters:
    ///     - id: the item's unique id.
    ///     - preferredVideoBitrate: video bitrate to download
    /// - Throws: DTGError.itemNotFound
    /// - Note: use `loadItemMetadata(id:options:)` for more control on downloaded tracks.
    func loadItemMetadata(id: String, preferredVideoBitrate: Int?) throws
    
    /// Load metadata for the given item id with media selection options.
    /// - Attention:
    /// This method executes on the thread it is called and takes time to finish,
    /// the **best practice is to call this method from a background queue**.
    /// - Parameters:
    ///     - id: the item's unique id.
    ///     - options: track selection options
    /// - Throws: DTGError.itemNotFound
    func loadItemMetadata(id: String, options: DTGSelectionOptions?) throws
    
    /// Start or resume item download.
    /// - Throws: DTGError.itemNotFound
    func startItem(id: String) throws
    
    /// Start items download in specified states.
    /// can be used to resume inProgress (after force quit) / interrupted / paused items, can use multiple selection or just one.
    ///
    /// ````
    /// try startItems(inStates: .inProgress)
    /// // or like this:
    /// try startItems(inStates: .inProgress, .paused)
    /// ````
    ///
    /// - Parameter states: The states to start.
    func startItems(inStates states: DTGItemStartableState...) throws
    
    /// Pause downloading an item.
    /// - Throws: DTGError.itemNotFound
    func pauseItem(id: String) throws
    
    /// Remove an existing item from storage, deleting all related files.
    /// - Throws: DTGError.itemNotFound
    func removeItem(id: String) throws
    
    /// Get a playable URL for an item.
    /// - Returns: a playback URL, or nil.
    /// - Throws: DTGError.itemNotFound
    func itemPlaybackUrl(id: String) throws -> URL?
    
    
    /// Handles events of a background session waiting to be processed.
    ///
    /// - Parameters:
    ///   - identifier: The background url session identifier.
    ///   - completionHandler: the completionHandler to call when finished handling the events.
    func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void)
    
    /// handles all the setup needed by the content manager, must be called on AppDelegate in:
    ///
    /// ```func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool```
    func setup() throws
    
    /// Set the default audio bitrate for size-estimation purposes. Defaults to 64000.
    func setDefaultAudioBitrateEstimation(bitrate: Int)
    
    func setManifestRequestAdapter(adapter: DTGRequestParamsAdapter)
    func setChunksRequestAdapter(adapter: DTGRequestParamsAdapter)
}


extension DTGContentManager {
    public func setLogLevel(_ logLevel: LogLevel) {
        log.outputLevel = logLevel.asXCGLoggerLevel()
    }
}

/// Delegate that will receive download events.
public protocol ContentManagerDelegate: class {
    /// Some data was downloaded for the item. 
    func item(id: String, didDownloadData totalBytesDownloaded: Int64, totalBytesEstimated: Int64?, completedFraction: Float)
    
    /// Item has changed state. in case state will be failed, the error will be provided (interupted state could also provide error).
    func item(id: String, didChangeToState newState: DTGItemState, error: Error?)
    
    /// The state of the internal web server has changed.
    func serverDidChangeState(_ state: DTGServerState)
}

// Default implementation of serverDidChangeState() to make it optional.
public extension ContentManagerDelegate {
    func serverDidChangeState(_ state: DTGServerState) {}
}

/// A downloadable item.
public protocol DTGItem {
    /// The item's unique id.
    var id: String { get }
    
    /// The items's remote URL.
    var remoteUrl: URL { get }
    
    /// The item's current state.
    var state: DTGItemState { get }
    
    /// Estimated size of the item.
    var estimatedSize: Int64? { get }
    
    /// Downloaded size in bytes.
    var downloadedSize: Int64 { get }
    
    /// Estimation of the completion status, 0.0 to 1.0. Suitable for use in `UIProgress.progress`.
    var completedFraction: Float { get }
        
    /// The selected text tracks for download (when download finishes this represents the downloaded tracks)
    var selectedTextTracks: [TrackInfo] { get }
    
    /// The selected audio tracks for download (when download finishes this represents the downloaded tracks)
    var selectedAudioTracks: [TrackInfo] { get }
}

/// Information about a Video track.
public protocol DTGVideoTrack {
    /// Width in pixels.
    var width: Int? { get }
    
    /// Height in pixels.
    var height: Int? { get }
    
    /// Bitrate.
    var bitrate: Int { get }
}

/// `DTGItemStartableState` represents startable states
public enum DTGItemStartableState {
    case inProgress, paused, interrupted
}

/// Item state.
public enum DTGItemState: Int, CaseIterable {
    /// Item was just added, no metadata is available except for the id and the URL.
    case new
    
    /// Item's metadata was loaded. Tracks information is available.
    case metadataLoaded
    
    /// Item download is in progress.
    case inProgress
    
    /// Item is paused by the app/user.
    case paused
    
    /// Item has finished downloading and processing.
    case completed
    
    /// Item download has failed (fatal error cannot use this item again).
    case failed
    
    /// Item download was interrupted (can be caused by error that we can recover from)
    /// 
    /// For example: when we can call start item again after this state.
    case interrupted
    
    /// Item is removed. This is only a temporary state, as the item is actually removed.
    case removed
    
    /// Item had a failure related to db access.
    /// If this state is sent make sure to save the id of the item to later try again.
    ///
    /// - Attention:
    /// It is important to keep this state seperatly because usually this will happen in a rare case
    /// where the device is out of storage and actions can't be made,
    /// meaning we cannot update item progress and its real state will be the last state that is was,
    /// for example for an item in the middle of a download that last state will be "in progress".
    /// if the storage will be available again we recommand removing the item and starting it again.
    case dbFailure
    
    init?(value: String) {
        switch value {
        case DTGItemState.new.asString(): self = .new
        case DTGItemState.metadataLoaded.asString(): self = .metadataLoaded
        case DTGItemState.inProgress.asString(): self = .inProgress
        case DTGItemState.paused.asString(): self = .paused
        case DTGItemState.completed.asString(): self = .completed
        case DTGItemState.failed.asString(): self = .failed
        case DTGItemState.interrupted.asString(): self = .interrupted
        case DTGItemState.removed.asString(): self = .removed
        case DTGItemState.dbFailure.asString(): self = .dbFailure
        default: return nil
        }
    }
    
    public func asString() -> String {
        switch self {
        case .new: return "new"
        case .metadataLoaded: return "metadataLoaded"
        case .inProgress: return "inProgress"
        case .paused: return "paused"
        case .completed: return "completed"
        case .failed: return "failed"
        case .interrupted: return "interrupted"
        case .removed: return "removed"
        case .dbFailure: return "dbFailure"
        }
    }
}

public enum LogLevel {
    case verbose
    case debug
    case info
    case warning
    case error
    
    func asXCGLoggerLevel() -> XCGLogger.Level {
        switch self {
        case .verbose: return .verbose
        case .debug: return .debug
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        }
    }
}

public typealias DTGRequestParams = (url: URL, headers: [String:String])

public protocol DTGRequestParamsAdapter: class {
    func adapt(_ params: DTGRequestParams) -> DTGRequestParams
}

/// The state of the internal web server.
public enum DTGServerState {
    /// Server is started and accepting connections.
    case started(serverUrl: URL?)
    
    /// Server is stopped.
    case stopped
    
    /// Server is handling requests.
    case connected(serverUrl: URL?)
    
    /// Server has finished handling requests (back to idle).
    case disconnected(serverUrl: URL?)
}
