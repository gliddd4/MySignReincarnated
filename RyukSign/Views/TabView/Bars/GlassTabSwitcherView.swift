//
//  GlassTabSwitcherView.swift
//  RyukSign
//
//  MySign's edge tab switcher, rebuilt on Apple's real Liquid Glass.
//
//  MySign pinned a collapsible vertical rail to the screen edge and hand-rolled
//  its "glass" out of VariableBlur plus an ultra-thin material at 30% opacity, two
//  years before iOS 26 shipped the real material. This keeps the interaction —
//  10pt/25pt drag thresholds, a 20x100 drag handle, tap and long-press shortcuts,
//  and a 10 second auto-hide — and drops the hand-rolled blur for
//  `glassEffect(_:in:)`, with MySign's own recipe kept as the pre-26 fallback.
//
//  Geometry notes, because the spacing is deliberately tied together:
//  the rail insets and the gap between rows are chosen so the space *around* an
//  icon is the same in every direction. The glyph sits in a slightly larger box,
//  so `_slack` is added to the label's outer edge and doubled into `_itemGap`.
//
//  The arrow is MySign's chevron indicator. MySign flipped it by swapping
//  `chevron.right` for `chevron.left` inside a `Group`, which cannot animate — a
//  symbol is inserted and removed. Here it is one chevron that rotates to the
//  rail's state and leans with the drag, so the arrow moves the way the swap implied.
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
	@AppStorage("Feather.showSourcesUpdateBadge") private var _showSourcesUpdateBadge: Bool = true
	@AppStorage("Feather.glassSwitcherExpanded") private var _isExpanded: Bool = false
	@AppStorage("Feather.glassSwitcherHidden") private var _isHidden: Bool = false

	@State private var _dragOffset: CGFloat = 0
	@State private var _isDragging = false
	@State private var _isHandleAutoHidden = false
	/// Bumped on every interaction; the auto-hide task is keyed on it, so touching
	/// the rail restarts MySign's 10 second timer without any timer bookkeeping.
	@State private var _interaction = UUID()

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
	/// Grows each row's touch target to the full pitch without moving anything.
	private let _hitPad: CGFloat = 3
	private let _handle: CGSize = .init(width: 20, height: 100)
	private let _handleHitWidth: CGFloat = 40
	private let _corner: CGFloat = 22
	private let _autoHideDelay: Duration = .seconds(10)
	/// Centre the rail a quarter of the way down from the top instead of the middle.
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

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .trailing) {
				TabEnum.view(for: _selected)
					.environmentObject(_selection)
					.frame(width: geometry.size.width, height: geometry.size.height)

				_switcher
					.offset(y: -geometry.size.height * _verticalShift)
			}
		}
	}

	// MARK: Switcher

	private var _switcher: some View {
		HStack(spacing: 0) {
			_handleStrip
			_rail
		}
		.padding(.trailing, 10)
		.offset(x: _isHidden ? 260 : 0)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
		.overlay(alignment: .trailing) { _edgeSwipeStrip }
		.animation(.spring(response: 0.4, dampingFraction: 0.8), value: _isHidden)
		.animation(.spring(response: 0.3, dampingFraction: 0.7), value: _isDragging)
		.animation(.easeInOut(duration: 0.3), value: _isHandleAutoHidden)
		.zIndex(999)
		.task(id: _interaction) {
			try? await Task.sleep(for: _autoHideDelay)
			guard !Task.isCancelled else { return }
			withAnimation(.easeInOut(duration: 0.3)) {
				_isHandleAutoHidden = true
			}
		}
	}

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
					.overlay(alignment: .topTrailing) { _badge(for: tab) }
			}
			.frame(height: _iconBox)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		// A row is only as tall as its icon, so the touch target is grown to the full
		// pitch and the layout is pulled back — the hit area covers the gap between
		// rows without adding any visible space.
		.padding(.vertical, _hitPad)
		.contentShape(Rectangle())
		.padding(.vertical, -_hitPad)
		.accessibilityLabel(tab.title)
	}

	@ViewBuilder
	private func _badge(for tab: TabEnum) -> some View {
		let count = _badgeCount(for: tab)

		if count > 0 {
			Text(verbatim: count > 99 ? "99+" : "\(count)")
				.font(.system(size: 10, weight: .bold))
				.foregroundStyle(.white)
				.padding(.horizontal, 5)
				.padding(.vertical, 2)
				.background(Capsule().fill(.red))
				.offset(x: 6, y: -2)
		}
	}

	private func _badgeCount(for tab: TabEnum) -> Int {
		if tab == .sources && _showSourcesUpdateBadge { return _updates.updateCount }
		if tab == .tweaks { return _tweaks.defaultInjectCount }
		return 0
	}

	// MARK: Handle

	private var _handleStrip: some View {
		VStack(spacing: 0) {
			Spacer(minLength: 0)

			ZStack {
				Color.clear
					.frame(width: _handle.width, height: _handle.height)
					.modifier(
						SwitcherGlass(
							shape: RoundedRectangle(cornerRadius: 12, style: .continuous),
							interactive: true
						)
					)

				_arrow
			}
			.opacity(_isHandleAutoHidden ? 0 : 1)
			.scaleEffect(_isDragging ? 1.15 : 1.0)
			.offset(x: _isDragging ? _dragOffset * 0.3 : 0)

			Spacer(minLength: 0)
		}
		.frame(width: _handleHitWidth)
		.contentShape(Rectangle())
		.gesture(_handleDrag)
		.onTapGesture { _toggleFromHandle(light: true) }
		.onLongPressGesture(minimumDuration: 0.3) { _toggleFromHandle(light: false) }
	}

	/// On a trailing rail the arrow points the way the rail has to be dragged to
	/// change state: left to pull it out, right to push it back.
	private var _arrow: some View {
		Image(systemName: "chevron.right")
			.font(.system(size: 12, weight: .bold))
			.foregroundStyle(_isDragging ? Color.userTint : Color.primary)
			.rotationEffect(_arrowAngle)
			.animation(.spring(response: 0.3, dampingFraction: 0.7), value: _isExpanded)
			.animation(.spring(response: 0.3, dampingFraction: 0.7), value: _isHidden)
	}

	private var _arrowAngle: Angle {
		let base: Double = _isExpanded ? 0 : 180
		guard _isDragging else { return .degrees(base) }
		// Lean up to 45 degrees either way while the handle is being pulled.
		let lean = min(max(Double(-_dragOffset) / 60, -0.5), 0.5) * 90
		return .degrees(base + lean)
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
							_isHandleAutoHidden = false
						}
						_interaction = UUID()
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
				_wake()
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
							_isHandleAutoHidden = true
						}
						FeedbackManager.shared.tap(.medium)
					}
				}
			}
	}

	private var _handleDrag: some Gesture {
		DragGesture(minimumDistance: 5)
			.onChanged { value in
				_isDragging = true
				_dragOffset = value.translation.width * 0.3
				_wake()
			}
			.onEnded { value in
				_isDragging = false
				let distance = value.translation.width
				let velocity = value.predictedEndTranslation.width

				withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
					_dragOffset = 0

					if distance < -15 || velocity < -25 {
						if _isHidden {
							_isHidden = false
						} else {
							_isExpanded = true
						}
						FeedbackManager.shared.tap(.medium)
					} else if distance > 15 || velocity > 25 {
						if _isExpanded {
							_isExpanded = false
						} else {
							_isHidden = true
							_isHandleAutoHidden = true
						}
						FeedbackManager.shared.tap(.medium)
					}
				}
			}
	}

	private func _toggleFromHandle(light: Bool) {
		_wake()

		withAnimation(.spring(response: light ? 0.3 : 0.2, dampingFraction: light ? 0.7 : 0.6)) {
			if light {
				if _isHidden {
					_isHidden = false
				} else if _isExpanded {
					_isExpanded = false
				} else {
					_isExpanded = true
				}
			} else {
				// Long press skips a step: collapsed goes straight to hidden, and
				// hidden comes back already expanded.
				if _isHidden {
					_isHidden = false
					_isExpanded = true
				} else if _isExpanded {
					_isExpanded = false
					_isHidden = true
				} else {
					_isExpanded = true
				}
			}
			_isHandleAutoHidden = false
		}

		if light {
			FeedbackManager.shared.tap(.light)
		} else {
			FeedbackManager.shared.tap(.heavy)
		}
	}

	/// Any interaction keeps the handle on screen and restarts its idle timer.
	private func _wake() {
		_interaction = UUID()
		guard _isHandleAutoHidden else { return }
		withAnimation(.easeInOut(duration: 0.2)) {
			_isHandleAutoHidden = false
		}
	}

	// MARK: Selection

	private func _select(_ tab: TabEnum) {
		_wake()
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
