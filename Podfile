platform :ios, '13.0'
use_frameworks!

target 'HyperFocus' do
  pod 'SnapKit', '~> 5.0'
  pod 'Toast-Swift', '~> 5.0.1'
  pod 'SWXMLHash', '~> 5.0.0'
  pod 'PromisesSwift'
  pod 'GRDB.swift'
  pod "CollectionKit", '~> 2.4.0'
  pod 'iCarousel'
  pod 'AMScrollingNavbar'
end

post_install do |installer|
  installer.pods_project.targets.select { |target| target.name == "GRDB.swift" }.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['OTHER_SWIFT_FLAGS'] = "$(inherited) -D SQLITE_ENABLE_FTS5"
    end
  end
end
