Pod::Spec.new do |s|
  s.name         = 'IdentifiedCore'
  s.version      = '0.1.1'
  s.summary      = 'Foundation-only core of the Identified iOS SDK. Install Identified instead.'
  s.description  = <<-DESC
    Models, API client and flow engine used by the Identified SDK. Not a public API: it exists
    as its own pod because the SDK is split into two Swift modules. Add `pod 'Identified'`.
  DESC
  s.homepage     = 'https://identified.cc'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = 'Identified'
  s.source       = { :git => 'https://github.com/fening/identified-ios-sdk.git', :tag => s.version.to_s }

  s.platform     = :ios, '16.0'
  s.swift_version = '6.0'
  s.source_files = 'Sources/IdentifiedCore/**/*.swift'
  # The two modules share `package` access, as they do under SwiftPM.
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name identified' }
end
