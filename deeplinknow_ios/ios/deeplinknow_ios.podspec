#
# iOS implementation of the `deeplinknow` Flutter plugin (endorsed as its default iOS package).
# All deferred-link logic lives in the native `DeepLinkNow` pod (FLT-01); the version range
# follows SDK-84 (FLT-03). The pod is not called `deeplinknow`: on a case-insensitive file system
# that name collides with the `DeepLinkNow` module (FLT-23).
#
Pod::Spec.new do |s|
  s.name             = 'deeplinknow_ios'
  s.version          = '1.4.0'
  s.summary          = 'iOS implementation of the deeplinknow Flutter plugin.'
  s.description      = <<-DESC
Flutter plugin for DeepLinkNow. A thin method-channel wrapper over the native DeepLinkNow iOS SDK:
pasteboard handoff, then fingerprint matching, to return the link the user tapped before installing.
                       DESC
  s.homepage         = 'https://deeplinknow.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'DeepLinkNow' => 'support@deeplinknow.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'deeplinknow_ios/Sources/deeplinknow_ios/**/*.swift'
  s.dependency 'Flutter'
  s.dependency 'DeepLinkNow', '~> 1.4.0'
  s.platform         = :ios, '13.0'
  # The DeepLinkNow pod is a static framework; a dynamic pod can't depend on it under
  # `use_frameworks!` (the Flutter Podfile default).
  s.static_framework = true

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.5'

  s.resource_bundles = { 'deeplinknow_ios_privacy' => ['deeplinknow_ios/Sources/deeplinknow_ios/PrivacyInfo.xcprivacy'] }
end
