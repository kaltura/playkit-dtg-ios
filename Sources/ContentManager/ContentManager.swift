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
import GCDWebServer
import XCGLogger
import PlayKitUtils

let log = XCGLogger.default

/************************************************************/
// MARK: - DownloadItemTaskType
/************************************************************/

enum DownloadItemTaskType {
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
}

/************************************************************/
// MARK: - DTGError
/************************************************************/

public enum DTGError: Error {
    case itemNotFound(itemId: String)
    /// sent when item cannot be started (casued when item state is other than metadata loaded)
    case invalidState(itemId: String)
}

/************************************************************/
// MARK: - DownloadItem
/************************************************************/

struct DownloadItem: DTGItem {
    var id: String
    var remoteUrl: URL
    var state: DTGItemState = .new
    var estimatedSize: Int64?
    var downloadedSize: Int64 = 0
    
    init(id: String, url: URL) {
        self.id = id
        self.remoteUrl = url
    }
}

/************************************************************/
// MARK: - DTGFilePaths
/************************************************************/

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

/************************************************************/
// MARK: - ContentManager
/************************************************************/

public class ContentManager: NSObject, DTGContentManager {
    
    /// shared singleton object
    public static let shared: DTGContentManager = ContentManager()
    
    /// Version string
    public static let versionString: String = Bundle(for: ContentManager.self).object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
    /// The client tag
    public static let clientTag = "playkit-dtg/ios-\(versionString)"
    /// session id, lives as long as the app is alive.
    let sessionId = UUID()
    /// A custom referrer, used for requesting the play manifest, if no referrer is set app id is used.
    public var referrer: String?
    
    public weak var delegate: ContentManagerDelegate?

    public var storagePath: URL {
        return DTGFilePaths.storagePath
    }
    
    var started = false
    var server = GCDWebServer()!
    var serverUrl: URL? {
        return server.isRunning ? server.serverURL : nil
    }
    var serverPort: UInt?
    var startCompletionHandler: (() -> Void)?
    
    // db interface instance
    let db: DB
    
    // Map of item id and the related downloader
    fileprivate var downloaders = [String: Downloader]()
    
    private override init() {
        /// create main directory
        try! FileManager.default.createDirectory(at: DTGFilePaths.storagePath, withIntermediateDirectories: true, attributes: nil)
        
        /// exclude url from from backup
        var url: URL = DTGFilePaths.storagePath
        do {
            var resourceValues = URLResourceValues()
            resourceValues.isExcludedFromBackup = true
            try url.setResourceValues(resourceValues)
        } catch let error as NSError {
            print("Error excluding \(url.lastPathComponent) from backup \(error)");
        }
        
        // initialize db
        self.db = RealmDB()
        super.init()
        // setup log default log level
        #if DEBUG
            let logLevel: XCGLogger.Level = .debug
        #else
            let logLevel: XCGLogger.Level = .info
        #endif
        log.setup(level: logLevel, showLevel: true, showFileNames: true, showLineNumbers: true, showDate: true)
        log.debug("*** ContentManager ***")
    }
    
    private func startServer() throws {
        // start server
        server.addGETHandler(forBasePath: "/", directoryPath: DTGFilePaths.itemsDirUrl.path, indexFilename: nil, cacheAge: 3600, allowRangeRequests: true)
        try server.start(options: [
            GCDWebServerOption_BindToLocalhost: true,
            GCDWebServerOption_Port: 0,
            ])

        serverPort = server.port
        
        // Stop the server, then restart it on a fixed port. 
        server.stop()
        server.delegate = self
        try server.start(options: [
            GCDWebServerOption_BindToLocalhost: true,
            GCDWebServerOption_Port: serverPort!,
            ])        
    }
    
    public func start(completionHandler: (() -> Void)?) throws {
        if started {
            return
        }

        self.startCompletionHandler = completionHandler
        
        try startServer()

        started = true
    }
    
    public func stop() {
        // stop server
        server.stop()
        started = false
    }

    public func startItems(inStates states: DTGItemStartableState...) throws {
        if states.contains(.inProgress) {
            for item in try itemsByState(.inProgress) {
                try startItem(id: item.id)
            }
        }
        if states.contains(.paused) {
            for item in try itemsByState(.paused) {
                try startItem(id: item.id)
            }
        }
        if states.contains(.interrupted) {
            for item in try itemsByState(.interrupted) {
                try startItem(id: item.id)
            }
        }
    }

    public func itemsByState(_ state: DTGItemState) throws -> [DTGItem] {

        return try db.items(byState: state)
    }
    
    public func itemById(_ id: String) throws -> DTGItem? {
        
        return try db.item(byId: id)
    }
    
