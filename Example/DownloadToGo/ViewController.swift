//
//  ViewController.swift
//  DownloadToGo
//
//  Created by noamtamim on 07/07/2017.
//  Copyright (c) 2017 noamtamim. All rights reserved.
//

import UIKit
import DownloadToGo
import Toast
import PlayKit
import PlayKitProviders

let defaultAudioBitrateEstimation: Int = 64000

func maybeSetSmallDuration(entry: PKMediaEntry) {
    if let minutes = setSmallerOfflineDRMExpirationMinutes {
        entry.sources?.forEach({ (source) in
            if let drmData = source.drmData, let fpsData = drmData.first as? FairPlayDRMParams {
                var lic = fpsData.licenseUri!.absoluteString
                lic.append(contentsOf: "&rental_duration=\(minutes*60)")
                fpsData.licenseUri = URL(string: lic)
            }
        })
    }
}

class Item {
    static let defaultEnv = "http://cdnapi.kaltura.com"
    let id: String
    let title: String
    let partnerId: Int?
    
    var url: URL?
    var entry: PKMediaEntry?
    
    var options: DTGSelectionOptions?
    var expected: ExpectedValues?
    
    convenience init(json: ItemJSON) {
        let title = json.title ?? json.id
        
        if let partnerId = json.partnerId {
            self.init(title, id: json.id, partnerId: partnerId, ks: json.ks, env: json.env, ott: json.ott ?? false, ottParams: json.ottParams)
        } else if let url = json.url {
            self.init(title, id: json.id, url: url)
        } else {
            fatalError("Invalid item, missing `partnerId` and `url`")
        }
        self.options = json.options?.toOptions()
    }
    
    init(_ title: String, id: String, url: String) {
        self.id = id
        self.title = title
        self.url = URL(string: url)!
        
        let source = PKMediaSource(id, contentUrl: URL(string: url))
        self.entry = PKMediaEntry(id, sources: [source])
        
        self.partnerId = nil
    }
    
    init(_ title: String, id: String, partnerId: Int, ks: String? = nil, env: String? = nil, ott: Bool = false, ottParams: ItemOTTParamsJSON? = nil) {
        self.id = id
        self.title = title
        self.partnerId = partnerId
        self.url = nil
        
        let session = SimpleSessionProvider(serverURL: env ?? Item.defaultEnv, partnerId: Int64(partnerId), ks: ks)
        
        let provider: MediaEntryProvider
        
        if ott {
            let ottProvider = PhoenixMediaProvider().set(sessionProvider: session)
                .set(assetId: self.id)
                .set(type: .media)
            
            if let ottParams = ottParams {
                if let format = ottParams.format {
                    ottProvider.set(formats: [format])
                }
            }
            
            provider = ottProvider
            
        } else {
            provider = OVPMediaProvider(session)
                .set(entryId: id)
        }
        
        provider.loadMedia { (entry, error) in
            if let entry = entry {
                maybeSetSmallDuration(entry: entry)
                self.entry = entry
                
                print("entry: \(entry)")
                
            } else if let error = error {
                print("error: \(error)")
            }
        }
    }
}


func showJsonTemplate() {
    let json = try! JSONEncoder().encode([
        ItemJSON(id: "ID", title: "TITLE", partnerId: 1, ks: nil, env: "http://example.com", url: "http://example.com/master.m3u8", 
                 options: OptionsJSON(audioLangs: nil, allAudioLangs: false, textLangs: nil, allTextLangs: false, 
                                      videoCodecs: nil, audioCodecs: nil, videoWidth: nil, videoHeight: nil, videoBitrates: nil, 
                                      allowInefficientCodecs: nil), expected: nil, ott: true, 
                                                                    ottParams: ItemOTTParamsJSON(format: "FORMAT"))])
    
    print("JSON Template:", String(data: json, encoding: .utf8))
    
}


class ViewController: UIViewController {
    let dummyFileName = "dummyfile"
    let videoViewControllerSegueIdentifier = "videoViewController"
    
    let cm = ContentManager.shared
    let lam = LocalAssetsManager.managerWithDefaultDataStore()
    
    var items = [Item]()
    
    let itemPickerView = UIPickerView()
    
    let languageCodePickerView = UIPickerView()
    
