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
import RealmSwift

class DownloadItemTaskRealm: Object, RealmObjectProtocol, PrimaryKeyable {
    
    dynamic var dtgItemId: String = ""
    
    dynamic var contentUrl: String = ""

    dynamic var type: String = ""

    /// The destination to save the download item to.
    dynamic var destinationUrl: String = ""
    
    dynamic var resumeData: Data? = nil
    
    override static func primaryKey() -> String? {
        return "contentUrl"
    }
    
    var pk: String {
        return self.contentUrl
    }
    
    convenience init(object: DownloadItemTask) {
        self.init()
        self.dtgItemId = object.dtgItemId
        self.contentUrl = object.contentUrl.absoluteString
        self.type = object.type.asString()
        self.destinationUrl = object.destinationUrl.absoluteString.substring(from: DTGFilePaths.storagePath.absoluteString.endIndex)
        self.resumeData = object.resumeData
    }
    
    static func initialize(with object: DownloadItemTask) -> DownloadItemTaskRealm {
        return DownloadItemTaskRealm(object: object)
    }
    
    func asObject() -> DownloadItemTask {
        let contentUrl = URL(string: self.contentUrl)!
        let type = DownloadItemTaskType(type: self.type)!
        let destinationUrl = URL(string: self.destinationUrl, relativeTo: DTGFilePaths.storagePath)!
        var downloadItemTask = DownloadItemTask(dtgItemId: self.dtgItemId, contentUrl: contentUrl, type: type, destinationUrl: destinationUrl)
        if let resumeData = self.resumeData {
            downloadItemTask.resumeData = resumeData
        }
        
        return downloadItemTask
    }
}