    public func addItem(id: String, url: URL) throws -> DTGItem? {
        
        if try db.item(byId: id) != nil {
            return nil
        }
        
        let item = DownloadItem(id: id, url: url)
        try self.update(item: item)

        return item
    }

    public func loadItemMetadata(id: String, preferredVideoBitrate: Int?) throws {
        var item = try findItemOrThrow(id)
        // can only load metadata on item in `.new` state.
        guard item.state == .new else { throw DTGError.invalidState(itemId: id) }
        
        let referrer = (self.referrer == nil ? Bundle.main.bundleIdentifier ?? "" : self.referrer!).data(using: .utf8)?.base64EncodedString() ?? ""
        let requestAdapter = PlayManifestRequestAdapter(url: item.remoteUrl, sessionId: self.sessionId.uuidString, clientTag: ContentManager.clientTag, referrer: referrer, playbackType: "offline")
        let localizer = HLSLocalizer(id: id, url: requestAdapter.adapt(), downloadPath: DTGFilePaths.itemDirUrl(forItemId: id), preferredVideoBitrate: preferredVideoBitrate)
        
        try localizer.loadMetadata()
        try localizer.saveLocalFiles()
        // when localizer finished add the tasks and update the item
        try self.db.set(tasks: localizer.tasks)
        item.state = .metadataLoaded
        item.estimatedSize = localizer.estimatedSize
        try self.update(item: item)
    }
    
    public func startItem(id: String) throws {
        // find in db
        let item = try findItemOrThrow(id)
        
        // for item to start downloading state must be metadataLoaded/paused or inProgress + no active downloader for the selected id.
        guard item.state == .metadataLoaded || item.state == .paused || item.state == .interrupted || (item.state == .inProgress && self.downloaders[id] == nil) else {
            throw DTGError.invalidState(itemId: id)
        }
        
        // make sure we have tasks to perform
        let tasks = try db.tasks(forItemId: id)
        guard tasks.count > 0 else {
            log.warning("no tasks for this id")
            // if an item was started and his state allows to start and has no tasks set the state to completed.
            try self.update(itemState: .completed, byId: id)
            return
        }
        
        try self.update(itemState: .inProgress, byId: id)
        
        let downloader = DefaultDownloader(itemId: id, tasks: tasks)
        downloader.delegate = self
        self.downloaders[id] = downloader
        try downloader.start()
    }

    public func pauseItem(id: String) throws {
        try findItemOrThrow(id)

        // if in progress, tell download manager to pause
        guard let downloader = self.downloaders[id] else {
            log.warning("no downloader for this id")
            return
        }
        // update state, changed before downloader delegate called
        // to make sure every call to db to get item will be with the updated state.
        try self.update(itemState: .paused, byId: downloader.dtgItemId)
        // pause the downloads and remove the downloader
        downloader.pause()
    }

    public func removeItem(id: String) throws {
        try findItemOrThrow(id)

        // if in progress, cancel
        if let downloader = self.downloaders[id] {
            downloader.cancel()
            self.downloaders[id] = nil
        }
        
        // remove from db
        try db.removeItem(byId: id)
        
        // remove all files
        let itemPath = DTGFilePaths.itemDirUrl(forItemId: id)
        let fileManager = FileManager.default
        var isDir: ObjCBool = true
        if fileManager.fileExists(atPath: itemPath.path, isDirectory:&isDir) {
            if isDir.boolValue {
                // file exists and is a directory
                try fileManager.removeItem(at: itemPath)
            } else {
                // file exists and is not a directory
            }
        } else {
            log.warning("can't remove item files, dir doesn't exist")
        }
        
        // notify state change
        self.notifyItemState(id, newState: .removed, error: nil)
    }

    public func itemPlaybackUrl(id: String) throws -> URL? {
        return serverUrl?.appendingPathComponent("\(id.safeItemPathName())/master.m3u8")
    }
    
    public func handleEventsForBackgroundURLSession(identifier: String, completionHandler: @escaping () -> Void) {
        for (_, downloader) in self.downloaders {
            if downloader.sessionIdentifier == identifier {
                downloader.backgroundSessionCompletionHandler = completionHandler
                break
            }
        }
    }
    
    public func setup() throws {
        // gets the realm instance, when migration is needed sets up the new scheme and migration block.
        _ = try getRealm()
    }
}

/************************************************************/
// MARK: - GCDWebServerDelegate
/************************************************************/

extension ContentManager: GCDWebServerDelegate {
    
    public func webServerDidStart(_ server: GCDWebServer!) {
        self.startCompletionHandler?()
        self.startCompletionHandler = nil
    }
}


/************************************************************/
// MARK: - DownloaderDelegate
/************************************************************/

extension ContentManager: DownloaderDelegate {
    
