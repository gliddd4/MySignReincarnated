//
//  FileBrowser.swift
//  RyukSign
//
//  Ported from MySign (mysignipasigner)'s Files tab (DirectoryViewModel +
//  FileUtilities + FilesMenu*).
//
//  A browser over the app's own container: navigate, search, rename, move,
//  delete, zip/unzip and share. Scoped to the app's Documents directory on
//  purpose — the old build reached outside the sandbox through an iOS 14-era
//  exploit, which no longer works and is not something this build wants to
//  carry. Everything the app can legitimately see, it can browse here.
//
//  The service is stateless: callers ask for a listing of a directory, and every
//  mutation announces itself through `fileBrowserDidChange` so whichever
//  directory views are on screen can refresh themselves. Keeping the current
//  directory in a singleton instead meant a pushed folder and the root could
//  disagree about what was on screen.
//

import Foundation
import SwiftUI
import Zip
import NimbleExtensions

extension Notification.Name {
	/// Posted after any file-system mutation the browser performs.
	static let fileBrowserDidChange = Notification.Name("RyukSign.fileBrowserDidChange")
}

// MARK: - Location

/// A named place inside the container. A struct rather than a tuple because
/// `ForEach` needs a key path, and Swift has no key paths into tuples.
struct FileLocation: Identifiable, Hashable {
	var title: String
	var icon: String
	var url: URL

