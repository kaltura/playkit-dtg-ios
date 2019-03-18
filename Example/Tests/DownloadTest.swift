//
//  DownloadTest.swift
//  DownloadToGo_Tests
//
//  Created by Noam Tamim on 04/03/2019.
//  Copyright © 2019 CocoaPods. All rights reserved.
//

import XCTest
@testable import DownloadToGo

import PlayKit
import PlayKitProviders


class DownloadTest: XCTestCase, ContentManagerDelegate {
    
    var downloadedExp: XCTestExpectation?
    var id: String?
    
    static var items: [ItemJSON]!
    
    // It's not possible to play on travis because of the microphone permission issue (https://forums.developer.apple.com/thread/110423)
    #if targetEnvironment(simulator)
    static let dontPlay = FileManager.default.fileExists(atPath: "/tmp/DontPlay")
    #else
    static let dontPlay = false
    #endif    
    
    
    override class func setUp() {
        
        let jsonURL = Bundle.main.url(forResource: "items", withExtension: "json")!
        //        let jsonURL = URL(string: "http://localhost/items.json")!
        let json = try! Data(contentsOf: jsonURL)
        items = try! JSONDecoder().decode([ItemJSON].self, from: json)
        
        
        if dontPlay {
            print("TRAVIS DETECTED, WILL NOT PLAY")
        }
        
        let cm = ContentManager.shared
        
        try! cm.start { 
            print("QQQ started dtg")
        }
        
        for s in DTGItemState.allCases {
            for i in try! cm.itemsByState(s) {
                try! cm.removeItem(id: i.id)
                print("QQQ removed leftover item \(i.id)")
            }
        }
        
    }
    
    override class func tearDown() {
        let cm = ContentManager.shared
        cm.delegate = nil
        cm.stop()
    }
    
    override func setUp() {
        
        cm.delegate = self
    }
    
    override func tearDown() {
        guard let id = self.id else {return}
        try! cm.removeItem(id: id)
    }
    

    
    func item(id: String, didDownloadData totalBytesDownloaded: Int64, totalBytesEstimated: Int64?) {
        print(id, "\(Double(totalBytesDownloaded)/1024/1024) / \(Double(totalBytesEstimated ?? -1)/1024/1024)")
    }
    