    func downloader(_ downloader: Downloader, didProgress bytesWritten: Int64) {
        do {
            guard var item = try self.db.item(byId: downloader.dtgItemId) else {
                log.warning("no item for request id")
                return
            }
            // when we receive progress for downloads when downloader is pasued make sure item state is pasued
            // otherwise because the delegate and db are async we can receive an item with state `inProgress` before the change was made.
            if downloader.state == .paused {
                item.state = .paused
            }
            item.downloadedSize += bytesWritten
            try self.update(item: item)
            self.delegate?.item(id: downloader.dtgItemId, didDownloadData: item.downloadedSize, totalBytesEstimated: item.estimatedSize)
        } catch {
            // remove the downloader, data storage has an issue or is full no need to keep downloading for now.
            self.removeDownloader(withId: downloader.dtgItemId)
            self.notifyItemState(downloader.dtgItemId, newState: .dbFailure, error: error)
        }
    }
    
    func downloader(_ downloader: Downloader, didPauseDownloadTasks tasks: [DownloadItemTask]) {
        log.info("downloading paused")
        self.removeDownloader(withId: downloader.dtgItemId)
        do {
            // save pasued tasks to db
            try self.db.update(tasks)
        } catch {
            self.notifyItemState(downloader.dtgItemId, newState: .dbFailure, error: error)
        }
    }
    
    func downloaderDidCancelDownloadTasks(_ downloader: Downloader) {
        // clear the downloader instance
        self.removeDownloader(withId: downloader.dtgItemId)
        do {
            // removes all tasks from the db
            try self.db.removeTasks(withItemId: downloader.dtgItemId)
        } catch {
            self.notifyItemState(downloader.dtgItemId, newState: .dbFailure, error: error)
        }
    }
    
    func downloader(_ downloader: Downloader, didFinishDownloading downloadItemTask: DownloadItemTask) {
        do {
            // remove the task from the db tasks objects
            try self.db.remove([downloadItemTask])
        } catch {
            // remove the downloader, data storage has an issue or is full no need to keep downloading for now.
            self.removeDownloader(withId: downloader.dtgItemId)
            self.notifyItemState(downloader.dtgItemId, newState: .dbFailure, error: error)
        }
    }
    
    func downloader(_ downloader: Downloader, didChangeToState newState: DownloaderState) {
        log.debug("downloader state: \(newState.rawValue)")
        if newState == .idle {
            try? self.update(itemState: .completed, byId: downloader.dtgItemId)
            // remove the downloader, no longer needed
            self.removeDownloader(withId: downloader.dtgItemId)
        }
    }
    
    func downloader(_ downloader: Downloader, didFailWithError error: Error) {
        do {
            switch error {
            case DownloaderError.http(let statusCode, let rootError):
                if statusCode >= 500 {
                    try self.update(itemState: .interrupted, byId: downloader.dtgItemId, error: rootError)
                } else {
                    try self.update(itemState: .failed, byId: downloader.dtgItemId, error: error)
                }
            default: try self.update(itemState: .interrupted, byId: downloader.dtgItemId, error: error)
            }
        } catch {
            self.removeDownloader(withId: downloader.dtgItemId)
            self.notifyItemState(downloader.dtgItemId, newState: .dbFailure, error: error)
        }
    }
}

/************************************************************/
// MARK: - Private Implementation
/************************************************************/

private extension ContentManager {
    
    func update(item: DownloadItem) throws {
        if item.state == .failed {
            try self.removeItem(id: item.id)
            self.notifyItemState(item.id, newState: item.state, error: nil)
        } else {
            let oldItem = try self.db.item(byId: item.id)
            try db.update(item: item)
            if oldItem?.state != item.state {
                self.notifyItemState(item.id, newState: item.state, error: nil)
            }
        }
    }
    
    func update(itemState: DTGItemState, byId id: String, error: Error? = nil) throws {
        if itemState == .failed {
            try self.removeItem(id: id)
        } else {
            try self.db.update(itemState: itemState, byId: id)
        }
        self.notifyItemState(id, newState: itemState, error: error)
    }
    
    @discardableResult
    func findItemOrThrow(_ id: String) throws -> DownloadItem {
        if let item = try db.item(byId: id) {
            return item
        } else {
            throw DTGError.itemNotFound(itemId: id)
        }
    }
    
    func notifyItemState(_ id: String, newState: DTGItemState, error: Error? = nil) {
        log.info("item: \(id), state updated, new state: \(newState.asString())")
        DispatchQueue.main.async {
            self.delegate?.item(id: id, didChangeToState: newState, error: error)
        }
    }
    
    func removeDownloader(withId itemId: String) {
        let downloader = self.downloaders[itemId]
        downloader?.invalidateSession()
        self.downloaders[itemId] = nil
    }
}
