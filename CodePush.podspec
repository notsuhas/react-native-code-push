require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name           = 'CodePush'
  s.version        = package['version'].gsub(/v|-beta/, '')
  s.summary        = package['description']
  s.author         = package['author']
  s.license        = package['license']
  s.homepage       = package['homepage']
  s.source         = { :git => 'https://github.com/CodePushNext/react-native-code-push.git', :tag => "v#{s.version}"}
  s.ios.deployment_target = '15.5'
  s.tvos.deployment_target = '15.5'
  s.preserve_paths = '*.js'
  s.library        = 'z'
  s.source_files = [
    'ios/CodePush/*.{h,m,mm}',
    # Vendored HDiffPatch apply core (cpp/patch_core/) — explicit list,
    # no Android JNI bindings. Diff-side files in cpp/HDiffPatch/HDiff
    # are NOT compiled because they're not enumerated here.
    'cpp/patch_core/archive_patch_core.{h,cpp}',
    'cpp/patch_core/patch_core.{h,cpp}',
    'cpp/patch_core/state_core.{h,cpp}',
    # Vendored sisong/HDiffPatch v4.9.0 — apply-side primitives only.
    'cpp/HDiffPatch/file_for_patch.{c,h}',
    'cpp/HDiffPatch/libHDiffPatch/HPatch/*.{c,h}',
    'cpp/HDiffPatch/libParallel/*.{cpp,h}',
  ]
  s.public_header_files = ['ios/CodePush/CodePush.h']
  s.pod_target_xcconfig = {
    "DEFINES_MODULE" => "YES",
    "CLANG_CXX_LANGUAGE_STANDARD" => "c++14",
    "CLANG_CXX_LIBRARY" => "libc++",
    "GCC_PREPROCESSOR_DEFINITIONS" => "$(inherited) _CRT_SECURE_NO_WARNINGS=1",
    # patch_core.h includes are referenced relatively by pushy/HDiffPatch
    # sources — expose both vendored roots to the Clang search path.
    "HEADER_SEARCH_PATHS" => "$(inherited) \"${PODS_TARGET_SRCROOT}/cpp\" \"${PODS_TARGET_SRCROOT}/cpp/HDiffPatch\" \"${PODS_TARGET_SRCROOT}/cpp/HDiffPatch/libHDiffPatch\""
  }

  # Note: Even though there are copy/pasted versions of some of these dependencies in the repo,
  # we explicitly let CocoaPods pull in the versions below so all dependencies are resolved and
  # linked properly at a parent workspace level.
  s.dependency 'React-Core'
  s.dependency 'SSZipArchive', '~> 2.5.5'
  s.dependency 'JWT', '~> 3.0.0-beta.12'
  s.dependency 'Base64', '~> 1.1'
end
