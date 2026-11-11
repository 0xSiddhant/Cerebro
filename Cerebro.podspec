# Consumed from Git only. CocoaPods trunk goes read-only on December 2, 2026, so
# this podspec is never pushed there.
Pod::Spec.new do |s|
  s.name = 'Cerebro'
  s.version = '0.1.0'
  s.summary = 'A debug-only network inspector for iOS apps.'
  s.description = <<~DESC
    Cerebro captures an iOS app's HTTP, WebSocket and NWConnection traffic and
    shows it in an in-app dashboard, including compressed and protobuf payloads.
  DESC
  s.homepage = 'https://github.com/0xSiddhant/Cerebro'
  s.license = { :type => 'MIT', :file => 'LICENSE' }
  s.author = 'Siddhant Kumar'
  s.source = { :git => 'https://github.com/0xSiddhant/Cerebro.git', :tag => "v#{s.version}" }

  s.ios.deployment_target = '16.0'
  s.swift_version = '5.9'
  s.pod_target_xcconfig = { 'SWIFT_STRICT_CONCURRENCY' => 'complete' }

  s.default_subspecs = 'Core', 'UI'

  # Run Script phases call this binary, because CocoaPods has no build-tool plugins.
  s.prepare_command = 'Scripts/build-generator.sh bin'
  s.preserve_paths = 'bin/cerebro-proto-gen'

  s.subspec 'Core' do |core|
    core.source_files = 'Sources/CerebroCore/**/*.swift'
    core.frameworks = 'Foundation', 'Network', 'Security', 'CFNetwork', 'CoreTelephony'
    core.libraries = 'compression'
  end

  s.subspec 'UI' do |ui|
    ui.dependency 'Cerebro/Core'
    ui.source_files = 'Sources/Cerebro/**/*.swift'
    ui.frameworks = 'UIKit', 'UserNotifications'
  end

  s.subspec 'Proto' do |proto|
    proto.dependency 'Cerebro/Core'
    proto.dependency 'SwiftProtobuf', '>= 1.27.0', '< 2.0.0'
    proto.source_files = 'Sources/CerebroProto/**/*.swift'
  end
end