    var selectedItem: Item! {
        didSet {
            do {
                let item = try cm.itemById(selectedItem.id)
                selectedDTGItem = item
                DispatchQueue.main.async {
                    self.statusLabel.text = item?.state.asString() ?? ""
                    if item?.state == .completed {
                        self.progressView.progress = 1.0
                    } else if let completedFraction = item?.completedFraction {
                        self.progressView.progress = completedFraction
                    } else {
                        self.progressView.progress = 0.0
                    }
                }
            } catch {
                // handle error here
                print("error: \(error.localizedDescription)")
            }
        }
    }
    
    var selectedDTGItem: DTGItem?
    
    var selectedTextLanguageCode: String?
    var selectedAudioLanguageCode: String?
    
    @IBOutlet weak var statusLabel: UILabel!
    @IBOutlet weak var itemTextField: UITextField!
    @IBOutlet weak var progressView: UIProgressView!
    @IBOutlet weak var languageCodeTextField: UITextField!
    @IBOutlet weak var progressLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let recognizer = UITapGestureRecognizer(target: self, action: #selector(showInfo(_:)))
        progressLabel.addGestureRecognizer(recognizer)
        
        let jsonURL = Bundle.main.url(forResource: "items", withExtension: "json")!
//        let jsonURL = URL(string: "http://localhost/items.json")!
        let json = try! Data(contentsOf: jsonURL)
        let loadedItems = try! JSONDecoder().decode([ItemJSON].self, from: json)
        
        items = loadedItems.map{Item(json: $0)}
        
        let completedItems = try! self.cm.itemsByState(.completed)
        for (index, item) in completedItems.enumerated() {
            if item.id.hasPrefix("test") && item.id.hasSuffix("()") {
                self.items.insert(Item(item.id, id: item.id, url: "file://foo.bar/baz"), at: index)
            }
        }

        cm.setDefaultAudioBitrateEstimation(bitrate: defaultAudioBitrateEstimation)

        // initialize UI
        selectedItem = items.first!
        itemPickerView.delegate = self
        itemPickerView.dataSource = self
        itemTextField.inputView = itemPickerView
        itemTextField.inputView?.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        itemTextField.text = items.first?.title ?? ""
        itemTextField.inputAccessoryView = getAccessoryView()
        
        languageCodePickerView.delegate = self
        languageCodePickerView.dataSource = self
        languageCodeTextField.inputView = languageCodePickerView
        languageCodeTextField.inputView?.autoresizingMask = [.flexibleHeight, .flexibleWidth]
        languageCodeTextField.inputAccessoryView = getAccessoryView()
        
        // setup content manager
        cm.delegate = self
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    @IBAction func addItem(_ sender: UIButton) {
        
        guard let entry = self.selectedItem.entry else {
            toast("No entry")
            return
        }
        
        guard let mediaSource = lam.getPreferredDownloadableMediaSource(for: entry) else {
            toast("No media source")
            return
        }
        
        print("Selected to download: \(String(describing: mediaSource.contentUrl))")
        
        var item: DTGItem?
        do {
            item = try cm.itemById(entry.id)
            if item == nil {
                item = try cm.addItem(id: entry.id, url: mediaSource.contentUrl!)
            }
        } catch {
            toast("Can't add item: " + error.localizedDescription)
            return
        }

        guard let dtgItem = item else {
            toast("Can't add item")
            return
        }
        
        self.statusLabel.text = dtgItem.state.asString()
        
        DispatchQueue.global().async {
            do {
                
                var options: DTGSelectionOptions
                
                options = DTGSelectionOptions()
                    .setMinVideoHeight(300)
//                    .setMinVideoWidth(1000)
                    .setMinVideoBitrate(.avc1, 3_000_000)
                    .setMinVideoBitrate(.hevc, 5_000_000)
                    .setPreferredVideoCodecs([.hevc, .avc1])
                    .setPreferredAudioCodecs([.ac3, .mp4a])
                    .setAllTextLanguages()
//                    .setTextLanguages(["en"])
//                    .setAudioLanguages(["en", "ru"])
                    .setAllAudioLanguages()
                
                options.allowInefficientCodecs = true
                                
//                options = DTGSelectionOptions()
//                    .setTextLanguages(["he", "eng"])
//                    .setAudioLanguages(["fr", "de"])
//                    .setMinVideoHeight(600)
//                    .setMinVideoWidth(800)
//                
//                options = DTGSelectionOptions()
//                    .setPreferredVideoCodecs([.hevc])
//                    .setPreferredAudioCodecs([.ac3])
//                
//                options = DTGSelectionOptions()
                
                
                
                
                
                
                try self.cm.loadItemMetadata(id: self.selectedItem.id, options: self.selectedItem.options)
//                try self.cm.loadItemMetadata(id: self.selectedItem.id, preferredVideoBitrate: 300000)
                print("Item Metadata Loaded")
                
            } catch {
                DispatchQueue.main.async {
                    self.toast("loadItemMetadata failed \(error)")
                }
            }
        }
    }
    
    @IBAction func start(_ sender: UIButton) {
        do {
            try cm.startItem(id: self.selectedItem.id)
        } catch {
            toast(error.localizedDescription)
        }
    }
    
    @IBAction func pause(_ sender: UIButton) {
        do {
            try cm.pauseItem(id: self.selectedItem.id)
        } catch {
            toast(error.localizedDescription)
        }
    }
    
    @IBAction func remove(_ sender: UIButton) {
        let id = self.selectedItem.id
        do {
            guard let url = try self.cm.itemPlaybackUrl(id: id) else {
                toast("Can't get local url")
                return
            }
            
            lam.unregisterDownloadedAsset(location: url, callback: { (error) in
                DispatchQueue.main.async {
                    self.toast("Unregister complete")
                }
            })
            
            try? cm.removeItem(id: id)
            
        } catch {
            toast(error.localizedDescription)
        }
    }
    
    @IBAction func renew(_ sender: UIButton) {
        let id = self.selectedItem.id
        do {
            guard let url = try self.cm.itemPlaybackUrl(id: id) else {
                toast("Can't get local url")
                return
            }
            
            guard let entry = self.selectedItem.entry, 
                let source = lam.getPreferredDownloadableMediaSource(for: entry) else {
                    
                    toast("No valid source")
                    return
            }
                        
            lam.renewDownloadedAsset(location: url, mediaSource: source) { (error) in
                DispatchQueue.main.async {
                    if let e = error {
                        self.toast("Failed with \(e)")
                    } else {
                        self.toast("Renew complete")
                    }
                }
            }
            
        } catch {
            toast(error.localizedDescription)
        }
    }

    @IBAction func checkStatus(_ sender: UIButton) {
        let id = self.selectedItem.id
        do {
            guard let url = try self.cm.itemPlaybackUrl(id: id) else {
                toast("Can't get local url")
                return
            }
            
            guard let exp = lam.getLicenseExpirationInfo(location: url) else {
                toast("Unknown")
                return
            }
            
            let expString = DateFormatter.localizedString(from: exp.expirationDate, dateStyle: .long, timeStyle: .long)
            
            if exp.expirationDate < Date() {
                toast("EXPIRED at \(expString)")
            } else {
                toast("VALID until \(expString)")
            }
            
        } catch {
            toast(error.localizedDescription)
        }
    }
    
    @IBAction func showInfo(_ sender: UIButton) {
        
        func name(_ code: String?) -> String {
            if let code = code {
                return Locale.current.localizedString(forLanguageCode: code) ?? (code + "?")
            }
            return "<unknown>"
        }
        
        var msg = ""
        do {
            if let item = try cm.itemById(selectedItem.id) {
                let audioLangs = item.selectedAudioTracks.map {name($0.languageCode)}
                let textLangs = item.selectedTextTracks.map {name($0.languageCode)}
                
                msg.append("Est. size: " + String(format: "%.3f MB", Double(item.estimatedSize ?? 0) / 1024 / 1024))
                msg.append("\nDL size: " + String(format: "%.3f MB", Double(item.downloadedSize) / 1024 / 1024))
                
                if audioLangs.count > 0 {
                    msg.append("\nAudio: " + audioLangs.joined(separator: ", "))
                }
                if textLangs.count > 0 {
                    msg.append("\nText: " + textLangs.joined(separator: ", "))
                }
            }
            
        } catch {
            msg.append(error.localizedDescription)
        }
        
        toast(msg)
    }
    
    @IBAction func actionBarButtonTouched(_ sender: UIBarButtonItem) {
        let actionAlertController = UIAlertController(title: "Perform Action", message: "Please select an action to perform", preferredStyle: .actionSheet)
        // fille device with dummy file action
        actionAlertController.addAction(UIAlertAction(title: "Fill device disk using dummy file", style: .default, handler: { (action) in
            let dialog = UIAlertController(title: "Fill Disk", message: "Please put the amount of MB to fill disk", preferredStyle: .alert)
            dialog.addTextField(configurationHandler: { (textField) in
                textField.placeholder = "Size in MB"
                textField.keyboardType = .numberPad
            })
            dialog.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) in
                guard let text = dialog.textFields?.first?.text, let sizeInMb = Int(text) else { return }
                let fileManager = FileManager.default
                if let dir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
                    let fileUrl = dir.appendingPathComponent(self.dummyFileName, isDirectory: false).appendingPathExtension("txt")
                    if !fileManager.fileExists(atPath: fileUrl.path) {
                        fileManager.createFile(atPath: fileUrl.path, contents: Data(), attributes: nil)
                    }
                    do {
                        let fileHandle = try FileHandle(forUpdating: fileUrl)
                        autoreleasepool {
                            for _ in 1...sizeInMb {
                                fileHandle.write(Data.init(count: 1000000))
                            }
                        }
                        fileHandle.closeFile()
                        DispatchQueue.main.async {
                            self.toast("Finished Filling Device with Dummy Data")
                        }
                    } catch {
                        print("error: \(error)")
                    }
                }
            }))
            dialog.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            self.present(dialog, animated: true, completion: nil)
        }))
        // update dummy file size action
        actionAlertController.addAction(UIAlertAction(title: "Update dummy file size", style: .default, handler: { (action) in
            let dialog = UIAlertController(title: "Update Dummy file Size", message: "Please put the amount of MB to reduce from dummy file", preferredStyle: .alert)
            dialog.addTextField(configurationHandler: { (textField) in
                textField.placeholder = "Size in MB"
                textField.keyboardType = .numberPad
            })
            dialog.addAction(UIAlertAction(title: "OK", style: .default, handler: { (action) in
                guard let text = dialog.textFields?.first?.text, let sizeInMb = Int(text) else { return }
                let fileManager = FileManager.default
                if let dir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
                    let fileUrl = dir.appendingPathComponent(self.dummyFileName, isDirectory: false).appendingPathExtension("txt")
                    guard fileManager.fileExists(atPath: fileUrl.path) else { return } // make sure file exits
                    do {
                        let fileHandle = try FileHandle(forUpdating: fileUrl)
                        fileHandle.truncateFile(atOffset: fileHandle.seekToEndOfFile() - UInt64(sizeInMb * 1000000))
                        fileHandle.closeFile()
                        DispatchQueue.main.async {
                            self.toast("Finished Updating Device Dummy Data File")
                        }
                    } catch {
                        print("error: \(error)")
                    }
                }
            }))
            dialog.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
            self.present(dialog, animated: true, completion: nil)
        }))
        // remove dummy file action
        actionAlertController.addAction(UIAlertAction(title: "Remove dummy file", style: .default, handler: { (action) in
            let fileManager = FileManager.default
            if let dir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first {
                let fileUrl = dir.appendingPathComponent(self.dummyFileName, isDirectory: false).appendingPathExtension("txt")
                do {
                    try fileManager.removeItem(at: fileUrl)
                } catch {
                    print("error: \(error)")
                }
            }
        }))
        
        self.present(actionAlertController, animated: true, completion: nil)
    }
    
    func getAccessoryView() -> UIView {
        let toolBar = UIToolbar(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: 44))
        let doneButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(self.doneButtonTapped(button:)))
        toolBar.items = [doneButton]
        
        return toolBar
    }
    
    @objc func doneButtonTapped(button: UIBarButtonItem) -> Void {
        do {
            let item = try cm.itemById(self.selectedItem.id)
            self.statusLabel.text = item?.state.asString()
            self.itemTextField.resignFirstResponder()
            self.languageCodeTextField.resignFirstResponder()
        } catch {
            // handle db issues here...
            print("error: \(error.localizedDescription)")
        }
    }
    
    func toast(_ message: String, _ duration: TimeInterval = 0) {
        print("[TOAST]", message)
        self.view!.makeToast(message, 
                             duration: duration > 0 ? duration : Double(message.count) * 0.050, 
                             position: CSToastPositionCenter)
    }
}

