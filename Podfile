platform :osx, '11.0'
use_frameworks!

target 'Thoth' do

  # Application
  pod 'PINCache'
  pod 'Sauce'
  # RealmSwift は 10.x 系内で最新に更新（20.x はメジャー移行で破壊的変更が大きいため回避）
  pod 'RealmSwift', '~> 10.54'
  pod 'RxCocoa'
  pod 'RxSwift'
  pod 'LoginServiceKit', :git => 'https://github.com/Clipy/LoginServiceKit.git'
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
      config.build_settings['MACOSX_DEPLOYMENT_TARGET'] = '11.0'
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
