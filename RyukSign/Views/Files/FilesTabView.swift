//
//  FilesTabView.swift
//  RyukSign
//
//  Ported from MySign (mysignipasigner)'s Files tab UI.
//
//  MySign let you browse, rename, move, compress, share, delete and search the
//  app's own files, and view images with page-to-page cycling. That whole surface
//  was missing here. This is it, rebuilt on `FileBrowser` (which does no UI of
//  its own) so a folder pushed onto the stack and the root listing can never
//  disagree about what they are showing.
//
//  Scoped to the app container: MySign's "view system files" reached outside the
//  sandbox via an exploit that current iOS blocks, so that part is not carried
//  over — everything the app can legitimately see is browsable here.
//

import SwiftUI
import NimbleViews
import UniformTypeIdentifiers

// MARK: - Tab

struct FilesTabView: View {
	var body: some View {
		NBNavigationView(.localized("Files")) {
			FilesDirectoryView(directory: URL.documentsDirectory, isRoot: true)
				// Declared once, on the stack's root, so pushed folders resolve
				// against the same destination instead of shadowing each other.
				.navigationDestination(for: URL.self) { url in
					FilesDirectoryView(directory: url)
				}
		}
	}
}

// MARK: - Directory

struct FilesDirectoryView: View {
	let directory: URL
	var isRoot: Bool = false

	@ObservedObject private var _browser = FileBrowser.shared

	@State private var _entries: [FileEntry] = []
	@State private var _searchText: String = ""
	@AppStorage("RyukSign.filesSort") private var _sortRaw: String = ItemSortOption.nameAZ.rawValue

	@State private var _isPrompting = false
	@State private var _promptMode: _PromptMode = .newFolder
	@State private var _promptText: String = ""

	@State private var _moveEntry: FileEntry?
	@State private var _viewerEntry: FileEntry?

	private var _sortOption: ItemSortOption {
		ItemSortOption(rawValue: _sortRaw) ?? .nameAZ
	}

	private var _displayed: [FileEntry] {
		_browser.filtered(_entries, query: _searchText)
	}

	private var _emptyMessage: String {
		_searchText.isEmpty ? .localized("This folder is empty") : .localized("No matches")
	}

	// MARK: Body

