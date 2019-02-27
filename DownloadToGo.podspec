Pod::Spec.new do |s|
  s.name             = 'DownloadToGo'
  s.version          = '3.5-dev'
  s.summary          = 'DownloadToGo -- download manager for HLS'
  s.homepage         = 'https://github.com/kaltura/playkit-ios-dtg'
  s.license          = { :type => 'AGPLv3', :file => 'LICENSE' }
  s.author           = { 'Kaltura' => 'community@kaltura.com' }
  s.source           = { :git => 'https://github.com/kaltura/playkit-ios-dtg.git', :tag => s.version.to_s }
  s.swift_version    = '4.0'

  s.ios.deployment_target = '8.0'

  s.source_files = 'Sources/**/*'

  s.dependency 'GCDWebServer', '~> 3.5.2'
  s.dependency 'RealmSwift', '~> 3.13.1'
  s.dependency 'XCGLogger', '~> 6.1.0'
  s.dependency 'PlayKitUtils', '~> 0.1.6'
end
