//
//  VocalLabViewModel.swift
//  5VocalMaster
//
//  Loads the 48 tip records from the bundle, provides category filtering and
//  search, deterministic "today's tip" selection, and related-tip lookup.
//

import SwiftUI
import Observation

@MainActor
@Observable
public final class VocalLabViewModel {

    public private(set) var allTips: [VocalTip] = []
    public var selectedCategory: VocalCategory?
    public var searchText = ""
    public private(set) var todayTip: VocalTip?
    public private(set) var isLoading = false
    public private(set) var loadError: String?
    /// Starred tip ids (persisted in UserDefaults as a string array).
    public private(set) var favoriteIds: Set<Int> = []
    public var showFavoritesOnly = false

    private static let favoritesKey = "favoriteTipIds"

    public init() {
        loadFavorites()
        loadTips()
    }

    public func loadFavorites() {
        let raw = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
        favoriteIds = Set(raw.compactMap(Int.init))
    }

    public func isFavorite(_ tip: VocalTip) -> Bool {
        favoriteIds.contains(tip.id)
    }

    public func toggleFavorite(_ tip: VocalTip) {
        if favoriteIds.contains(tip.id) {
            favoriteIds.remove(tip.id)
        } else {
            favoriteIds.insert(tip.id)
        }
        UserDefaults.standard.set(
            favoriteIds.map(String.init).sorted(),
            forKey: Self.favoritesKey
        )
    }

    public func loadTips() {
        // Tab switches recreate this view model's initializer often; only the
        // first (or a previously failed) load does actual work.
        guard allTips.isEmpty || loadError != nil else { return }
        isLoading = true
        defer { isLoading = false }

        guard let url = Bundle.main.url(forResource: "vocal_tips", withExtension: "json") else {
            loadError = "vocal_tips.json을 번들에서 찾을 수 없습니다. (Target Membership 확인 필요)"
            allTips = []
            return
        }
        do {
            let data = try Data(contentsOf: url)
            allTips = try JSONDecoder().decode([VocalTip].self, from: data)
            loadError = nil
            selectTodayTip()
        } catch {
            loadError = "팁 데이터를 해석할 수 없습니다: \(error.localizedDescription)"
            allTips = []
        }
    }

    public var filteredTips: [VocalTip] {
        allTips.filter { tip in
            let matchesFavorites = !showFavoritesOnly || favoriteIds.contains(tip.id)
            let matchesCategory = selectedCategory == nil || tip.category == selectedCategory
            let matchesSearch = searchText.isEmpty
                || tip.title.localizedCaseInsensitiveContains(searchText)
                || tip.shortsSummary.localizedCaseInsensitiveContains(searchText)
                || tip.beginnerAnalogy.localizedCaseInsensitiveContains(searchText)
                || tip.keyActionWord.localizedCaseInsensitiveContains(searchText)
            return matchesFavorites && matchesCategory && matchesSearch
        }
    }

    public func tipCount(for category: VocalCategory) -> Int {
        allTips.filter { $0.category == category }.count
    }

    public func relatedTips(for tip: VocalTip) -> [VocalTip] {
        let related = allTips.filter { tip.relatedShorts.contains($0.id) }
        return tip.relatedShorts.compactMap { id in related.first { $0.id == id } }
    }

    /// Deterministic per-day tip so the featured card doesn't shuffle on re-render.
    private func selectTodayTip() {
        guard !allTips.isEmpty else {
            todayTip = nil
            return
        }
        let dayOfYear = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 1
        todayTip = allTips[(dayOfYear - 1) % allTips.count]
    }
}
