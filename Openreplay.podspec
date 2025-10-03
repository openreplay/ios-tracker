Pod::Spec.new do |s|
  s.name             = 'Openreplay'
  s.version          = '1.0.19'
  s.summary          = 'IOS Library for Openreplay.'
  s.homepage         = 'https://github.com/openreplay/ios-tracker'
  s.license          = { :type => 'ELv2', :file => 'LICENSE.md' }
  s.author           = { 'Nick Delirium' => 'nikita@openreplay.com' }
  s.source           = { :git => 'https://github.com/openreplay/ios-tracker.git', :tag => s.version }
  s.ios.deployment_target = '13.0'
  s.swift_version = '5.10'
  s.source_files = 'Sources/OpenReplay/**/*'
  s.dependency 'SWCompression'
  s.dependency 'DeviceKit'
end
