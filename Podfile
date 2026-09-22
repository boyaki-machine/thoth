platform :osx, '15.0'
use_frameworks!

target 'Thoth' do

  # Application
  pod 'Sauce'
  # SwiftData への移行が済むまで 10.x に据え置く（移行時に旧データベースを読み出すために使う）
  pod 'RealmSwift', '~> 10.54'
  pod 'RxCocoa'
  pod 'RxSwift'
  pod 'KeyHolder'
  pod 'Magnet'
  pod 'RxScreeen'
  pod 'AEXML'
  pod 'LetsMove'
  pod 'SwiftHEXColors'
  # Utility
  pod 'BartyCrouch'
  pod 'SwiftLint'
  pod 'SwiftGen'

  target 'ThothTests' do
    inherit! :search_paths

    pod 'Quick', '~> 7.0'
    pod 'Nimble', '~> 14.0'

  end

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '15.0'
      # Apple Silicon 専用。Pods プロジェクトの既定（arm64 x86_64）のままにしない
      config.build_settings['ARCHS'] = 'arm64'
    end
  end

  # CocoaPods が生成するサードパーティライセンス一覧を、
  # アプリ同梱用（Thoth/Resources）とリポジトリ公開用（NOTICE）にコピーする。
  # Podfile / Podfile.lock を変更したら `bundle exec pod install` を再実行することで
  # 常に最新のライセンス一覧に同期される。
  require 'fileutils'
  generated = 'Pods/Target Support Files/Pods-Thoth/Pods-Thoth-acknowledgements.markdown'
  FileUtils.cp(generated, 'Thoth/Resources/Acknowledgements.md')
  FileUtils.cp(generated, 'NOTICE')
end
