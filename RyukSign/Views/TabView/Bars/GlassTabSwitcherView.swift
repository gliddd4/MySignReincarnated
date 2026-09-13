//
//  GlassTabSwitcherView.swift
//  RyukSign
//
//  MySign's edge tab switcher, rebuilt on Apple's real Liquid Glass.
//
//  MySign pinned a collapsible vertical rail to the leading edge of the screen and
//  hand-rolled its "glass" out of VariableBlur plus an ultra-thin material at 30%
//  opacity. Two years later iOS 26 shipped the same idea with a real material, so
//  this keeps the interaction and geometry exactly as MySign had it — 44pt targets,
//  10pt gaps, a 20x100 drag handle, 15pt/25pt drag thresholds, tap and long-press
//  shortcuts, and a 10 second auto-hide — and swaps the hand-rolled blur for
//  `glassEffect(_:in:)`, with MySign's material recipe kept as the pre-26 fallback.
//
//  The arrow is MySign's chevron indicator. MySign swapped `chevron.right` for
//  `chevron.left` in a `Group`, which cannot animate — a symbol is inserted and
//  removed. Here it is one chevron that rotates to the state and leans with the
//  drag, so the arrow actually moves the way MySign's swap implied.
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
		case .glassSwitcher: return "rectangle.lefthalf.inset.filled"
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

	@Namespace private var _glass
	@State private var _dragOffset: CGFloat = 0
	@State private var _isDragging = false
	@State private var _isHandleAutoHidden = false
	/// Bumped on every interaction; the auto-hide task is keyed on it, so touching
	/// the handle restarts MySign's 10 second timer without any timer bookkeeping.
	@State private var _interaction = UUID()

	/// MySign's geometry, kept verbatim so the rail reads the same.
	private let _target: CGFloat = 44
	private let _itemGap: CGFloat = 10
	private let _railPadding: CGFloat = 8
	private let _handle: CGSize = .init(width: 20, height: 100)
	private let _handleHitWidth: CGFloat = 40
	private let _corner: CGFloat = 22
	private let _autoHideDelay: Duration = .seconds(10)

	private var _tabs: [TabEnum] {
		_prefs.visibleTabs
	}

	private var _selected: TabEnum {
		_tabs.contains(_selection.selectedTab) ? _selection.selectedTab : (_tabs.first ?? .library)
	}

	var body: some View {
		ZStack(alignment: .leading) {
			TabEnum.view(for: _selected)
				.environmentObject(_selection)
				.frame(maxWidth: .infinity, maxHeight: .infinity)

			_switcher
		}
	}

	// MARK: Switcher

	private var _switcher: some View {
		HStack(spacing: 0) {
			_rail
			_handleStrip
		}
		.padding(.leading, 10)
		.offset(x: _isHidden ? -260 : 0)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
		.overlay(alignment: .leading) { _edgeSwipeStrip }
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
			VStack(alignment: .leading, spacing: _itemGap) {
				ForEach(_tabs, id: \.self) { tab in
					_item(for: tab)
				}
			}
			.padding(_railPadding)
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
			HStack(spacing: 12) {
				ZStack {
					if isSelected {
						Color.clear
							.frame(width: _target, height: _target)
							.modifier(
								SwitcherGlass(
									shape: Circle(),
									tint: Color.userTint.opacity(0.75),
									interactive: true,
									morphID: "ryuk.glassSwitcher.selection",
									namespace: _glass
								)
							)
					}

					Image(systemName: tab.icon)
						.font(.system(size: 18, weight: isSelected ? .semibold : .medium))
						.foregroundStyle(isSelected ? Color.userTint : Color.primary)
						.frame(width: _target, height: _target)
				}
				.overlay(alignment: .topTrailing) { _badge(for: tab) }

				if _isExpanded {
					Text(tab.title)
						.font(.system(size: 16, weight: .medium))
						.foregroundStyle(isSelected ? Color.userTint : Color.primary)
						.fixedSize()
						.transition(.move(edge: .leading).combined(with: .opacity))
				}
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
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

	/// MySign's chevron indicator, with the flip it implied made real: the arrow
	/// rotates to the rail's state and leans with the drag as it is pulled.
	private var _arrow: some View {
		Image(systemName: "chevron.right")
			.font(.system(size: 12, weight: .bold))
			.foregroundStyle(_isDragging ? Color.userTint : Color.primary)
			.rotationEffect(_arrowAngle)
			.animation(.spring(response: 0.3, dampingFraction: 0.7), value: _isExpanded)
			.animation(.spring(response: 0.3, dampingFraction: 0.7), value: _isHidden)
	}

	private var _arrowAngle: Angle {
		let base: Double = _isExpanded ? 180 : 0
		guard _isDragging else { return .degrees(base) }
		// Lean up to 45 degrees either way while the handle is being pulled.
		let lean = min(max(Double(_dragOffset) / 60, -0.5), 0.5) * 90
		return .degrees(base + lean)
	}

	// MARK: Edge reveal

	private var _edgeSwipeStrip: some View {
		Color.clear
			.frame(width: 60)
			.frame(maxHeight: .infinity)
			.contentShape(Rectangle())
			.gesture(
				DragGesture(minimumDistance: 5)
					.onEnded { value in
						guard value.translation.width > 15 else { return }
						withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
							if _isHidden { _isHidden = false }
							_isHandleAutoHidden = false
						}
						_interaction = UUID()
						FeedbackManager.shared.tap(.medium)
					}
			)
			.allowsHitTesting(_isHidden || _isHandleAutoHidden)
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

					if distance > 20 || velocity > 40 {
						_isExpanded = true
						FeedbackManager.shared.tap(.medium)
					} else if distance < -20 || velocity < -40 {
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
				_interaction = UUID()
			}
			.onEnded { value in
				_isDragging = false
				let distance = value.translation.width
				let velocity = value.predictedEndTranslation.width

				withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
					_dragOffset = 0

					if distance > 15 || velocity > 25 {
						if _isHidden {
							_isHidden = false
						} else {
							_isExpanded = true
						}
						FeedbackManager.shared.tap(.medium)
					} else if distance < -15 || velocity < -25 {
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
		_interaction = UUID()

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

	// MARK: Selection

	private func _select(_ tab: TabEnum) {
		_interaction = UUID()
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
	var morphID: String?
	var namespace: Namespace.ID?

	@ViewBuilder
	func body(content: Content) -> some View {
		if #available(iOS 26.0, *) {
			if let morphID, let namespace {
				content
					.glassEffect(_glass, in: shape)
					.glassEffectID(morphID, in: namespace)
			} else {
				content.glassEffect(_glass, in: shape)
			}
		} else if let morphID, let namespace {
			content
				.background { _fallback }
				.matchedGeometryEffect(id: morphID, in: namespace)
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

/// Sibling glass shapes only blend and morph inside a container, which is iOS 26
/// only — so this passes content straight through on older systems.
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