    func item(id: String, didChangeToState newState: DTGItemState, error: Error?) {
        
        print("QQQ item \(id) moved to state \(newState)")
        
        if let selfId = self.id {
            if newState == .completed {
                assert(id == selfId, "Id doesn't match")
                print("QQQ item \(id) completed")
                
                // Check if it's in completed state
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    // Only in travis, sometimes it takes a while until the state is reflected in db.
                    eq(self.item().state, DTGItemState.completed)
                    self.downloadedExp?.fulfill()
                }
            }
        } else {
            // setUp
            assert(newState == .removed)
            print("QQQ Removed \(id) in setUp()")
        }
    }
    
    let cm = ContentManager.shared
    
    func waitForDownload(_ timeout: TimeInterval = 300) {
        if let e = downloadedExp {
            wait(for: [e], timeout: timeout)
            print("QQQ download fulfilled")
        }
    }
    
    
    func item(_ id: String) -> DTGItem? {
        if let item = try! cm.itemById(id) {
            return item
        }
        XCTFail("No item")
        return nil
    }
    
    func item() -> DTGItem {
        guard let id = self.id else {fatalError()}
        return self.item(id)!
    }
    
    func startItem() {
        guard let id = self.id else {return}
        downloadedExp = XCTestExpectation(description: "Download item")
        try! cm.startItem(id: id)
    }
    
    func newItem(_ url: String, _ function: String = #function) {        
        self.id = function
        
        try! cm.addItem(id: function, url: URL(string: url)!)
    }
    
    func loadItem(_ options: DTGSelectionOptions?) {
        guard let id = self.id else {return}
        try! cm.loadItemMetadata(id: id, options: options)
    }
    
    func allLangs() -> DTGSelectionOptions {
        return DTGSelectionOptions().setAllTextLanguages().setAllAudioLanguages()
    }
    
    func basic() -> DTGSelectionOptions {
        return DTGSelectionOptions()
    }
    
    func localEntry() -> PKMediaEntry {
        guard let id = self.id else {fatalError()}
        return PKMediaEntry(id, sources: [PKMediaSource(id, contentUrl: try! cm.itemPlaybackUrl(id: id))])
    }
    
    func playItem(audioLangs: [String] = [], textLangs: [String] = []) {
        
        if DownloadTest.dontPlay {
            print("Travis detected, not trying to play")
            return
        }
        
        let player = PlayKitManager.shared.loadPlayer(pluginConfig: nil)
        
        let canPlay = XCTestExpectation(description: "canPlay \(id!)")
        let tracks = XCTestExpectation(description: "tracks for \(id!)")
        
        player.addObserver(self, event: PlayerEvent.error) { (e) in
            print("QQQ Player error: \(String(describing: e.error))")
        }
        
        player.addObserver(self, event: PlayerEvent.tracksAvailable) { (e) in
            
            if let tracks = e.tracks {
                let textTracks = tracks.textTracks?.map{ $0.language ?? "??" } ?? []
                let audioTracks = tracks.audioTracks?.map{ $0.language ?? "??" } ?? []
                print("QQQ tracks for \(self.id!):", audioTracks, textTracks)
                
                for lang in audioLangs {
                    XCTAssert(audioTracks.contains(lang), "\(self.id!): \(audioTracks) does not contain \(lang)")
                }
                for lang in textLangs {
                    XCTAssert(textTracks.contains(lang), "\(self.id!): \(textTracks) does not contain \(lang)")
                }
            }
            tracks.fulfill()
        }
        
        let reached5sec = XCTestExpectation(description: "reached 5 seconds \(id!)")
        let ended = XCTestExpectation(description: "ended \(id!)")

        player.addObserver(self, event: PlayerEvent.playheadUpdate) { (e) in
            if let time = e.currentTime, time.floatValue >= 5.0 {
                print("QQQ reached 5 sec!")
                reached5sec.fulfill()
            }
        }
        
        player.addObserver(self, event: PlayerEvent.ended) { (e) in
            print("QQQ ended!")
            ended.fulfill()
        }
        
        player.addObserver(self, event: PlayerEvent.canPlay) { (e) in
            print("QQQ can play!")
            canPlay.fulfill()
        }
        
        let entry = localEntry()
        print("QQQ prepare \(entry)")
        player.prepare(MediaConfig(mediaEntry: entry))
        
        wait(for: [canPlay, tracks], timeout: 2)

        player.play()

        wait(for: [reached5sec], timeout: 6)
        
        player.seek(to: player.duration - 2)
        
        wait(for: [ended], timeout: 4)

        player.destroy()
    }
    
    func _testFromJSON() {
        for it in DownloadTest.items {
            
            guard let url = it.url else {continue}
            
            newItem(url, it.id)
            loadItem(it.options?.toOptions())
            
            if let est = it.expected?.estimatedSize {
                eq(item().estimatedSize, est)
            }
            
            startItem()
            waitForDownload()
            
            if let est = it.expected?.downloadedSize {
                eq(item().downloadedSize, est)
            }
            
            playItem()
        }
    }
    
    func testSmallBunny() {
        newItem("https://noamtamim.com/hls-bunny/index.m3u8")
        loadItem(basic().setMinVideoBitrate(.avc1, 100))
        eq(item().estimatedSize, 5066000)
        
        startItem()
        waitForDownload()
        
        eq(item().downloadedSize, 5156458)
        
        playItem()
    }
   
    func testBasicDownload_1() {
        newItem("http://cdntesting.qa.mkaltura.com/p/1091/sp/109100/playManifest/entryId/0_mskmqcit/format/applehttp/protocol/http/a.m3u8")
        loadItem(basic())
        
        eq(item().estimatedSize, 47_197_225)
        
        startItem()
        waitForDownload()
        
        eq(item().downloadedSize, 47_229_736)
        
        playItem()
    }
    
    func testBasicDownload_2() {
        newItem("http://cdntesting.qa.mkaltura.com/p/1091/sp/109100/playManifest/entryId/0_mskmqcit/format/applehttp/protocol/http/a.m3u8")
        loadItem(allLangs())
        
        eq(item().estimatedSize, 59_054_521)
        
        startItem()
        waitForDownload()
        
        eq(item().downloadedSize, 60_758_276)
        
        playItem(audioLangs: ["en", "es"], textLangs: ["en", "ru", "nl"])
    }
    
    func testBasicDownload_3() {
        newItem("http://cdntesting.qa.mkaltura.com/p/1091/sp/109100/playManifest/entryId/0_mskmqcit/format/applehttp/protocol/http/a.m3u8")
        loadItem(allLangs().setMinVideoWidth(2000))
        
        eq(item().estimatedSize, 171_385_356)
        
        startItem()
        waitForDownload()
        
        eq(item().downloadedSize, 168_808_644)
        
        playItem(audioLangs: ["en", "es"], textLangs: ["en", "ru", "nl"])
    }
    
    func testHEVC_1() {
        newItem("https://cdnapisec.kaltura.com/p/2215841/sp/2215841/playManifest/entryId/1_w9zx2eti/flavorIds/1_r6q0xdb6,1_yq8tg3pq,1_1obpcggb,1_huc2wn1a,1_yyuvftfz,1_3f4sp5qu,1_1ybsfwrp,1_1xdbzoa6,1_k16ccgto,1_djdf6bk8/deliveryProfileId/19201/protocol/https/format/applehttp/a.m3u8")
        loadItem(allLangs())
        
        eq(item().estimatedSize, Int64(883.148*(456999+64000)/8))
        
        startItem()
        waitForDownload()
        
        eq(item().downloadedSize, 63_101_824)
        
        playItem()
    }
    
    func testMultiAESKey() {
        newItem("https://noamtamim.com/random/hls/test-enc-aes/multi.m3u8")
        loadItem(nil)
        
        eq(item().estimatedSize, Int64(598.0333259999995*1000000/8))
        
        startItem()
        waitForDownload()
        
        eq(item().downloadedSize, 78_614_704)
        
        playItem()
    }
}

