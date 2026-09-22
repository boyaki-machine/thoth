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

/// クリップボード履歴の定期クリーンアップを行うサービス。
/// 最大履歴数（maxHistorySize）を超えた古いクリップの削除と、
/// どの履歴からも参照されなくなった孤児 .data ファイルの削除を 30 分間隔で実行する。
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
    /// 上限超過クリップの削除と孤児ファイルの掃除を即時実行する
    func cleanDatas() {
        let historyStore = AppEnvironment.current.historyStore
        let maxHistorySize = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)
        let clips = historyStore.clips(ascending: false)
        if let cutoff = Self.overflowCutoff(updateTimesNewestFirst: clips.map(\.updateTime), maxHistorySize: maxHistorySize) {
            // サムネイルは履歴と一緒に消える
            historyStore.deleteClips(olderThan: cutoff)
        }
        cleanFiles(referencedPaths: historyStore.clips(ascending: false).map(\.dataPath))
    }

    /// 最大履歴数を超えたときに削除する境界の時刻を返す（これより古い履歴を消す）。
    ///
    /// 上限件目の履歴と同じ時刻のものは残すため、同じ秒に複数コピーした場合は
    /// 上限をわずかに超えて残ることがある（従来と同じ挙動）。
    /// - Parameter updateTimesNewestFirst: 全履歴の updateTime（新しい順）
    /// - Returns: 削除不要なら nil
    static func overflowCutoff(updateTimesNewestFirst: [Int], maxHistorySize: Int) -> Int? {
        guard maxHistorySize > 0, updateTimesNewestFirst.count > maxHistorySize else { return nil }
        return updateTimesNewestFirst[maxHistorySize - 1]
    }

    /// どの履歴からも参照されていない .data ファイルを削除する
    private func cleanFiles(referencedPaths: [String]) {
        let fileManager = FileManager.default
        guard let paths = try? fileManager.contentsOfDirectory(atPath: CPYUtilities.applicationSupportFolder()) else { return }

        let allClipPaths = Set(referencedPaths.compactMap { $0.components(separatedBy: "/").last })

        // Delete diff datas on background thread
        DispatchQueue.global(qos: .utility).async {
            allClipPaths.symmetricDifference(paths)
                .map { CPYUtilities.applicationSupportFolder() + "/" + "\($0)" }
                .forEach { CPYUtilities.deleteData(at: $0) }
        }
    }
}
