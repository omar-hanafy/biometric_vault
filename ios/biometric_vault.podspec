#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint biometric_vault.podspec' to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'biometric_vault'
  s.version          = '1.0.0'
  s.summary          = 'Secure storage with optional biometric protection for Flutter.'
  s.description      = <<-DESC
Secure storage with optional biometric protection for Flutter apps.
                       DESC
  s.homepage         = 'https://github.com/omar-hanafy/biometric_vault'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'omar-hanafy' => 'omar_hanafy@icloud.com' }
  s.source           = { :path => '.' }
  s.source_files = 'biometric_vault/Sources/biometric_vault/**/*.swift'
  s.resource_bundles = { 'biometric_vault_privacy' => ['biometric_vault/Sources/biometric_vault/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.frameworks = 'LocalAuthentication', 'Security'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
