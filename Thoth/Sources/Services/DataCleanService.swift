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
    /// 上限超過クリップの削除と孤児ファイルの掃除を、保存待ちを終えてから行う。
    ///
    /// **保存と同じ直列キューで走らせる。** 保存は「.data を書く → 履歴に載せる」の順なので、
    /// その間に掃除が走ると、書いたばかりの .data を孤児と判断して消してしまう
    func cleanDatas() {
        AppEnvironment.current.clipService.performAfterPendingSaves { [weak self] in
            self?.cleanDatasNow()
        }
    }

    /// 掃除の本体。保存キューの外から直接呼ばないこと（テストは除く）
    func cleanDatasNow(directory: String = CPYUtilities.applicationSupportFolder()) {
        let historyStore = AppEnvironment.current.historyStore
        let maxHistorySize = AppEnvironment.current.defaults.integer(forKey: Constants.UserDefaults.maxHistorySize)
        let clips = historyStore.clips(ascending: false)
        if let cutoff = Self.overflowCutoff(updateTimesNewestFirst: clips.map(\.updateTime), maxHistorySize: maxHistorySize) {
            // サムネイルは履歴と一緒に消える
            historyStore.deleteClips(olderThan: cutoff)
        }
        // 保存層が使えない起動中（鍵が読めない等）の履歴はメモリ上だけなので、ディスクの .data は
        // どれも「参照されていない」ように見える。ここで消すと、原因が解消しても履歴を貼り付けられなくなる
        guard AppEnvironment.current.isLibraryUsable,
              let fileNames = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
        let referencedPaths = historyStore.clips(ascending: false).map(\.dataPath)
        Self.orphanDataFileNames(fileNames: fileNames, referencedPaths: referencedPaths)
            .forEach { CPYUtilities.deleteData(at: (directory as NSString).appendingPathComponent($0)) }
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

    /// どの履歴からも参照されていない .data ファイルの名前を返す（純粋関数）。
    /// フォルダには .data 以外のファイルも置かれうるので、それらは対象にしない
    static func orphanDataFileNames(fileNames: [String], referencedPaths: [String]) -> [String] {
        let referenced = Set(referencedPaths.map { ($0 as NSString).lastPathComponent })
        return fileNames.filter { $0.hasSuffix(".data") && !referenced.contains($0) }
    }
}