/************************************************************/
// MARK: - Navigation
/************************************************************/

extension ViewController {
    
    override func shouldPerformSegue(withIdentifier identifier: String, sender: Any?) -> Bool {
        do {
            if identifier == self.videoViewControllerSegueIdentifier {
                guard let item = try cm.itemById(self.selectedItem.id) else {
                    toast("cannot segue to video view controller until download is finished")
                    return false
                }
                if item.state == .completed {
                    return true
                }
                toast("cannot segue to video view controller until download is finished")
                return false
            }
        } catch {
            // handle db issues here...
            print("error: \(error.localizedDescription)")
        }
        return true
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == self.videoViewControllerSegueIdentifier {
            let destinationVC = segue.destination as! VideoViewController
            do {
                destinationVC.contentUrl = try self.cm.itemPlaybackUrl(id: self.selectedItem.id)
                destinationVC.textLanguageCode = self.selectedTextLanguageCode
                destinationVC.audioLanguageCode = self.selectedAudioLanguageCode
            } catch {
                print("error: \(error.localizedDescription)")
            }
        }
    }
}

/************************************************************/
// MARK: - ContentManagerDelegate
/************************************************************/

extension ViewController: ContentManagerDelegate {
    func item(id: String, didDownloadData totalBytesDownloaded: Int64, totalBytesEstimated: Int64?, completedFraction: Float) {
        if id != selectedItem.id {return}   // only update the view for selected item.
        
        PKLog.debug("item=\(id) completedFraction=\(completedFraction)")
        
        DispatchQueue.main.async {
            self.progressView.progress = completedFraction
            self.view.layoutIfNeeded()
        }
    }
    
