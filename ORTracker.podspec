Pod::Spec.new do |s|
  s.name             = 'ORTracker'
  s.version          = '1.0.1'
  s.summary          = 'IOS Library for Openreplay.'
  s.homepage         = 'https://github.com/openreplay/iOS-SDK'
  s.license          = { :type => 'ELv2', :file => 'LICENSE.md' }
  s.author           = { 'Nick Delirium' => 'nikita@openreplay.com' }
  s.source           = { :git => 'https://github.com/openreplay/iOS-SDK.git', :tag => s.version }
  s.ios.deployment_target = '13.0'
  s.swift_version = '5.0'
  s.source_files = 'Sources/ORTracker/**/*'
  s.dependency 'SWCompression'
  s.dependency 'DeviceKit'
end
