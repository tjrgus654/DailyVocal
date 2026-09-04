//
//  VocalLabView.swift
//  DailyVocal
//
//  48-tip library: today's featured card, 6-category grid, filtering chips,
//  and search. Detail opens as a sheet.
//

import SwiftUI

public struct VocalLabView: View {
    @State private var viewModel = VocalLabViewModel()
    @State private var selectedTip: VocalTip?

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    public init() {}

    public var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 16) {
                headerView
                searchBarView
                    .padding(.horizontal, 20)
                categoryFilterChips

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 20) {
                        if viewModel.selectedCategory == nil,
                           viewModel.searchText.isEmpty,
                           !viewModel.showFavoritesOnly {
                            if let todayTip = viewModel.todayTip {
                                todayTipCard(todayTip)
                                    .padding(.horizontal, 20)
                            }
                            categoryGridView
                                .padding(.horizontal, 20)
                        }

                        if viewModel.selectedCategory != nil || !viewModel.searchText.isEmpty || viewModel.showFavoritesOnly {
                            tipsListSection
                                .padding(.horizontal, 20)
                        } else if viewModel.selectedCategory == nil && viewModel.searchText.isEmpty && viewModel.allTips.isEmpty {
                            emptyStateView
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.bottom, 24)
                }
            }
        }
        .sheet(item: $selectedTip) { tip in
            TipDetailView(
                tip: tip,
                relatedTips: viewModel.relatedTips(for: tip),
                isFavorite: viewModel.isFavorite(tip),
                onToggleFavorite: {
                    viewModel.toggleFavorite(tip)
                    HapticManager.shared.buttonTap()
                }
            ) { related in
                selectedTip = related
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("발성 비법 · 연구 기반")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.brandSecondary)
                Text("발성 연구소")
                    .font(.screenTitle)
                    .foregroundColor(.white)
            }
            Spacer()

            Text("총 \(viewModel.allTips.count)개 비법")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassCard(cornerRadius: 10, padding: 4)
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
    }

    // MARK: - Search

    private var searchBarView: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.textSecondary)
            TextField("비법 검색 (예: 가성, 호흡, 삑사리)", text: $viewModel.searchText)
                .foregroundColor(.white)
                .autocorrectionDisabled()
            if !viewModel.searchText.isEmpty {
                Button(action: { viewModel.searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 14, padding: 0)
    }

    // MARK: - Category chips

    private var categoryFilterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button(action: {
                    viewModel.selectedCategory = nil
                    viewModel.showFavoritesOnly = false
                    HapticManager.shared.buttonTap()
                }) {
                    Text("전체 보기")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(viewModel.selectedCategory == nil && !viewModel.showFavoritesOnly
                                    ? Color.brandPrimary : Color.surfaceDark)
                        .foregroundColor(viewModel.selectedCategory == nil && !viewModel.showFavoritesOnly ? .white : .textSecondary)
                        .clipShape(Capsule())
                }

                Button(action: {
                    viewModel.showFavoritesOnly.toggle()
                    if viewModel.showFavoritesOnly { viewModel.selectedCategory = nil }
                    HapticManager.shared.buttonTap()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: viewModel.showFavoritesOnly ? "star.fill" : "star")
                            .font(.caption2)
                        Text("즐겨찾기 \(viewModel.favoriteIds.count)")
                    }
                    .font(.caption)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(viewModel.showFavoritesOnly ? Color.vocalWarning : Color.surfaceDark)
                    .foregroundColor(viewModel.showFavoritesOnly ? .white : .textSecondary)
                    .clipShape(Capsule())
                }

                ForEach(VocalCategory.allCases) { category in
                    Button(action: {
                        viewModel.selectedCategory = viewModel.selectedCategory == category ? nil : category
                        HapticManager.shared.buttonTap()
                    }) {
                        HStack(spacing: 4) {
                            Text(category.emoji)
                            Text(category.title)
                        }
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(viewModel.selectedCategory == category ? category.themeColor : Color.surfaceDark)
                        .foregroundColor(viewModel.selectedCategory == category ? .white : .textSecondary)
                        .clipShape(Capsule())
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Empty state

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title)
                .foregroundColor(.vocalWarning)
            Text(viewModel.loadError ?? "팁 데이터가 없습니다.")
                .font(.caption)
                .foregroundColor(.textSecondary)
                .multilineTextAlignment(.center)
            Button("다시 불러오기") {
                viewModel.loadTips()
            }
            .font(.caption.bold())
            .foregroundColor(.brandSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .glassCard(cornerRadius: 16, padding: 16)
    }

    // MARK: - Today's tip

    private func todayTipCard(_ tip: VocalTip) -> some View {
        Button(action: {
            selectedTip = tip
            HapticManager.shared.buttonTap()
        }) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("오늘의 추천 비법", systemImage: "star.fill")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.vocalWarning)
                    Spacer()
                    Text(tip.viewCount > 0 ? "쇼츠 #\(tip.id)" : "연구 기반 팁")
                        .font(.caption2)
                        .foregroundColor(.textSecondary)
                }

                Text(tip.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.leading)

                Text(tip.beginnerAnalogy)
                    .font(.caption)
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .glassCard(cornerRadius: 18, padding: 16)
        }
    }

    // MARK: - Category grid

    private var categoryGridView: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(VocalCategory.allCases) { category in
                Button(action: {
                    viewModel.selectedCategory = category
                    HapticManager.shared.buttonTap()
                }) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(category.emoji)
                                .font(.title)
                            Spacer()
                            Text("\(viewModel.tipCount(for: category))개 팁")
                                .font(.caption2)
                                .foregroundColor(.textSecondary)
                        }
                        Text(category.title)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(category.summaryDescription)
                            .font(.caption2)
                            .foregroundColor(.textSecondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .frame(height: 120)
                    .glassCard(cornerRadius: 16, padding: 14)
                }
            }
        }
    }

    // MARK: - Filtered list

    private var tipsListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(viewModel.filteredTips.count)개의 발성 비법")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.textSecondary)

            ForEach(viewModel.filteredTips) { tip in
                Button(action: {
                    selectedTip = tip
                    HapticManager.shared.buttonTap()
                }) {
                    HStack(spacing: 14) {
                        Text(tip.category.emoji)
                            .font(.title2)
                            .frame(width: 44, height: 44)
                            .background(Color.surfaceDark)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(tip.title)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text(tip.keyActionWord)
                                .font(.caption2)
                                .foregroundColor(.brandSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button(action: {
                            viewModel.toggleFavorite(tip)
                            HapticManager.shared.buttonTap()
                        }) {
                            Image(systemName: viewModel.isFavorite(tip) ? "star.fill" : "star")
                                .font(.caption)
                                .foregroundColor(viewModel.isFavorite(tip) ? .vocalWarning : .textSecondary)
                        }

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.textSecondary)
                    }
                    .glassCard(cornerRadius: 14, padding: 14)
                }
            }
        }
    }
}
