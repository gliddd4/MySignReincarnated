//
//  SourcesView.swift
//  RyukSign
//
//  Created by samara on 10.04.2025.
//
import CoreData
import AltSourceKit
import SwiftUI
import NimbleViews

// MARK: - View
struct SourcesView: View {
	@Environment(\.scenePhase) private var scenePhase
	#if !NIGHTLY && !DEBUG
	@AppStorage("Feather.shouldStar") private var _shouldStar: Int = 0
	#endif
	@StateObject var viewModel = SourcesViewModel.shared
	@State private var _isAddingPresenting = false
	@State private var _addingSourceLoading = false
	@State private var _searchText = ""
	@State private var _shouldNavigateToAllRepos = false
	@State private var _activeIndividualSource: AltSource? = nil
	@State private var _isEditMode = false
	@State private var _selectedSources: Set<AltSource> = []
	@State private var _showDeleteConfirmation = false

	@AppStorage("Feather.sourcesTabShowAllReposDirectly")
	private var _sourcesTabShowAllReposDirectly: Bool = false

	/// Sources not excluded from "All Repositories"
	private var _nonExcludedSources: [AltSource] {
		_sources.filter { source in
			let id = source.identifier ?? source.sourceURL?.absoluteString ?? ""
			return !RyukSignAPI.isSourceExcluded(id)
		}
	}

	@ObservedObject var appNavigationManager = AppNavigationManager.shared
	@ObservedObject private var _premiumFilter = PremiumFilterPreferences.shared

	private var _filteredSources: [AltSource] {
		_sources.filter { _searchText.isEmpty || ($0.name?.localizedCaseInsensitiveContains(_searchText) ?? false) }
	}

	// MARK: Sorting & favourites

	@ObservedObject private var _favorites = SourceFavorites.shared
	@ObservedObject private var _sourceCache = SourceCache.shared

	@AppStorage("RyukSign.sourceSort") private var _sortRawValue: String = SourceSortOption.nameAZ.rawValue

	/// Browse settings (Settings → Browse).
	@AppStorage(BrowsePreferences.hidesRepositorySectionCounts) private var _hidesSectionCounts = false

	/// Announcements from every source, so a notice from a repository you have not
	/// opened is not invisible.
	@ObservedObject private var _news = NewsFeed.shared
	@State private var _isNewsPresenting = false

	/// The glass tab bar draws the view toolbar, so this screen publishes its items
	/// to the glass grid instead of contributing them to the navigation bar.
	@ObservedObject private var _tabToolbar = TabToolbarRegistry.shared
	@AppStorage("Feather.tabBarStyle") private var _tabBarStyle: TabBarStyle = .system

	private var _sortOption: SourceSortOption {
		SourceSortOption(rawValue: _sortRawValue) ?? .nameAZ
	}

	/// Favourites get their own section so a long list stays navigable.
	private var _favoriteSources: [AltSource] {
		_sortedSources(_filteredSources.filter { _favorites.isFavorite(SourceFavorites.key(for: $0)) })
	}

	private var _otherSources: [AltSource] {
		_sortedSources(_filteredSources.filter { !_favorites.isFavorite(SourceFavorites.key(for: $0)) })
	}

	private func _sortedSources(_ sources: [AltSource]) -> [AltSource] {
		sources.sorted { lhs, rhs in
			switch _sortOption {
			case .nameAZ:
				return (lhs.name ?? "").localizedCaseInsensitiveCompare(rhs.name ?? "") == .orderedAscending
			case .nameZA:
				return (lhs.name ?? "").localizedCaseInsensitiveCompare(rhs.name ?? "") == .orderedDescending
			case .mostApps:
				return _appCount(lhs) > _appCount(rhs)
			case .fewestApps:
				return _appCount(lhs) < _appCount(rhs)
			case .recentlyUpdated:
				return _lastUpdated(lhs) > _lastUpdated(rhs)
			}
		}
	}

	private func _appCount(_ source: AltSource) -> Int {
		guard let url = source.sourceURL else { return 0 }
		return _sourceCache.appCount(for: url) ?? 0
	}

	private func _lastUpdated(_ source: AltSource) -> Date {
		guard let url = source.sourceURL else { return .distantPast }
		return _sourceCache.lastUpdated(for: url) ?? .distantPast
	}

