//
//  GlassTabSwitcherView.swift
//  RyukSign
//
//  MySign's edge tab switcher, rebuilt on Apple's real Liquid Glass, and then
//  grown into a four-box reachable grid.
//
//  MySign pinned a collapsible vertical rail to the screen edge and hand-rolled
//  its "glass" out of VariableBlur plus an ultra-thin material at 30% opacity, two
//  years before iOS 26 shipped the real material. `glassEffect(_:in:)` replaces
//  that, with MySign's own recipe kept as the pre-26 fallback.
//
//  The grid is arranged around the rail, and everything hangs off it:
//
//      [ search ]  [ toolbar items that carry a word ]   <- above the rail
//      [ icon-only toolbar items ]  [ the tab rail ]     <- the rail's own row
//
//  The search circle is therefore diagonal to the rail rather than on its left or
//  above it, and an item lands in the icon box or the text box depending on
//  whether it carries a word.
//
//  Geometry notes, because the spacing is deliberately tied together:
//  the rail insets and the gap between rows are chosen so the space *around* an
//  icon is the same in every direction. The glyph sits in a slightly larger box,
//  so `_slack` is added to the label's outer edge and doubled into `_itemGap`.
//

import SwiftUI

// MARK: - Style

enum TabBarStyle: String, CaseIterable, Identifiable {
	case system
	case glassSwitcher

	var id: String { rawValue }

	var title: String {
		switch self {
		case .system:        return .localized("System")
		case .glassSwitcher: return .localized("Glass Switcher")
		}
	}

	var icon: String {
		switch self {
		case .system:        return "rectangle.bottomthird.inset.filled"
		case .glassSwitcher: return "rectangle.righthalf.inset.filled"
		}
	}
}

// MARK: - View

struct GlassTabSwitcherView: View {
	@ObservedObject private var _selection = TabSelectionObserver.shared
	@ObservedObject private var _prefs = TabBarPreferences.shared
	@ObservedObject private var _updates = AppUpdateChecker.shared
	@ObservedObject private var _tweaks = TweakManager.shared
	@ObservedObject private var _toolbar = TabToolbarRegistry.shared
	@AppStorage("Feather.showSourcesUpdateBadge") private var _showSourcesUpdateBadge: Bool = true
	@AppStorage("Feather.glassSwitcherExpanded") private var _isExpanded: Bool = false
	@AppStorage("Feather.glassSwitcherHidden") private var _isHidden: Bool = false

	@State private var _dragOffset: CGFloat = 0
	@State private var _isDragging = false
	@FocusState private var _searchFocused: Bool

	// MARK: Geometry
	//
	// The rail lives against the trailing edge, so the label sits to the left of its
	// icon: the icon stays put as the rail grows leftwards, exactly as MySign's icons
	// stayed put while its rail grew rightwards.

	/// Point size of the glyph itself.
	private let _glyph: CGFloat = 18
	/// The box the glyph is centred in. Slightly larger than the glyph, which is what
	/// creates `_slack` and lets the spacer maths below come out even.
	private let _iconBox: CGFloat = 26
	/// Reserve around every icon, in every direction.
	private let _padding: CGFloat = 10
	/// Icon to label.
	private let _labelSpacing: CGFloat = 10
	/// Between rows. Paired with `_slack` this makes the vertical gap between two
	/// icons equal the horizontal gap from the rail's edge to an icon.
	private let _itemGap: CGFloat = 6
	/// Between the four boxes of the grid.
	private let _boxGap: CGFloat = 8
	/// Diameter of the circular search button.
	private let _circle: CGFloat = 46
	private let _fieldWidth: CGFloat = 214
	private let _corner: CGFloat = 22
	/// Centre the grid a quarter of the way up from the middle, so it sits within
	/// reach of a thumb rather than dead centre.
	private let _verticalShift: CGFloat = 0.25

	/// Half the difference between the glyph and its box — the extra space that has to
	/// be mirrored on the label's outer edge for the row to look evenly padded.
	private var _slack: CGFloat {
		(_iconBox - _glyph) / 2
	}

	private var _tabs: [TabEnum] {
		_prefs.visibleTabs
	}

	private var _selected: TabEnum {
		_tabs.contains(_selection.selectedTab) ? _selection.selectedTab : (_tabs.first ?? .library)
	}

	private var _iconActions: [TabToolbarAction] {
		_toolbar.config.iconActions.filter { !$0.hasText }
	}

