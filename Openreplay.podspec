Pod::Spec.new do |s|
  s.name             = 'Openreplay'
  s.version          = '1.0.26'
  s.summary          = 'IOS Library for Openreplay.'
  s.homepage         = 'https://github.com/openreplay/ios-tracker'
  s.license          = { :type => 'ELv2', :file => 'LICENSE.md' }
  s.author           = { 'Nick Delirium' => 'nikita@openreplay.com' }
  s.source           = { :git => 'https://github.com/openreplay/ios-tracker.git', :tag => s.version }
  s.ios.deployment_target = '13.0'
  s.swift_version = '5.10'
  s.source_files = 'Sources/OpenReplay/**/*.swift'
  # Same cap as Package.swift: SWCompression 4.9.0 raised its minimum to iOS 17,
  # so an open range breaks every consumer targeting iOS 13-16.
  s.dependency 'SWCompression', '~> 4.8.5'
  s.dependency 'DeviceKit'
end
