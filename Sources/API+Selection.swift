// ===================================================================================================
// Copyright (C) 2019 Kaltura Inc.
//
// Licensed under the AGPLv3 license, unless a different license for a 
// particular library is specified in the applicable library path.
//
// You may obtain a copy of the License at
// https://www.gnu.org/licenses/agpl-3.0.html
// ===================================================================================================


import Foundation

public class DTGSelectionOptions {
    
    /// Initialize a new SelectionSettings object.
    /// The default behavior is as follows:
    /// - Video: select the track most suitable for the current device (codec, width, height)
    /// - Audio: select the default, as specified by the HLS playlist
    /// - Subtitles: select nothing
    public init() {}
    
    /// Audio languages to download.
    ///
    /// The languages are specified in ISO-639-1 (2 letters) or ISO-639-2 (3 letters) codes.
    ///
    /// Example: selecting French and German audio:
    /// ```
    /// ["fr", "de"]
    /// ```
    /// An empty array means not downloading extra audio tracks at all.
    public var audioLanguages: [String]? = nil {
        didSet {
            if audioLanguages != nil {
                allAudioLanguages = false
            }
        }
    }
    
    /// Text languages to download.
    ///
    /// The languages are specified in ISO-639-1 (2 letters) or ISO-639-2 (3 letters) codes.
    ///
    /// Example: selecting English subtitles:
    /// ```
    /// ["en"]
    /// ```
    /// An empty array means not downloading text tracks at all.
    public var textLanguages: [String]? = nil {
        didSet {
            if textLanguages != nil {
                allTextLanguages = false
            }
        }
    }
    
    /// Select all audio languages.
    public var allAudioLanguages: Bool = false {
        didSet {
            if allAudioLanguages {
                audioLanguages = nil
            }
        }
    }
    
    /// Select all subtitle languages.
    public var allTextLanguages: Bool = false {
        didSet {
            if allTextLanguages {
                textLanguages = nil
            }
        }
    }
    
    /// Preferred video codecs.
    ///
    /// The default is to allow all codecs in quality order: `[.hevc, .avc1]`.
    ///
    /// - Note:
    /// A given codec may be selected even if it isn't listed if there's no other way to satisfy the download.
    /// For example, if the list is `[.hevc]`, but the stream has only `avc1`, `avc1` will be selected. Likewise,
    /// if the list contains only `.hevc` but the device does not support it, `.avc1` will be selected.
    public var videoCodecs: [VideoCodec]? = nil 
    
    /// Preferred audio codecs.
    ///
    /// The default is to allow all codecs in quality order: [.eac3, .ac3, .mp4a].
    ///
    /// - Note:
    /// A given codec may be selected even if it isn't listed if there's no other way to satisfy the download.
    /// For example, if the list is `[.ac3, .eac3]`, but the stream has only `mp4a`, `mp4a` will be selected. Likewise,
    /// if the list contains only `.eac3` but the device does not support it, `.ac3` or `.mp4a` will be selected.
    public var audioCodecs: [AudioCodec]? = nil
    
    /// Preferred video width in pixels. DTG will prefer the smallest rendition that is large enough.
    public var videoWidth: Int? = nil
    
    /// Preferred video height in pixels. DTG will prefer the smallest rendition that is large enough.
    public var videoHeight: Int? = nil
    
    
    /// Preferred video bitrates, **per codec**.
    ///
    /// By default, the best bitrate for the device is selected.
    ///
    /// - Attention:
    /// When setting this property, it is advised to include the max bitrate for every codec.
    /// Otherwise, if a codec not on this list is selected for download, the selected
    /// bitrate is not defined.
    public var videoBitrates: [VideoCodec: Int] = [:]
    
    /// Allow or disallow codecs that are not implemented in hardware.
    /// iOS 11 and up support HEVC, but hardware support is only available in iPhone 7 and later.
    /// Using a software decoder causes higher energy consumption, affecting battery life.
    public var allowInefficientCodecs: Bool = false
    
    public enum VideoCodec: CaseIterable {
        
        /// AVC1 codec, AKA H.264
        case avc1
        
        /// HEVC codec, AKA HVC1 or H.265
        case hevc
    }
    
    public enum AudioCodec {
        /// MP4A
        case mp4a
        
        /// AC3: Dolby Atmos
        case ac3
        
        /// E-AC3: Dolby Digital Plus (Enhanced AC3)
        case eac3
    }
    
    // Convenience methods for setting the properties.
    
    @discardableResult
    public func setMinVideoWidth(_ width: Int) -> Self {
        self.videoWidth = width
        return self
    }
    
    @discardableResult
    public func setMinVideoHeight(_ height: Int) -> Self {
        self.videoHeight = height
        return self
    }
    
    @discardableResult
    public func setMinVideoBitrate(_ codec: VideoCodec, _ bitrate: Int) -> Self {
        self.videoBitrates[codec] = bitrate
        return self
    }
    
    @discardableResult
    public func setPreferredVideoCodecs(_ codecs: [VideoCodec]) -> Self {
        self.videoCodecs = codecs
        return self
    }
    
    @discardableResult
    public func setPreferredAudioCodecs(_ codecs: [AudioCodec]) -> Self {
        self.audioCodecs = codecs
        return self
    }
    
    @discardableResult
    public func setAudioLanguages(_ langs: [String]) -> Self {
        self.audioLanguages = langs
        return self
    }
    
    @discardableResult
    public func setTextLanguages(_ langs: [String]) -> Self {
        self.textLanguages = langs
        return self
    }
    
    @discardableResult
    public func setAllAudioLanguages(_ all: Bool = true) -> Self {
        self.allAudioLanguages = true
        return self
    }
    
    @discardableResult
    public func setAllTextLanguages(_ all: Bool = true) -> Self {
        self.allTextLanguages = true
        return self
    }
}
