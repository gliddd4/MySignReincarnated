//
//  FileBrowser.swift
//  RyukSign
//
//  Ported from MySign (mysignipasigner)'s Files tab (DirectoryViewModel +
//  FileUtilities + FilesMenu*).
//
//  A browser over the app's own container: navigate, search, rename, move,
//  delete, zip/unzip and share. Scoped to the app's Documents directory on
//  purpose — the old build reached into /System via a sandbox exploit, which
//  does not work on current iOS and is not something this build wants to carry.
//

import Foundation
import SwiftUI
import Zip
import NimbleExtensions

// MARK: - Entry

struct FileEntry: Identifiable, Hashable, SortableItem {
	/// Path is stable across reloads and unique within a directory.
	var id: String { url.path }

	let url: URL
	let isDirectory: Bool
	let size: Int64
	let modified: Date

	var name: String { url.lastPathComponent }
	var pathExtension: String { url.pathExtension.lowercased() }

	// MARK: SortableItem

	var sortName: String { name.lowercased() }
	var sortDate: Date { modified }
	var sortSize: Int64 { size }

	// MARK: Kind

	var isImage: Bool {
		["png", "jpg", "jpeg", "gif", "heic", "webp", "bmp", "tiff"].contains(pathExtension)
	}

	var isZip: Bool { pathExtension == "zip" }

	var isIPA: Bool { pathExtension == "ipa" || pathExtension == "tipa" }

	/// Anything that can be handed to Zsign / the installer.
	var isInstallable: Bool { isIPA }

	var isCertBundle: Bool { pathExtension == "p12" || pathExtension == "mobileprovision" }

	var isTweak: Bool { ["dylib", "deb", "framework"].contains(pathExtension) }

	var icon: String {
		if isDirectory { return "folder.fill" }
		if isInstallable { return "shippingbox.fill" }
		if isZip { return "doc.zipper" }
		if isCertBundle { return "checkmark.seal.fill" }
		if isTweak { return "wrench.and.screwdriver.fill" }
		if isImage { return "photo.fill" }
		if pathExtension == "mobileprovision" { return "doc.badge.gearshape" }
		if ["plist", "json", "txt", "log", "md"].contains(pathExtension) { return "doc.text.fill" }
		return "doc.fill"
	}

	var subtitle: String {
		if isDirectory {
			return modified.formatted(date: .abbreviated, time: .shortened)
		}
		let sizeText = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
		return "\(sizeText) · \(modified.formatted(date: .abbreviated, time: .shortened))"
	}
}

// MARK: - Browser

@MainActor
final class FileBrowser: ObservableObject {
	static let shared = FileBrowser()

	@Published private(set) var directory: URL
	@Published private(set) var entries: [FileEntry] = []
	@Published var searchText: String = ""
	@Published var sort: ItemSortOption = .nameAZ {
		didSet { applySort() }
	}
	@Published private(set) var isBusy: Bool = false

	/// Everything the browser can see — the app's own container.
	private var root: URL { URL.documentsDirectory }

	/// Convenient starting points, all inside the container.
	var shortcuts: [(title: String, icon: String, url: URL)] {
		let fm = FileManager.default
		return [
			("Documents", "folder", URL.documentsDirectory),
			("Archives", "archivebox", fm.archives),
			("Signed", "checkmark.seal", fm.signed),
			("Unsigned", "doc.badge.clock", fm.unsigned),
			("Certificates", "person.text.rectangle", fm.certificates),
			("Tweaks", "wrench.and.screwdriver", fm.tweaksLibrary)
		]
	}

	private init() {
		directory = URL.documentsDirectory
		reload()
	}

	// MARK: Navigation

	/// True while the browser is below the container root.
	var canGoUp: Bool {
		directory.standardizedFileURL.path != root.standardizedFileURL.path
	}

