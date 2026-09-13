//
//  TabToolbar.swift
//  RyukSign
//
//  The glass tab bar draws the *view* toolbars, not the tab bar: each screen's
//  toolbar items are published here and rendered into the glass grid instead of
//  the navigation bar. SwiftUI offers no way to read back what a `.toolbar`
//  block contributed, so screens have to say.
//
//  A screen decides which box its items land in by whether they carry a word:
//  an item with a `title` goes in the text box above the switcher, one without
//  goes in the icon-only box beside it.
//

import SwiftUI

// MARK: - Menu entry

/// One row inside a control that opens a menu. Screens that used a `Menu` or a
/// `Picker` in their toolbar describe the same choices here, since a `Menu`
/// cannot be handed across as a value.
struct TabToolbarMenuEntry: Identifiable {
	let id: String
	var title: String = ""
	var systemImage: String?
	var isSelected: Bool = false
	var isDivider: Bool = false
	var action: () -> Void = {}

	static func divider(_ id: String) -> TabToolbarMenuEntry {
		TabToolbarMenuEntry(id: id, isDivider: true)
	}
}

// MARK: - Action

struct TabToolbarAction: Identifiable {
	let id: String
	var systemImage: String
	/// A word on the control. Non-empty means it belongs in the text box above
	/// the switcher rather than the icon-only box beside it.
	var title: String?
	var badge: Int = 0
	var isDisabled: Bool = false
	/// Non-empty turns the control into a menu of these.
	var menu: [TabToolbarMenuEntry] = []
	/// Last on purpose: a trailing closure then binds to the action rather than to
	/// the menu, so call sites read `TabToolbarAction(id: "add", systemImage: "plus") { ... }`.
	var action: (() -> Void)?

	var hasText: Bool {
		!(title ?? "").isEmpty
	}
}

// MARK: - Config

struct TabToolbarConfig {
	var iconActions: [TabToolbarAction] = []
	var textActions: [TabToolbarAction] = []
	var hasSearch: Bool = false
	var searchPrompt: String = ""

	/// Cheap identity, so a screen only republishes when something visible about
	/// its toolbar changed rather than on every re-render.
	var key: String {
		let icons = iconActions
			.map { "\($0.id):\($0.badge):\($0.isDisabled)" }
			.joined(separator: ",")
		let texts = textActions
			.map { "\($0.id):\($0.title ?? ""):\($0.isDisabled)" }
			.joined(separator: ",")
		return "\(hasSearch)|\(searchPrompt)|\(icons)|\(texts)"
	}
}

// MARK: - Registry

final class TabToolbarRegistry: ObservableObject {
	static let shared = TabToolbarRegistry()

	@Published private(set) var config = TabToolbarConfig()

	/// The query in the glass search field. The system search field is not
	/// attached in this style, so screens mirror this into their own filter.
	@Published var searchText: String = ""
	@Published var isSearching: Bool = false

	/// The active tab's screen is the only publisher, and it publishes on appear.
	func apply(_ config: TabToolbarConfig) {
		guard config.key != self.config.key else { return }
		self.config = config
	}

	/// Switching tabs must not leave the previous screen's items on screen while
	/// the new screen is still appearing.
	func reset() {
		config = TabToolbarConfig()
		searchText = ""
		isSearching = false
	}
}

// MARK: - View plumbing

extension View {
	/// Publishes this screen's view-toolbar items to the glass grid. Harmless
	/// while the system tab bar is in use, since the grid is not on screen then.
	func tabToolbar(_ config: TabToolbarConfig) -> some View {
		self
			.onAppear { TabToolbarRegistry.shared.apply(config) }
			.onChange(of: config.key) { _ in
				TabToolbarRegistry.shared.apply(config)
			}
	}

	/// The glass style puts search in its own glass field, so the system search
	/// field must not also be attached — two fields would fight over one query.
	@ViewBuilder
	func adaptiveSearchable(
		text: Binding<String>,
		style: TabBarStyle,
		placement: SearchFieldPlacement = .platform(),
		prompt: String? = nil
	) -> some View {
		if style == .glassSwitcher {
			self.onChange(of: TabToolbarRegistry.shared.searchText) { newValue in
				if text.wrappedValue != newValue {
					text.wrappedValue = newValue
				}
			}
		} else if let prompt {
			self.searchable(text: text, placement: placement, prompt: Text(prompt))
		} else {
			self.searchable(text: text, placement: placement)
		}
	}
}