	var id: String { url.absoluteString }
}

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

	/// True while a zip/unzip is running, so the UI can show it.
	@Published private(set) var isBusy: Bool = false

	private init() {}

	/// The container root. Nothing outside it is browsable.
	var root: URL { URL.documentsDirectory }

	/// Convenient starting points, all inside the container.
	var shortcuts: [FileLocation] {
		let fm = FileManager.default
		return [
			FileLocation(title: .localized("Documents"), icon: "folder", url: URL.documentsDirectory),
			FileLocation(title: .localized("Archives"), icon: "archivebox", url: fm.archives),
			FileLocation(title: .localized("Signed"), icon: "checkmark.seal", url: fm.signed),
			FileLocation(title: .localized("Unsigned"), icon: "doc.badge.clock", url: fm.unsigned),
			FileLocation(title: .localized("Certificates"), icon: "person.text.rectangle", url: fm.certificates),
			FileLocation(title: .localized("Tweaks"), icon: "wrench.and.screwdriver", url: fm.tweaksLibrary)
		]
	}

	/// Refuses to walk outside the container.
	func isBrowsable(_ url: URL) -> Bool {
		url.standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path)
	}

	// MARK: Listing

	func list(_ directory: URL) -> [FileEntry] {
		guard isBrowsable(directory) else { return [] }

		let keys: [URLResourceKey] = [
			.isDirectoryKey,
			.fileSizeKey,
			.totalFileAllocatedSizeKey,
			.contentModificationDateKey
		]

		let urls = (try? FileManager.default.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: keys,
			options: [.skipsHiddenFiles]
		)) ?? []

		return urls.compactMap { url in
			guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
			return FileEntry(
				url: url,
				isDirectory: values.isDirectory ?? false,
				size: Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0),
				modified: values.contentModificationDate ?? .distantPast
			)
		}
	}

	/// Folders first, then by the chosen order.
	func sorted(_ entries: [FileEntry], by sort: ItemSortOption) -> [FileEntry] {
		let directories = entries.filter(\.isDirectory).sorted { _isOrdered($0, $1, sort) }
		let files = entries.filter { !$0.isDirectory }.sorted { _isOrdered($0, $1, sort) }
		return directories + files
	}

	func filtered(_ entries: [FileEntry], query: String) -> [FileEntry] {
		let trimmed = query.trimmingCharacters(in: .whitespaces)
		guard !trimmed.isEmpty else { return entries }
		return entries.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
	}

	/// Children of a directory that are images, in listing order — the image
	/// viewer pages through exactly this so cycling matches what was on screen.
	func images(in directory: URL) -> [FileEntry] {
		sorted(list(directory), by: .nameAZ).filter(\.isImage)
	}

	// MARK: Operations

	func makeFolder(named name: String, in directory: URL) {
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
			_announce()
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
			_announce()
		} catch {
			Toast.error(error.localizedDescription, duration: .long)
		}
	}

	func delete(_ entry: FileEntry) {
		do {
			try FileManager.default.removeItem(at: entry.url)
			Toast.success(.localized("Deleted"), systemImage: "trash.fill")
			_announce()
		} catch {
			Toast.error(error.localizedDescription, duration: .long)
		}
	}

	func duplicate(_ entry: FileEntry) {
		let base = entry.url.deletingPathExtension().lastPathComponent
		let ext = entry.pathExtension
		let parent = entry.url.deletingLastPathComponent()

		var index = 2
		var destination = parent.appendingPathComponent(ext.isEmpty ? "\(base) copy" : "\(base) copy.\(ext)")
		while FileManager.default.fileExists(atPath: destination.path), index < 100 {
			destination = parent.appendingPathComponent(ext.isEmpty ? "\(base) copy \(index)" : "\(base) copy \(index).\(ext)")
			index += 1
		}

		do {
			try FileManager.default.copyItem(at: entry.url, to: destination)
			Toast.success(.localized("Duplicated"), systemImage: "plus.square.on.square")
			_announce()
		} catch {
			Toast.error(error.localizedDescription, duration: .long)
		}
	}

	func move(_ entry: FileEntry, into target: URL) {
		guard isBrowsable(target) else { return }

		let destination = target.appendingPathComponent(entry.name)
		guard destination.standardizedFileURL.path != entry.url.standardizedFileURL.path else { return }
		guard !FileManager.default.fileExists(atPath: destination.path) else {
			Toast.error(.localized("Something with that name already exists"), duration: .long)
			return
		}

		do {
			try FileManager.default.moveItem(at: entry.url, to: destination)
			Toast.success(.localized("Moved"), systemImage: "arrow.turn.down.right")
			_announce()
		} catch {
			Toast.error(error.localizedDescription, duration: .long)
		}
	}

	/// Copies files the user picked into a directory.
	func importFiles(_ urls: [URL], into directory: URL) {
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
			_announce()
		}
	}

	/// Packs a file/folder into a `.zip` sitting next to it.
	func zip(_ entry: FileEntry) {
		let parent = entry.url.deletingLastPathComponent()
		let destination = parent.appendingPathComponent("\(entry.url.deletingPathExtension().lastPathComponent).zip")

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
			self._announce()
		}
	}

	/// Unpacks a `.zip` into a sibling folder named after the archive.
	func unzip(_ entry: FileEntry) {
		let parent = entry.url.deletingLastPathComponent()
		let base = parent.appendingPathComponent(
			entry.url.deletingPathExtension().lastPathComponent,
			isDirectory: true
		)

		// Don't silently merge into an existing folder — suffix instead.
		var target = base
		var index = 2
		while FileManager.default.fileExists(atPath: target.path), index <= 100 {
			target = parent.appendingPathComponent("\(base.lastPathComponent) \(index)", isDirectory: true)
			index += 1
		}

		isBusy = true
		_offMain {
			try FileManager.default.createDirectoryIfNeeded(at: target)
			try Zip.unzipFile(entry.url, destination: target, overwrite: true, password: nil, progress: nil)
		} completion: { [weak self] result in
			guard let self else { return }
			self.isBusy = false
			switch result {
			case .success:
				Toast.success(.localized("Unpacked"), systemImage: "doc.zipper")
			case .failure(let error):
				// Leave no half-extracted folder behind.
				try? FileManager.default.removeItem(at: target)
				Toast.error(error.localizedDescription, duration: .long)
			}
			self._announce()
		}
	}

	// MARK: Internal

	private func _isOrdered(_ lhs: FileEntry, _ rhs: FileEntry, _ sort: ItemSortOption) -> Bool {
		switch sort {
		case .nameAZ:      return lhs.sortName < rhs.sortName
		case .nameZA:      return lhs.sortName > rhs.sortName
		case .dateNewest:  return lhs.sortDate > rhs.sortDate
		case .dateOldest:  return lhs.sortDate < rhs.sortDate
		case .sizeLargest: return lhs.sortSize > rhs.sortSize
		}
	}

	private func _announce() {
		NotificationCenter.default.post(name: .fileBrowserDidChange, object: nil)
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
