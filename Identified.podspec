Pod::Spec.new do |s|
  s.name         = 'Identified'
  s.version      = '0.1.1'
  s.summary      = 'Native identity verification flow for the Identified API (iOS 16+).'
  s.description  = <<-DESC
    Consent, name, ID details, ID front and back, three-pose selfie, review and status, with
    UIKit and SwiftUI entry points. Camera, Vision and Core Image capture are bundled.
  DESC
  s.homepage     = 'https://identified.cc'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.author       = 'Identified'
  s.source       = { :git => 'https://github.com/fening/identified-ios-sdk.git', :tag => s.version.to_s }
  s.documentation_url = 'https://github.com/fening/identified-ios-sdk#readme'

  s.platform     = :ios, '16.0'
  s.swift_version = '6.0'
  s.source_files = 'Sources/Identified/**/*.swift'
  s.resource_bundles = {
    'IdentifiedResources' => [
      'Sources/Identified/Resources/*.png',
      'Sources/Identified/Resources/Fonts/*.{ttf,txt}',
      'Sources/Identified/Resources/*.lproj',
    ],
  }
  s.frameworks   = 'AVFoundation', 'CoreImage', 'CoreLocation', 'CoreText', 'ImageIO', 'PhotosUI',
                   'SwiftUI', 'UIKit', 'UniformTypeIdentifiers', 'Vision'
  s.dependency 'IdentifiedCore', s.version.to_s
  s.pod_target_xcconfig = { 'OTHER_SWIFT_FLAGS' => '$(inherited) -package-name identified' }
end