	private var _textActions: [TabToolbarAction] {
		_toolbar.config.textActions + _toolbar.config.iconActions.filter { $0.hasText }
	}

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .trailing) {
				TabEnum.view(for: _selected)
					.environmentObject(_selection)
					.frame(width: geometry.size.width, height: geometry.size.height)

				_grid
					.offset(y: -geometry.size.height * _verticalShift)
			}
		}
		// The screen that owns the new tab publishes on appear; clearing first stops
		// the outgoing screen's items lingering in the gap.
		.onChange(of: _selection.selectedTab) { _ in
			_toolbar.reset()
		}
	}

	// MARK: Grid

	private var _grid: some View {
		VStack(alignment: .trailing, spacing: _boxGap) {
			if _toolbar.isSearching {
				_searchField
			} else {
				HStack(spacing: _boxGap) {
					if _toolbar.config.hasSearch {
						_searchButton
					}
					if !_textActions.isEmpty {
						_textBox
					}
				}
			}

			HStack(alignment: .center, spacing: _boxGap) {
				if !_iconActions.isEmpty {
					_iconBox
				}
				_rail
			}
		}
		.padding(.trailing, 10)
		.offset(x: _isHidden ? 340 : 0)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
		.overlay(alignment: .trailing) { _edgeSwipeStrip }
		.animation(.spring(response: 0.4, dampingFraction: 0.8), value: _isHidden)
		.animation(.spring(response: 0.3, dampingFraction: 0.7), value: _isDragging)
		.animation(.spring(response: 0.3, dampingFraction: 0.8), value: _toolbar.isSearching)
		.zIndex(999)
	}

	// MARK: Rail

	private var _rail: some View {
		SwitcherGlassContainer(spacing: _itemGap) {
			VStack(alignment: .trailing, spacing: _itemGap) {
				ForEach(_tabs, id: \.self) { tab in
					_item(for: tab)
				}
			}
			.padding(_padding)
			.modifier(SwitcherGlass(shape: RoundedRectangle(cornerRadius: _corner, style: .continuous)))
		}
		.offset(x: _dragOffset)
		.scaleEffect(_isDragging ? 0.98 : 1.0)
		.gesture(_railDrag)
		// With the arrow gone the rail is its own control surface. A tap has to stay
		// free for the tabs inside it, so labels are a long press and hiding is a drag.
		.onLongPressGesture(minimumDuration: 0.35) { _toggleLabels() }
		.animation(.spring(response: 0.4, dampingFraction: 0.8), value: _isExpanded)
	}

	private func _item(for tab: TabEnum) -> some View {
		let isSelected = _selected == tab

		return Button {
			_select(tab)
		} label: {
			HStack(spacing: _labelSpacing) {
				if _isExpanded {
					Text(tab.title)
						.font(.system(size: 16, weight: .medium))
						.foregroundStyle(isSelected ? Color.userTint : Color.primary)
						.fixedSize()
						// Mirrors the icon's own slack so the rail is inset evenly on
						// both sides of the row.
						.padding(.leading, _slack)
						.transition(.move(edge: .leading).combined(with: .opacity))
				}

				Image(systemName: tab.icon)
					.font(.system(size: _glyph, weight: isSelected ? .semibold : .medium))
					.foregroundStyle(isSelected ? Color.userTint : Color.primary)
					.frame(width: _iconBox, height: _iconBox)
					.overlay(alignment: .topTrailing) { _tabBadge(for: tab) }
			}
			.frame(height: _iconBox)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		// A row is only as tall as its icon, so the touch target is grown to the full
		// pitch and the layout is pulled back — the hit area covers the gap between
		// rows without adding any visible space.
		.padding(.vertical, 3)
		.contentShape(Rectangle())
		.padding(.vertical, -3)
		.accessibilityLabel(tab.title)
	}

	@ViewBuilder
	private func _tabBadge(for tab: TabEnum) -> some View {
		let count = _badgeCount(for: tab)

		if count > 0 {
			_countBadge(count, font: 10)
				.offset(x: 6, y: -2)
		}
	}

	private func _badgeCount(for tab: TabEnum) -> Int {
		if tab == .sources && _showSourcesUpdateBadge { return _updates.updateCount }
		if tab == .tweaks { return _tweaks.defaultInjectCount }
		return 0
	}

	private func _countBadge(_ count: Int, font: CGFloat) -> some View {
		Text(verbatim: count > 99 ? "99+" : "\(count)")
			.font(.system(size: font, weight: .bold))
			.foregroundStyle(.white)
			.padding(.horizontal, 5)
			.padding(.vertical, 2)
			.background(Capsule().fill(.red))
	}

	// MARK: Toolbar boxes

	/// Icons with no word on them, in their own box beside the rail.
	private var _iconBox: some View {
		let glyph = _glyphFor(_iconActions.count)

		return HStack(spacing: _itemGap) {
			ForEach(_iconActions) { action in
				_control(action, glyph: glyph, showsTitle: false)
			}
		}
		.padding(_padding)
		.modifier(SwitcherGlass(shape: RoundedRectangle(cornerRadius: _corner, style: .continuous)))
	}

	/// Items that carry a word, in their own box directly above the rail.
	private var _textBox: some View {
		let glyph = _glyphFor(_textActions.count)

		return HStack(spacing: _labelSpacing + 4) {
			ForEach(_textActions) { action in
				_control(action, glyph: glyph, showsTitle: true)
			}
		}
		.padding(_padding)
		.modifier(SwitcherGlass(shape: RoundedRectangle(cornerRadius: _corner, style: .continuous)))
	}

	/// More than two controls in a box and they start shrinking. Fitting them is
	/// the answer "for now"; nothing is moved to a second box yet.
	private func _glyphFor(_ count: Int) -> CGFloat {
		guard count > 2 else { return _glyph }
		return max(11, _glyph * 2 / CGFloat(count))
	}

	@ViewBuilder
	private func _control(_ action: TabToolbarAction, glyph: CGFloat, showsTitle: Bool) -> some View {
		if action.menu.isEmpty {
			Button {
				action.action?()
				FeedbackManager.shared.tap(.light)
			} label: {
				_controlLabel(action, glyph: glyph, showsTitle: showsTitle)
			}
			.buttonStyle(.plain)
			.disabled(action.isDisabled)
			.accessibilityLabel(Text(action.title ?? action.id))
		} else {
			Menu {
				ForEach(action.menu) { entry in
					if entry.isDivider {
						Divider()
					} else {
						Button {
							entry.action()
						} label: {
							if entry.isSelected {
								Label(entry.title, systemImage: "checkmark")
							} else if let image = entry.systemImage {
								Label(entry.title, systemImage: image)
							} else {
								Text(entry.title)
							}
						}
					}
				}
			} label: {
				_controlLabel(action, glyph: glyph, showsTitle: showsTitle)
			}
			.disabled(action.isDisabled)
			.accessibilityLabel(Text(action.title ?? action.id))
		}
	}

	private func _controlLabel(_ action: TabToolbarAction, glyph: CGFloat, showsTitle: Bool) -> some View {
		HStack(spacing: 6) {
			Image(systemName: action.systemImage)
				.font(.system(size: glyph, weight: .medium))
				.overlay(alignment: .topTrailing) {
					if action.badge > 0 {
						_countBadge(action.badge, font: 9)
							.offset(x: 7, y: -5)
					}
				}

			if showsTitle, let title = action.title, !title.isEmpty {
				Text(title)
					.font(.system(size: 15, weight: .medium))
					.lineLimit(1)
					.fixedSize()
			}
		}
		.foregroundStyle(Color.primary)
		.frame(height: _iconBox)
		.frame(minWidth: _iconBox)
		.padding(.horizontal, showsTitle ? 4 : 0)
		.contentShape(Rectangle())
	}

	// MARK: Search

	private var _searchButton: some View {
		Button {
			withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
				_toolbar.isSearching = true
			}
			_searchFocused = true
			FeedbackManager.shared.tap(.light)
		} label: {
			Image(systemName: "magnifyingglass")
				.font(.system(size: _glyph, weight: .medium))
				.foregroundStyle(Color.primary)
				.frame(width: _circle, height: _circle)
				.contentShape(Circle())
				.modifier(SwitcherGlass(shape: Circle(), interactive: true))
		}
		.buttonStyle(.plain)
		.accessibilityLabel(.localized("Search"))
	}

	private var _searchField: some View {
		HStack(spacing: 8) {
			Image(systemName: "magnifyingglass")
				.font(.system(size: 15, weight: .medium))
				.foregroundStyle(.secondary)

			TextField(
				_toolbar.config.searchPrompt.isEmpty ? .localized("Search") : _toolbar.config.searchPrompt,
				text: $_toolbar.searchText
			)
			.focused($_searchFocused)
			.font(.system(size: 16))
			.submitLabel(.search)
			.autocorrectionDisabled()
			.textInputAutocapitalization(.never)

			Button {
				withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
					_toolbar.searchText = ""
					_toolbar.isSearching = false
				}
				_searchFocused = false
			} label: {
				Image(systemName: "xmark.circle.fill")
					.font(.system(size: 16))
					.foregroundStyle(.secondary)
			}
			.buttonStyle(.plain)
			.accessibilityLabel(.localized("Cancel"))
		}
		.padding(.horizontal, 14)
		.frame(width: _fieldWidth, height: _circle)
		.modifier(SwitcherGlass(shape: RoundedRectangle(cornerRadius: _circle / 2, style: .continuous)))
		.onAppear { _searchFocused = true }
	}

	// MARK: Edge reveal
	//
	// Only live while the rail is actually off screen. It used to also arm itself
	// whenever the handle auto-hid, which laid a 60pt invisible strip straight over
	// the rail — that is what was eating taps on the icons.

	private var _edgeSwipeStrip: some View {
		Color.clear
			.frame(width: 60)
			.frame(maxHeight: .infinity)
			.contentShape(Rectangle())
			.gesture(
				DragGesture(minimumDistance: 5)
					.onEnded { value in
						guard value.translation.width < -15 else { return }
						withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
							_isHidden = false
						}
						FeedbackManager.shared.tap(.medium)
					}
			)
			.allowsHitTesting(_isHidden)
	}

	// MARK: Gestures

	private var _railDrag: some Gesture {
		DragGesture(minimumDistance: 10)
			.onChanged { value in
				_isDragging = true
				if !_isExpanded {
					_dragOffset = value.translation.width * 0.5
				}
			}
			.onEnded { value in
				_isDragging = false
				let distance = value.translation.width
				let velocity = value.predictedEndTranslation.width

				withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
					_dragOffset = 0

					if distance < -20 || velocity < -40 {
						_isExpanded = true
						FeedbackManager.shared.tap(.medium)
					} else if distance > 20 || velocity > 40 {
						if _isExpanded {
							_isExpanded = false
						} else {
							_isHidden = true
						}
						FeedbackManager.shared.tap(.medium)
					}
				}
			}
	}

	// MARK: State

	private func _toggleLabels() {
		withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
			_isExpanded.toggle()
		}
		FeedbackManager.shared.tap(.light)
	}

	// MARK: Selection

	private func _select(_ tab: TabEnum) {
		FeedbackManager.shared.tap(.light)

		withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
			if tab == _selection.selectedTab && tab == .sources {
				_selection.sourcesRetapped.toggle()
			}
			_selection.selectedTab = tab
			// MySign collapsed the rail once a tab was picked, so the content is clear.
			if _isExpanded { _isExpanded = false }
		}
	}
}