	var body: some View {
		List {
			if isRoot && _searchText.isEmpty {
				Section {
					ForEach(_browser.shortcuts) { shortcut in
						NavigationLink(value: shortcut.url) {
							Label(shortcut.title, systemImage: shortcut.icon)
						}
					}
				} header: {
					Text(.localized("Locations"))
				}
			}

			if _displayed.isEmpty {
				Section {
					Text(verbatim: _emptyMessage)
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			} else {
				Section {
					ForEach(_displayed) { entry in
						_row(for: entry)
					}
				} header: {
					Text(verbatim: .localized("%lld items", arguments: _displayed.count))
				}
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle(isRoot ? .localized("Files") : directory.lastPathComponent)
		.navigationBarTitleDisplayMode(isRoot ? .large : .inline)
		.searchable(
			text: $_searchText,
			placement: .navigationBarDrawer(displayMode: .always),
			prompt: .localized("Search this folder")
		)
		.toolbar {
			ToolbarItem(placement: .navigationBarTrailing) {
				_sortMenu
			}
			ToolbarItem(placement: .navigationBarTrailing) {
				_addMenu
			}
		}
		.overlay {
			if _browser.isBusy {
				ProgressView()
					.padding(12)
					.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
			}
		}
		.onAppear(perform: _reload)
		// Any mutation anywhere in the browser refreshes whatever is on screen.
		.onReceive(NotificationCenter.default.publisher(for: .fileBrowserDidChange)) { _ in
			_reload()
		}
		.alert(_promptTitle, isPresented: $_isPrompting) {
			TextField(_promptMode == .newFolder ? .localized("Folder Name") : .localized("Name"), text: $_promptText)
			Button(.localized("Cancel"), role: .cancel) {}
			Button(.localized("Done")) {
				_commitPrompt()
			}
		}
		.sheet(item: $_moveEntry) { entry in
			FileMovePickerView(entry: entry)
		}
		.fullScreenCover(item: $_viewerEntry) { entry in
			ImagePagerView(directory: directory, start: entry)
		}
	}

	// MARK: Row

	@ViewBuilder
	private func _row(for entry: FileEntry) -> some View {
		if entry.isDirectory {
			NavigationLink(value: entry.url) {
				_label(for: entry)
			}
			.contextMenu { _menu(for: entry) }
		} else {
			Button {
				_open(entry)
			} label: {
				_label(for: entry)
			}
			.buttonStyle(.plain)
			.contextMenu { _menu(for: entry) }
		}
	}

	private func _label(for entry: FileEntry) -> some View {
		HStack(spacing: 12) {
			Image(systemName: entry.icon)
				.font(.body)
				.foregroundStyle(entry.isDirectory ? Color.accentColor : Color.secondary)
				.frame(width: 24)

			VStack(alignment: .leading, spacing: 2) {
				Text(entry.name)
					.lineLimit(2)
				Text(entry.subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}

	@ViewBuilder
	private func _menu(for entry: FileEntry) -> some View {
		Button(.localized("Rename"), systemImage: "pencil") {
			_promptMode = .rename(entry)
			_promptText = entry.name
			_isPrompting = true
		}

		Button(.localized("Duplicate"), systemImage: "plus.square.on.square") {
			_browser.duplicate(entry)
		}

		Button(.localized("Move"), systemImage: "arrow.turn.down.right") {
			_moveEntry = entry
		}

		if !entry.isDirectory {
			Button(.localized("Compress"), systemImage: "doc.zipper") {
				_browser.zip(entry)
			}
		}

		if entry.isZip {
			Button(.localized("Uncompress"), systemImage: "doc.zipper") {
				_browser.unzip(entry)
			}
		}

		Button(.localized("Share"), systemImage: "square.and.arrow.up") {
			UIActivityViewController.show(activityItems: [entry.url])
		}

		Button(.localized("Copy Path"), systemImage: "doc.on.clipboard") {
			UIPasteboard.general.string = entry.url.path
			Toast.success(.localized("Path copied"), systemImage: "doc.on.clipboard")
		}

		Divider()

		Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
			_browser.delete(entry)
		}
	}

	// MARK: Toolbar

	private var _sortMenu: some View {
		Menu {
			Picker(.localized("Sort"), selection: $_sortRaw) {
				ForEach(ItemSortOption.allCases) { option in
					Label(option.label, systemImage: option.systemImage)
						.tag(option.rawValue)
				}
			}
		} label: {
			Image(systemName: "arrow.up.arrow.down")
		}
	}

	private var _addMenu: some View {
		Menu {
			Button(.localized("New Folder"), systemImage: "folder.badge.plus") {
				_promptMode = .newFolder
				_promptText = ""
				_isPrompting = true
			}
			Button(.localized("Import Files"), systemImage: "square.and.arrow.down") {
				DocumentPicker.open([.item], multiple: true) { urls in
					_browser.importFiles(urls, into: directory)
				}
			}
		} label: {
			Image(systemName: "plus")
		}
	}

	// MARK: Actions

	private func _reload() {
		_entries = _browser.sorted(_browser.list(directory), by: _sortOption)
	}

	private func _open(_ entry: FileEntry) {
		// Images open the pager so they can be cycled; anything else is most
		// likely on its way somewhere, so offer it to the share sheet.
		if entry.isImage {
			_viewerEntry = entry
		} else {
			UIActivityViewController.show(activityItems: [entry.url])
		}
	}

	private var _promptTitle: String {
		switch _promptMode {
		case .newFolder: return .localized("New Folder")
		case .rename:    return .localized("Rename")
		}
	}

	private func _commitPrompt() {
		switch _promptMode {
		case .newFolder:
			_browser.makeFolder(named: _promptText, in: directory)
		case .rename(let entry):
			_browser.rename(entry, to: _promptText)
		}
	}
}

// MARK: - Prompt mode

private enum _PromptMode: Equatable {
	case newFolder
	case rename(FileEntry)
}

// MARK: - Move destination

/// Picks where a file should go. Deliberately a flat list of the container's
/// known locations plus its top-level folders — moving into a nested folder is
/// rare enough that browsing for it would just be more surface to get wrong.
struct FileMovePickerView: View {
	let entry: FileEntry

	@ObservedObject private var _browser = FileBrowser.shared
	@Environment(\.dismiss) private var dismiss

	/// The file's own folder is skipped — moving something onto itself is not an
	/// operation, and offering it invites a confusing no-op.
	private var _destinations: [FileLocation] {
		let parent = entry.url.deletingLastPathComponent().standardizedFileURL

		let topLevel = _browser.list(URL.documentsDirectory)
			.filter(\.isDirectory)
			.filter { $0.url.standardizedFileURL != parent }
			.map { FileLocation(title: $0.name, icon: "folder", url: $0.url) }

		return _browser.shortcuts.filter { $0.url.standardizedFileURL != parent } + topLevel
	}

	var body: some View {
		NBNavigationView(.localized("Move"), displayMode: .inline) {
			List {
				Section {
					Text(entry.name)
						.font(.footnote)
						.foregroundStyle(.secondary)
						.lineLimit(2)
				}

				Section {
					ForEach(_destinations) { destination in
						Button {
							_browser.move(entry, into: destination.url)
							dismiss()
						} label: {
							Label(destination.title, systemImage: destination.icon)
						}
					}
				} header: {
					Text(.localized("Move To"))
				}
			}
			.listStyle(.insetGrouped)
			.toolbar {
				NBToolbarButton(role: .dismiss)
			}
		}
	}
}
