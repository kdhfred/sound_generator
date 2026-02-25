#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint sound_generator.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'sound_generator'
  s.version          = '0.0.12'
  s.summary          = 'A Flutter plugin for procedural sound generation.'
  s.description      = <<-DESC
A Flutter plugin for procedural sound generation using AVAudioEngine.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'AVFoundation'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'ENABLE_TESTABILITY' => 'YES' }
  s.swift_version = '5.0'
end
