# Consumed from Git. The owner may also push a release to CocoaPods trunk by hand until
# trunk goes read-only on December 2, 2026. Later versions come from Git only.
Pod::Spec.new do |s|
  s.name = 'Cerebro'
  s.version = '1.0.1'
  s.summary = 'A debug-only network inspector and file browser for iOS apps.'
  s.description = <<~DESC
    Cerebro captures an iOS app's HTTP, Server-Sent Events, WebSocket and
    NWConnection traffic, including compressed and protobuf payloads, and shows
    it in an in-app dashboard that also browses the app's sandbox.
  DESC
  s.homepage = 'https://github.com/0xSiddhant/Cerebro'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = '0xSiddhant'
  s.source = { :git => 'https://github.com/0xSiddhant/Cerebro.git', :tag => "v#{s.version}" }

  s.ios.deployment_target = '16.0'
  s.swift_version = '5.9'
  s.pod_target_xcconfig = { 'SWIFT_STRICT_CONCURRENCY' => 'complete' }

  s.default_subspecs = 'Core', 'UI'

  # Run Script phases call this binary, because CocoaPods has no build-tool plugins.
  s.prepare_command = 'Scripts/build-generator.sh bin'

  s.subspec 'Core' do |core|
    core.source_files = 'Sources/CerebroCore/**/*.swift'
    core.resource_bundles = { 'Cerebro_Privacy' => ['Sources/CerebroCore/PrivacyInfo.xcprivacy'] }
    core.frameworks = 'Foundation', 'Network', 'Security', 'CFNetwork', 'CoreTelephony'
    core.libraries = 'compression'
  end

  s.subspec 'UI' do |ui|
    ui.dependency 'Cerebro/Core'
    ui.source_files = 'Sources/Cerebro/**/*.swift'
    ui.frameworks = 'UIKit', 'QuickLook', 'UniformTypeIdentifiers'
  end

  s.subspec 'Proto' do |proto|
    proto.dependency 'Cerebro/Core'
    proto.dependency 'SwiftProtobuf', '>= 1.27.0', '< 2.0.0'
    proto.source_files = 'Sources/CerebroProto/**/*.swift'
    # CocoaPods keeps only the files of the subspecs an app installs, so on the root spec this was deleted.
    proto.preserve_paths = 'bin/cerebro-proto-gen'
  end
end
