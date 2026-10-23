import Foundation
import GRDB

/// Unread primaries per category, live, plus which categories are switched on (have an enabled
/// feed). `total` is the sum over enabled categories; secondaries never count.
@MainActor
@Observable
final class UnreadCountsModel {
    let appDB: AppDatabase
    private(set) var byCategory: [String: Int] = [:]
    private(set) var enabledCategories: Set<String> = Set(NewsCategory.all.filter(\.defaultEnabled).map(\.id))
    private var enabledTask: Task<Void, Never>?

    var total: Int { byCategory.values.reduce(0, +) }

    /// Registry order, only the categories that are on.
    var visibleCategories: [NewsCategory] { NewsCategory.visible(enabledIDs: enabledCategories) }

    init(appDB: AppDatabase) {
        self.appDB = appDB
    }

    func count(for category: String) -> Int { byCategory[category] ?? 0 }

    func observe() async {
        enabledTask?.cancel()
        enabledTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await ids in AppDatabase.enabledCategoriesObservation().values(in: self.appDB.dbPool) {
                    self.enabledCategories = ids
                }
            } catch {}
        }
        do {
            for try await counts in AppDatabase.unreadCountsByCategoryObservation().values(in: appDB.dbPool) {
                byCategory = counts
            }
        } catch {
            // cancelled
        }
        enabledTask?.cancel()
    }
}
