//
//  DataCleanService.swift
//
//  Clipy
//  GitHub: https://github.com/clipy
//  HP: https://clipy-app.com
//
//  Created by Econa77 on 2016/11/20.
//
//  Copyright © 2015-2018 Clipy Project.
//

import Foundation
import RxSwift
import RealmSwift
import PINCache

/// クリップボード履歴の定期クリーンアップを行うサービス。
/// 最大履歴数（maxHistorySize）を超えた古いクリップの削除と、
/// Realm に参照が無くなった孤児 .data ファイルの削除を 30 分間隔で実行する。
/// すべて .utility QoS のバックグラウンドで動作し、メインスレッドには影響しない。
final class DataCleanService {

    // MARK: - Properties
    fileprivate var disposeBag = DisposeBag()
    fileprivate let scheduler = SerialDispatchQueueScheduler(qos: .utility)

    // MARK: - Monitoring
    /// 30 分間隔の定期クリーンアップを開始する
    func startMonitoring() {
        disposeBag = DisposeBag()
        // Clean datas every 30 minutes
        Observable<Int>.interval(.seconds(60 * 30), scheduler: scheduler)
            .subscribe(onNext: { [weak self] _ in
                self?.cleanDatas()
            })
            .disposed(by: disposeBag)
    }

    // MARK: - Delete Data
    /// 上限超過クリップの削除（サムネイルキャッシュ含む）と孤児ファイルの掃除を即時実行する
    func cleanDatas() {
        let realm = RealmProvider.defaultRealm()
        let flowHistories = overflowingClips(with: realm)
        flowHistories
            .compactMap { !$0.isInvalidated && !$0.thumbnailPath.isEmpty ? $0.thumbnailPath : nil }
            .forEach { PINCache.shared.removeObject(forKey: $0) }
        realm.transaction { realm.delete(flowHistories) }
        cleanFiles(with: realm)
    }

    /// 最大履歴数を超えた（= 削除対象の）古いクリップを返す
    private func overflowingClips(with realm: Realm) -> Results<CPYClip> {
        let clips = realm.objects(CPYClip.self).sorted(byKeyPath: #keyPath(CPYClip.updateTime), ascending: false)
        let maxHistorySize = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)

        if clips.count <= maxHistorySize { return realm.objects(CPYClip.self).filter("FALSEPREDICATE") }
        // Delete first clip
        let lastClip = clips[maxHistorySize - 1]
        if lastClip.isInvalidated { return realm.objects(CPYClip.self).filter("FALSEPREDICATE") }

        // Deletion target
        let updateTime = lastClip.updateTime
        let targetClips = realm.objects(CPYClip.self).filter("updateTime < %d", updateTime)

        return targetClips
    }

    /// Realm 上のどのクリップからも参照されていない .data ファイルを削除する
    private func cleanFiles(with realm: Realm) {
        let fileManager = FileManager.default
        guard let paths = try? fileManager.contentsOfDirectory(atPath: CPYUtilities.applicationSupportFolder()) else { return }

        let allClipPaths = Set(realm.objects(CPYClip.self)
            .filter { !$0.isInvalidated }
            .compactMap { $0.dataPath.components(separatedBy: "/").last })

        // Delete diff datas on background thread
        DispatchQueue.global(qos: .utility).async {
            allClipPaths.symmetricDifference(paths)
                .map { CPYUtilities.applicationSupportFolder() + "/" + "\($0)" }
                .forEach { CPYUtilities.deleteData(at: $0) }
        }
    }
}
