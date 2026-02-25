#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint sound_generator.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'sound_generator'
  s.version          = '0.0.11'
  s.summary          = 'A new Flutter plugin.'
  s.description      = <<-DESC
A new Flutter plugin.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.', :submodules => true }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  # TODO: We actually require >=4.11.1 and <5
  s.dependency 'AudioKit', '<5'
  s.static_framework = true
  s.platform = :ios, '13.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'ENABLE_TESTABILITY' => 'YES' }
  s.swift_version = '5.0'
  s.library = 'c++'
  s.xcconfig = {
    'USER_HEADER_SEARCH_PATHS' => '"${PROJECT_DIR}/.."/Classes/CallbackManager/*,"${PROJECT_DIR}/.."/Classes/Scheduler/*',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2a',
    'CLANG_CXX_LIBRARY' => 'libc++'
  }
end