// MARK: - Glass

/// Applies real Liquid Glass on iOS 26 and MySign's own recipe everywhere else:
/// ultra-thin material with a faint white stroke, which is what its rail and
/// handle were built from.
private struct SwitcherGlass<S: Shape>: ViewModifier {
	let shape: S
	var tint: Color?
	var interactive: Bool = false

	@ViewBuilder
	func body(content: Content) -> some View {
		if #available(iOS 26.0, *) {
			content.glassEffect(_glass, in: shape)
		} else {
			content.background { _fallback }
		}
	}

	@available(iOS 26.0, *)
	private var _glass: Glass {
		var glass: Glass = .regular
		if let tint { glass = glass.tint(tint) }
		if interactive { glass = glass.interactive() }
		return glass
	}

	private var _fallback: some View {
		ZStack {
			shape.fill(.ultraThinMaterial)
			if let tint { shape.fill(tint.opacity(0.35)) }
			shape.stroke(Color.white.opacity(0.12), lineWidth: 0.5)
		}
	}
}

/// Sibling glass shapes only blend inside a container, which is iOS 26 only — so
/// this passes content straight through on older systems.
private struct SwitcherGlassContainer<Content: View>: View {
	let spacing: CGFloat
	@ViewBuilder let content: () -> Content

	var body: some View {
		if #available(iOS 26.0, *) {
			GlassEffectContainer(spacing: spacing) {
				content()
			}
		} else {
			content()
		}
	}
}