	/// Root → current, for the breadcrumb.
	var breadcrumbs: [URL] {
		let rootPath = root.standardizedFileURL.path
		let currentPath = directory.standardizedFileURL.path
		guard currentPath.hasPrefix(rootPath) else { return [root] }

		var result: [URL] = [root]
		let relative = currentPath.dropFirst(rootPath.count)
		var accumulated = root
		for component in relative.split(separator: "/") {
			accumulated = accumulated.appendingPathComponent(String(component))
			result.append(accumulated)
		}
		return result
	}

	func open(_ url: URL) {
		// Refuse to walk outside the container.
		guard url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path) else { return }
		directory = url
		searchText = ""
		reload()
	}

	func goUp() {
		guard canGoUp else { return }
		directory = directory.deletingLastPathComponent()
		searchText = ""
		reload()
	}

	func reload() {
		let fm = FileManager.default
		let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .totalFileAllocatedSizeKey, .contentModificationDateKey]

		let urls = (try? fm.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: keys,
			options: [.skipsHiddenFiles]
		)) ?? []

		entries = urls.compactMap { url in
			guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
			return FileEntry(
				url: url,
				isDirectory: values.isDirectory ?? false,
				size: Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0),
				modified: values.contentModificationDate ?? .distantPast
			)
		}

		applySort()
	}

	/// Search-filtered, sorted entries for the UI.
	var displayedEntries: [FileEntry] {
		let query = searchText.trimmingCharacters(in: .whitespaces)
		guard !query.isEmpty else { return entries }
		return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
	}

	// MARK: Operations

	func makeFolder(named name: String) {
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }

		let target = directory.appendingPathComponent(trimmed, isDirectory: true)
		guard !FileManager.default.fileExists(atPath: target.path) else {
			Toast.error(.localized("Something with that name already exists"), duration: .long)
			return
		}

		do {
			try FileManager.default.createDirectoryIfNeeded(at: target)
			Toast.success(.localized("Folder created"), systemImage: "folder.badge.plus")
			reload()
		} catch {
			Toast.error(error.localizedDescription, duration: .long)
		}
	}

	func rename(_ entry: FileEntry, to newName: String) {
		let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty, trimmed != entry.name else { return }

		// Keep the original extension unless the user typed their own.
		var target = trimmed
		if !entry.isDirectory, (trimmed as NSString).pathExtension.isEmpty, !entry.pathExtension.isEmpty {
			target = "\(trimmed).\(entry.pathExtension)"
		}

		let destination = entry.url.deletingLastPathComponent().appendingPathComponent(target)
		guard !FileManager.default.fileExists(atPath: destination.path) else {
			Toast.error(.localized("Something with that name already exists"), duration: .long)
			return
		}

		do {
			try FileManager.default.moveItem(at: entry.url, to: destination)
			Toast.success(.localized("Renamed"), systemImage: "pencil")
			reload()
		} catch {
			Toast.error(error.localizedDescription, duration: .long)
		}
	}

	func delete(_ entry: FileEntry) {
		do {
			try FileManager.default.removeItem(at: entry.url)
			Toast.success(.localized("Deleted"), systemImage: "trash.fill")
			reload()
		} catch {
			Toast.error(error.localizedDescription, duration: .long)
		}
	}

	func move(_ entry: FileEntry, into target: URL) {
		let destination = target.appendingPathComponent(entry.name)

		guard destination.standardizedFileURL.path != entry.url.standardizedFileURL.path else { return }
		guard !FileManager.default.fileExists(atPath: destination.path) else {
			Toast.error(.localized("Something with that name already exists"), duration: .long)
			return
		}

		do {
			try FileManager.default.moveItem(at: entry.url, to: destination)
			Toast.success(.localized("Moved"), systemImage: "arrow.turn.down.right")
			reload()
		} catch {
			Toast.error(error.localizedDescription, duration: .long)
		}
	}

	/// Copies files the user picked into the directory on screen.
	func importFiles(_ urls: [URL]) {
		guard !urls.isEmpty else { return }
		var imported = 0

		for url in urls {
			let destination = directory.appendingPathComponent(url.lastPathComponent)
			if FileManager.default.fileExists(atPath: destination.path) {
				Toast.error(.localized("%@ already exists", arguments: url.lastPathComponent), duration: .long)
				continue
			}
			do {
				try FileManager.default.copyItem(at: url, to: destination)
				imported += 1
			} catch {
				Toast.error(error.localizedDescription, duration: .long)
			}
		}

		if imported > 0 {
			Toast.success(.localized("Imported %lld item(s)", arguments: imported), systemImage: "square.and.arrow.down.fill")
			reload()
		}
	}

	/// Packs a file/folder into a `.zip` sitting next to it.
	func zip(_ entry: FileEntry) {
		let destination = directory.appendingPathComponent("\(entry.url.deletingPathExtension().lastPathComponent).zip")
		guard !FileManager.default.fileExists(atPath: destination.path) else {
			Toast.error(.localized("An archive with that name already exists"), duration: .long)
			return
		}

		let compression = ZipCompression(rawValue: UserDefaults.standard.integer(forKey: "Feather.compressionLevel"))
			?? ZipCompression.DefaultCompression

		isBusy = true
		_offMain {
			try Zip.zipFiles(paths: [entry.url], zipFilePath: destination, password: nil, compression: compression, progress: nil)
		} completion: { [weak self] result in
			guard let self else { return }
			self.isBusy = false
			switch result {
			case .success:
				Toast.success(.localized("Archive created"), systemImage: "doc.zipper")
			case .failure(let error):
				Toast.error(error.localizedDescription, duration: .long)
			}
			self.reload()
		}
	}

	/// Unpacks a `.zip` into a sibling folder named after the archive.
	func unzip(_ entry: FileEntry) {
		let base = directory.appendingPathComponent(
			entry.url.deletingPathExtension().lastPathComponent,
			isDirectory: true
		)

		// Don't silently merge into an existing folder — suffix instead.
		var finalTarget = base
		var index = 2
		while FileManager.default.fileExists(atPath: finalTarget.path) {
			finalTarget = directory.appendingPathComponent("\(base.lastPathComponent) \(index)", isDirectory: true)
			index += 1
			if index > 100 { break }
		}

		isBusy = true
		_offMain {
			try FileManager.default.createDirectoryIfNeeded(at: finalTarget)
			try Zip.unzipFile(entry.url, destination: finalTarget, overwrite: true, password: nil, progress: nil)
		} completion: { [weak self] result in
			guard let self else { return }
			self.isBusy = false
			switch result {
			case .success:
				Toast.success(.localized("Unpacked"), systemImage: "doc.zipper")
			case .failure(let error):
				// Leave no half-extracted folder behind.
				try? FileManager.default.removeItem(at: finalTarget)
				Toast.error(error.localizedDescription, duration: .long)
			}
			self.reload()
		}
	}

	// MARK: Internal

	private func applySort() {
		let directoriesFirst = entries.filter(\.isDirectory).sorted(by: _comparator)
		let files = entries.filter { !$0.isDirectory }.sorted(by: _comparator)
		entries = directoriesFirst + files
	}

	private func _comparator(_ lhs: FileEntry, _ rhs: FileEntry) -> Bool {
		switch sort {
		case .nameAZ:     return lhs.sortName < rhs.sortName
		case .nameZA:     return lhs.sortName > rhs.sortName
		case .dateNewest: return lhs.sortDate > rhs.sortDate
		case .dateOldest: return lhs.sortDate < rhs.sortDate
		case .sizeLargest: return lhs.sortSize > rhs.sortSize
		}
	}

	/// Runs blocking archive work off the main thread and reports back on it.
	private func _offMain(
		_ work: @escaping () throws -> Void,
		completion: @escaping (Result<Void, Error>) -> Void
	) {
		DispatchQueue.global(qos: .userInitiated).async {
			do {
				try work()
				DispatchQueue.main.async { completion(.success(())) }
			} catch {
				DispatchQueue.main.async { completion(.failure(error)) }
			}
		}
	}
}

// MARK: - Helpers
