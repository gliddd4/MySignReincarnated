//
//  RepositoryIconStore.swift
//  RyukSign
//
//  Ported from MySign (mysignipasigner)'s IconManager / RepositoryIconView.
//
//  Plenty of repositories never declare an `iconURL`, and they used to render as
//  the same generic placeholder — indistinguishable from every other icon-less
//  repository in a long list. MySign's answer was to walk the repository's apps
//  and keep the first icon that actually loads. That is the right idea; the only
//  change here is that the resolved bytes are cached on disk, so a fallback costs
//  one request ever rather than one per launch.
//
//  Layout: Documents/RepositoryIcons/<sha256(key)>.png, keyed by source URL.
//

import SwiftUI
import UIKit
import Combine
import CryptoKit
import OSLog

@MainActor
final class RepositoryIconStore: ObservableObject {
	static let shared = RepositoryIconStore()

	private let _logger = Logger(subsystem: "com.ryuksign.cache", category: "RepositoryIcons")

	/// Resolved icons for this session, keyed by source URL.
	@Published private(set) var images: [String: UIImage] = [:]

	/// Keys currently being resolved, so a scrolling list doesn't queue the same
	/// download once per recycled row.
	private var _inFlight: Set<String> = []

	private var _directory: URL {
		URL.documentsDirectory.appendingPathComponent("RepositoryIcons", isDirectory: true)
	}

	private init() {
		_loadFromDisk()
	}

	// MARK: - Read

	func image(for key: String) -> UIImage? {
		images[key]
	}

	var cachedCount: Int { images.count }

	func sizeOnDisk() -> Int64 {
		guard let urls = try? FileManager.default.contentsOfDirectory(
			at: _directory,
			includingPropertiesForKeys: [.fileSizeKey]
		) else {
			return 0
		}

		return urls.reduce(into: Int64(0)) { total, url in
			let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
			total += Int64(size)
		}
	}

	// MARK: - Resolve

	/// Walks `candidates` in order and keeps the first icon that downloads.
	/// Cheap to call from `onAppear`: it no-ops once an icon is cached.
	func ensureIcon(for key: String, candidates: [URL]) {
		guard !key.isEmpty, images[key] == nil, !_inFlight.contains(key) else { return }
		_resolve(key: key, candidates: candidates)
	}

	/// Forgets the cached icon and resolves again — the context menu action.
	func refreshIcon(for key: String, candidates: [URL]) {
		guard !key.isEmpty else { return }
		images[key] = nil
		_inFlight.remove(key)
		try? FileManager.default.removeItem(at: _location(for: key))
		_resolve(key: key, candidates: candidates)
	}

	func remove(for key: String) {
		images[key] = nil
		try? FileManager.default.removeItem(at: _location(for: key))
	}

	func clear() {
		images.removeAll()
		_inFlight.removeAll()
		try? FileManager.default.removeItem(at: _directory)
	}

	// MARK: - Private

	private func _resolve(key: String, candidates: [URL]) {
		guard let first = candidates.first else { return }
		_inFlight.insert(key)

		_attempt(first, remaining: Array(candidates.dropFirst())) { [weak self] image in
			guard let self else { return }
			self._inFlight.remove(key)

			guard let image else { return }
			self.images[key] = image

			guard let data = image.pngData() else { return }
			try? FileManager.default.createDirectory(at: self._directory, withIntermediateDirectories: true)
			try? data.write(to: self._location(for: key), options: .atomic)
		}
	}

	/// Tries one candidate, then hands off to the next. Each request is short so a
	/// dead icon host can't stall the row behind a 60-second default timeout.
	private func _attempt(_ url: URL, remaining: [URL], completion: @escaping (UIImage?) -> Void) {
		var request = URLRequest(url: url)
		request.timeoutInterval = 4
		request.cachePolicy = .returnCacheDataElseLoad

		URLSession.shared.dataTask(with: request) { [weak self] data, _, _ in
			let image = data.flatMap { UIImage(data: $0) }

			if let image {
				DispatchQueue.main.async { completion(image) }
				return
			}

			guard let next = remaining.first, let self else {
				DispatchQueue.main.async { completion(nil) }
				return
			}

			DispatchQueue.main.async {
				self._attempt(next, remaining: Array(remaining.dropFirst()), completion: completion)
			}
		}.resume()
	}

	private func _loadFromDisk() {
		guard let contents = try? FileManager.default.contentsOfDirectory(
			at: _directory,
			includingPropertiesForKeys: nil
		) else {
			return
		}

		for url in contents {
			guard
				let data = try? Data(contentsOf: url),
				let image = UIImage(data: data)
			else {
				continue
			}
			images[url.deletingPathExtension().lastPathComponent] = image
		}

		if !images.isEmpty {
			_logger.debug("loaded \(self.images.count, privacy: .public) cached repository icons")
		}
	}

	private func _location(for key: String) -> URL {
		_directory.appendingPathComponent("\(_hash(key)).png")
	}

	private func _hash(_ string: String) -> String {
		let hex = SHA256.hash(data: Data(string.utf8))
			.map { String(format: "%02x", $0) }
			.joined()
		return String(hex.prefix(40))
	}
}