	@FetchRequest(
		entity: AltSource.entity(),
		sortDescriptors: [NSSortDescriptor(keyPath: \AltSource.name, ascending: true)],
		animation: .snappy
	) private var _sources: FetchedResults<AltSource>

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Sources")) {
			mainContent
		}
		.tabToolbar(_gridToolbarConfig)
		.task(id: Array(_sources)) {
			await viewModel.fetchSources(_sources)
			// The feed is built from repositories now in memory, so it has to be
			// rebuilt after they land, not before.
			_news.rebuild()
		}
		.sheet(isPresented: $_isNewsPresenting) {
			NewsFeedView()
		}
		.onChange(of: appNavigationManager.pendingAppNavigation) { pendingNavigation in
			handlePendingNavigation(pendingNavigation)
		}
		.onChange(of: _isEditMode) { isEditing in
			if !isEditing {
				_selectedSources.removeAll()
			}
		}
		.onChange(of: _premiumFilter.stamp) { _ in
			Task {
				await viewModel.fetchSources(_sources, refresh: true)
			}
		}
		.onChange(of: scenePhase) { newPhase in
			if newPhase == .active {
				Task {
					await viewModel.fetchSources(_sources)
				}
			}
		}
	}

	@ViewBuilder
	private var mainContent: some View {
		if _sourcesTabShowAllReposDirectly && !_filteredSources.isEmpty {
			allRepositoriesDirectView
		} else {
			sourcesListView
		}
	}

	@ViewBuilder
	private var allRepositoriesDirectView: some View {
		SourceAppsView(
			object: _nonExcludedSources,
			viewModel: viewModel,
			onRefresh: {
				await self.viewModel.fetchSources(self._sources, refresh: true)
			}
		)
		.toolbar {
			NBToolbarButton(
				systemImage: "plus",
				style: .icon,
				placement: .topBarTrailing,
				isDisabled: _addingSourceLoading
			) {
				_isAddingPresenting = true
			}
		}
		.sheet(isPresented: $_isAddingPresenting) {
			SourcesAddView()
				.adaptiveSheetSizing()
		}
	}

	@ViewBuilder
	private var sourcesListView: some View {
		NBListAdaptable {
			if !_filteredSources.isEmpty {
				allRepositoriesSection
				favoritesSection
				repositoriesSection
			}
		}
		.adaptiveSearchable(text: $_searchText, style: _tabBarStyle)
		.overlay {
			emptyStateView
		}
		.toolbar {
			// The glass grid owns the toolbar items in that style.
			if _tabBarStyle != .glassSwitcher {
				toolbarContent
			}
		}
		.refreshable {
			await viewModel.fetchSources(_sources, refresh: true)
		}
		.sheet(isPresented: $_isAddingPresenting) {
			SourcesAddView()
				.adaptiveSheetSizing()
		}
		.alert(
			deleteDialogTitle,
			isPresented: $_showDeleteConfirmation
		) {
			Button("Delete", role: .destructive) {
				deleteSelectedSources()
			}
			Button("Cancel", role: .cancel) {}
		} message: {
			Text("This action cannot be undone.")
		}
	}

	private var deleteDialogTitle: String {
		let count = _selectedSources.count
		return "Delete \(count) \(count == 1 ? "repository" : "repositories")?"
	}

	@ViewBuilder
	private var allRepositoriesSection: some View {
		Section {
			NavigationLink(isActive: $_shouldNavigateToAllRepos) {
				SourceAppsView(
					object: _nonExcludedSources,
					viewModel: viewModel,
					onRefresh: {
						await self.viewModel.fetchSources(self._sources, refresh: true)
					}
				)
			} label: {
				allRepositoriesLabel
			}
			.buttonStyle(.plain)
			.onChange(of: _shouldNavigateToAllRepos) { isActive in
				if isActive {
					_activeIndividualSource = nil
				}
			}
		}
		.disabled(_isEditMode)
	}

	@ViewBuilder
	private var allRepositoriesLabel: some View {
		// Same shape as a repository row, so the list reads as one continuous
		// column instead of a card sitting on top of it. The subtitle only
		// restated the title, and it cost the row its second line.
		HStack(spacing: 10) {
			Image("Repositories")
				.appIconStyle(size: 30)
			Text(.localized("All Repositories"))
				.font(.subheadline.weight(.semibold))
			Spacer(minLength: 0)
		}
	}

	@ViewBuilder
	private var favoritesSection: some View {
		if !_favoriteSources.isEmpty {
			NBSection(
				.localized("Favourites"),
				secondary: _hidesSectionCounts ? nil : "\(_favoriteSources.count)"
			) {
				ForEach(_favoriteSources) { source in
					if _isEditMode {
						editModeRow(for: source)
					} else {
						normalModeRow(for: source)
					}
				}
			}
		}
	}

	@ViewBuilder
	private var repositoriesSection: some View {
		// Selection feedback is never hidden — knowing how many you are about to
		// delete is not the same as knowing how many you have.
		let sectionTitle = _isEditMode ? "\(_selectedSources.count) selected" : "\(_otherSources.count)"
		NBSection(
			.localized("Repositories"),
			secondary: (_hidesSectionCounts && !_isEditMode) ? nil : sectionTitle
		) {
			ForEach(_otherSources) { source in
				if _isEditMode {
					editModeRow(for: source)
				} else {
					normalModeRow(for: source)
				}
			}
		}
	}

	/// Always present, so the feed stays reachable once everything has been read;
	/// the badge only says how much is new.
	@ViewBuilder
	private var _newsButton: some View {
		Button {
			_isNewsPresenting = true
		} label: {
			Image(systemName: "newspaper")
				.overlay(alignment: .topTrailing) {
					if _news.unseenCount > 0 {
						Text(verbatim: _news.unseenCount > 9 ? "9+" : "\(_news.unseenCount)")
							.font(.system(size: 9, weight: .bold))
							.foregroundStyle(.white)
							.padding(.horizontal, 3)
							.padding(.vertical, 1)
							.background(Capsule().fill(.red))
							.offset(x: 6, y: -6)
					}
				}
		}
	}

	@ViewBuilder
	private var sortMenu: some View {
		Menu {
			Picker(.localized("Sort"), selection: $_sortRawValue) {
				ForEach(SourceSortOption.allCases) { option in
					Label(option.label, systemImage: option.systemImage)
						.tag(option.rawValue)
				}
			}
		} label: {
			Image(systemName: "arrow.up.arrow.down")
		}
	}

	@ViewBuilder
	private func editModeRow(for source: AltSource) -> some View {
		HStack(spacing: 12) {
			selectionButton(for: source)
			SourcesCellView(source: source, isEditMode: true)
		}
		.contentShape(Rectangle())
		.onTapGesture {
			toggleSelection(for: source)
		}
	}

	@ViewBuilder
	private func selectionButton(for source: AltSource) -> some View {
		let isPremium = source.sourceURL.map { RyukSignAPI.isPremiumSource($0) } ?? false
		Button {
			toggleSelection(for: source)
		} label: {
			let isSelected = _selectedSources.contains(source)
			if isPremium {
				Image(systemName: "lock.fill")
					.font(.title3)
					.foregroundColor(.secondary.opacity(0.5))
			} else {
				Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
					.font(.title3)
					.foregroundColor(isSelected ? .accentColor : .secondary)
			}
		}
		.buttonStyle(.plain)
		.disabled(isPremium)
	}

	@ViewBuilder
	private func normalModeRow(for source: AltSource) -> some View {
		let isActive = Binding(
			get: { _activeIndividualSource == source },
			set: { isActive in
				if isActive {
					_activeIndividualSource = source
					_shouldNavigateToAllRepos = false
				} else if _activeIndividualSource == source {
					_activeIndividualSource = nil
				}
			}
		)

		NavigationLink(isActive: isActive) {
			SourceAppsView(
				object: [source],
				viewModel: viewModel,
				onRefresh: {
					await self.viewModel.fetchSources(self._sources, refresh: true)
				}
			)
		} label: {
			SourcesCellView(source: source, isEditMode: false)
		}
		.buttonStyle(.plain)
	}

	@ViewBuilder
	private var emptyStateView: some View {
		if _filteredSources.isEmpty {
			NBContentUnavailable(
				.localized("No Repositories"),
				systemImage: "globe.desk.fill",
				description: .localized("Get started by adding your first repository.")
			) {
				Button {
					_isAddingPresenting = true
				} label: {
					NBButton(.localized("Add Source"), style: .text)
				}
			}
		}
	}

	// MARK: Glass grid config

	/// What the glass grid shows for this screen. The split between the two boxes is
	/// simply whether an item carries a word: Edit/Done/Select All are text, the
	/// icon buttons are not.
	private var _gridToolbarConfig: TabToolbarConfig {
		var config = TabToolbarConfig()
		config.hasSearch = true
		config.searchPrompt = .localized("Search repositories")

		if _isEditMode {
			config.textActions = [
				TabToolbarAction(id: "done", systemImage: "checkmark", title: .localized("Done")) {
					withAnimation {
						_isEditMode = false
						_selectedSources.removeAll()
					}
				},
				TabToolbarAction(id: "selectAll", systemImage: "checkmark.circle", title: .localized("Select All")) {
					selectAllSources()
				},
			]
			config.iconActions = [
				TabToolbarAction(
					id: "delete",
					systemImage: "trash",
					isDisabled: _selectedSources.isEmpty
				) {
					if !_selectedSources.isEmpty {
						_showDeleteConfirmation = true
					}
				},
			]
		} else {
			config.textActions = _filteredSources.isEmpty ? [] : [
				TabToolbarAction(id: "edit", systemImage: "square.and.pencil", title: .localized("Edit")) {
					withAnimation { _isEditMode = true }
				},
			]
			config.iconActions = [
				TabToolbarAction(id: "news", systemImage: "newspaper", badge: _news.unseenCount) {
					_isNewsPresenting = true
				},
				TabToolbarAction(
					id: "sort",
					systemImage: "arrow.up.arrow.down",
					menu: SourceSortOption.allCases.map { option in
						TabToolbarMenuEntry(
							id: option.rawValue,
							title: option.label,
							systemImage: option.systemImage,
							isSelected: option.rawValue == _sortRawValue
						) {
							_sortRawValue = option.rawValue
						}
					}
				),
				TabToolbarAction(
					id: "add",
					systemImage: "plus",
					isDisabled: _addingSourceLoading
				) {
					_isAddingPresenting = true
				},
			]
		}

		return config
	}

	@ToolbarContentBuilder
	private var toolbarContent: some ToolbarContent {
		ToolbarItem(placement: .topBarLeading) {
			if _isEditMode {
				HStack(spacing: 12) {
					Button("Done") {
						withAnimation {
							_isEditMode = false
							_selectedSources.removeAll()
						}
					}
					Button(action: selectAllSources) {
						Text("Select All")
					}
				}
			} else {
				if !_filteredSources.isEmpty {
					Button("Edit") {
						withAnimation {
							_isEditMode = true
						}
					}
				}
			}
		}

		ToolbarItem(placement: .topBarTrailing) {
			if _isEditMode {
				Button(role: .destructive) {
					if !_selectedSources.isEmpty {
						_showDeleteConfirmation = true
					}
				} label: {
					Image(systemName: "trash")
				}
				.disabled(_selectedSources.isEmpty)
			} else {
				HStack(spacing: 12) {
					_newsButton
					sortMenu
					Button {
						_isAddingPresenting = true
					} label: {
						Image(systemName: "plus")
					}
					.disabled(_addingSourceLoading)
				}
			}
		}
	}

	// MARK: - Selection Methods
	private var _deletableSources: [AltSource] {
		_filteredSources.filter { source in
			guard let url = source.sourceURL else { return true }
			return !RyukSignAPI.isPremiumSource(url)
		}
	}

	private func toggleSelection(for source: AltSource) {
		// Don't allow selecting premium sources
		if let url = source.sourceURL, RyukSignAPI.isPremiumSource(url) { return }
		if _selectedSources.contains(source) {
			_selectedSources.remove(source)
		} else {
			_selectedSources.insert(source)
		}
	}

	private var areAllSourcesSelected: Bool {
		let all = Set(_deletableSources)
		return !all.isEmpty && _selectedSources == all
	}

	private func selectAllSources() {
		if areAllSourcesSelected {
			_selectedSources.removeAll()
		} else {
			_selectedSources = Set(_deletableSources)
		}
	}

	private func deleteSelectedSources() {
		withAnimation {
			for source in _selectedSources {
				// Skip premium sources — they can only be removed via Reset Premium
				if let url = source.sourceURL, RyukSignAPI.isPremiumSource(url) {
					continue
				}
				Storage.shared.deleteSource(for: source)
			}
			_selectedSources.removeAll()
			_isEditMode = false
		}
	}

	// MARK: - Navigation Handler
	private func handlePendingNavigation(_ pendingNavigation: AppNavigationManager.PendingAppNavigation?) {
		guard let navigation = pendingNavigation else { return }

		if let activeSource = _activeIndividualSource {
			if let repository = viewModel.sources[activeSource],
			   appExistsInRepository(appId: navigation.appId, repository: repository) {
				// Already in the right source — let it handle scrolling.
				return
			} else {
				_activeIndividualSource = nil

				// Let the source close before opening All Repositories.
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
					self._shouldNavigateToAllRepos = true
				}
				return
			}
		}

		if !_shouldNavigateToAllRepos {
			_shouldNavigateToAllRepos = true
		}
	}

	private func appExistsInRepository(appId: String, repository: ASRepository) -> Bool {
		for app in repository.apps {
			if app.currentUniqueId == appId {
				return true
			}
		}
		return false
	}
}

// MARK: - Sorting

/// Repository ordering. "Most apps" reads from the app-count cache, which is
/// written on every refresh and reloaded on launch, so it is populated before
/// the network answers.
enum SourceSortOption: String, CaseIterable, Identifiable {
	case nameAZ
	case nameZA
	case mostApps
	case fewestApps
	case recentlyUpdated

	var id: String { rawValue }

	var label: String {
		switch self {
		case .nameAZ:          return .localized("Name (A–Z)")
		case .nameZA:          return .localized("Name (Z–A)")
		case .mostApps:        return .localized("Most Apps")
		case .fewestApps:      return .localized("Fewest Apps")
		case .recentlyUpdated: return .localized("Recently Updated")
		}
	}

	var systemImage: String {
		switch self {
		case .nameAZ, .nameZA: return "textformat"
		case .mostApps:        return "arrow.down.circle"
		case .fewestApps:      return "arrow.up.circle"
		case .recentlyUpdated: return "clock"
		}
	}
}