    func item(id: String, didChangeToState newState: DTGItemState, error: Error?) {
        DispatchQueue.main.async {
            if newState == .completed && id == self.selectedItem.id {
                self.progressView.progress = 1.0
            } else if newState == .removed && id == self.selectedItem.id {
                self.progressView.progress = 0.0
            } else if newState == .failed {
                print("error: \(String(describing: error?.localizedDescription))")
            }
            self.statusLabel.text = newState.asString()
        }
    }
    
    func serverDidChangeState(_ state: DTGServerState) {
        print("serverDidChangeState: \(state)")
    }
}

/************************************************************/
// MARK: - UIPickerViewDataSource
/************************************************************/

extension ViewController: UIPickerViewDataSource {
    
    func numberOfComponents(in pickerView: UIPickerView) -> Int {
        if pickerView === self.languageCodePickerView {
            return 2
        } else {
            return 1
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, numberOfRowsInComponent component: Int) -> Int {
        if pickerView === self.languageCodePickerView {
            guard let item = selectedDTGItem else { return 0 }
            if component == 0 {
                return item.selectedTextTracks.count
            } else {
                return item.selectedAudioTracks.count
            }
        } else {
            return self.items.count
        }
    }
}

/************************************************************/
// MARK: - UIPickerViewDelegate
/************************************************************/

extension ViewController: UIPickerViewDelegate {
    
    func pickerView(_ pickerView: UIPickerView, titleForRow row: Int, forComponent component: Int) -> String? {
        if pickerView === self.languageCodePickerView {
            guard let item = selectedDTGItem else { return "" }
            if component == 0 {
                return item.selectedTextTracks[row].title
            } else {
                return item.selectedAudioTracks[row].title
            }
        } else {
            return items[row].title
        }
    }
    
    func pickerView(_ pickerView: UIPickerView, didSelectRow row: Int, inComponent component: Int) {
        if pickerView === self.languageCodePickerView {
            guard let item = selectedDTGItem else { return }
            if component == 0 {
                guard item.selectedTextTracks.count > 0 else { return }
                self.selectedTextLanguageCode = item.selectedTextTracks[row].languageCode
            } else {
                guard item.selectedAudioTracks.count > 0 else { return }
                self.selectedAudioLanguageCode = item.selectedAudioTracks[row].languageCode
            }
            self.languageCodeTextField.text = "text code: \(self.selectedTextLanguageCode ?? ""), audio code: \(self.selectedAudioLanguageCode ?? "")"
        } else {
            self.itemTextField.text = items[row].title
            self.selectedItem = items[row]
        }
    }
}
