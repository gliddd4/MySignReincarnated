//
//  SourceCache.swift
//  RyukSign
//
//  Ported from MySign (mysignipasigner)'s RepositoryCacheManager.
//
//  MySign's edge over RyukSign was cold-start speed on enormous repositories: it
//  kept every repository on disk and rendered from there before the network
//  answered. This is that idea, rebuilt around raw response bodies — the
//  AltSourceKit models are `Decodable` only, and caching bytes is both simpler
//  and closer to what actually takes the time (the request, not the decode).
//
//  Layout: Documents/SourceCache/<sha256(url)>.json, one file per source URL.
//  Freshness comes from each file's modification date, so there is no manifest to
//  corrupt and deleting the folder is always safe.
//
//  The read and write paths are deliberately `nonisolated static`: they only
//  touch the filesystem, and a caller that has to hydrate dozens of multi-megabyte
//  bodies has to be able to do it off the main actor.
//

import Foundation
import Combine
import CryptoKit
import OSLog

private let _log = Logger(subsystem: "com.ryuksign.cache", category: "SourceCache")

@MainActor
final class SourceCache: ObservableObject {
	static let shared = SourceCache()

	/// App count + last successful refresh per source URL, so the browser can show
	/// (and sort by) how much each repository actually covers.
	struct CountEntry: Codable {
		var apps: Int
		var updated: Date
	}

	/// Published so rows and the "most apps first" sort update as counts land.
	@Published private(set) var counts: [String: CountEntry] = [:]

	/// The counts sidecar: app totals and refresh dates as one small JSON file,
	/// kept beside the cached bodies rather than inside their directory.
	private var _countsURL: URL {
		URL.documentsDirectory.appendingPathComponent("SourceCounts.json")
	}

	private init() {
		counts = _loadCounts()
	}

	// MARK: - App counts

	func appCount(for url: URL) -> Int? {
		counts[url.absoluteString]?.apps
	}

	func appCount(identifier: String) -> Int? {
		counts[identifier]?.apps
	}

	func lastUpdated(for url: URL) -> Date? {
		counts[url.absoluteString]?.updated
	}

	/// Recorded after every successful fetch, so the value survives relaunches.
	func recordAppCount(_ apps: Int, for url: URL) {
		counts[url.absoluteString] = CountEntry(apps: apps, updated: Date())
		_saveCounts()
	}

	/// Records a whole load's worth of counts and writes the sidecar once. The
	/// single-source version above writes per call, which for a sixty-source load
	/// meant sixty encodes and sixty atomic writes on the main actor.
	func recordAppCounts(_ apps: [URL: Int]) {
		guard !apps.isEmpty else { return }

		let now = Date()
		for (url, count) in apps {
			counts[url.absoluteString] = CountEntry(apps: count, updated: now)
		}
		_saveCounts()
	}

	func clearCounts() {
		counts = [:]
		try? FileManager.default.removeItem(at: _countsURL)
	}

	private func _loadCounts() -> [String: CountEntry] {
		guard
			let data = try? Data(contentsOf: _countsURL),
			let decoded = try? JSONDecoder().decode([String: CountEntry].self, from: data)
		else {
			return [:]
		}
		return decoded
	}

	private func _saveCounts() {
		guard let data = try? JSONEncoder().encode(counts) else { return }
		try? data.write(to: _countsURL, options: .atomic)
	}

	// MARK: - Read

	/// The cached response body for a source, if one was ever stored.
	func data(for url: URL) -> Data? {
		Self.cachedData(for: url)
	}

	/// Nonisolated so a load can read and decode cached bodies off the main actor.
	nonisolated static func cachedData(for url: URL) -> Data? {
		try? Data(contentsOf: location(for: url))
	}

	/// When the cached copy was stored.
	func timestamp(for url: URL) -> Date? {
		let attributes = try? FileManager.default.attributesOfItem(atPath: Self.location(for: url).path)
		return attributes?[.modificationDate] as? Date
	}

	/// True when a copy exists and is younger than `maxAge`.
	func isFresh(_ url: URL, maxAge: TimeInterval = 60 * 60 * 24) -> Bool {
		guard let timestamp = timestamp(for: url) else { return false }
		return Date().timeIntervalSince(timestamp) < maxAge
	}

	var cachedSourceCount: Int {
		let contents = try? FileManager.default.contentsOfDirectory(atPath: Self.directory.path)
		return contents?.filter { $0.hasSuffix(".json") }.count ?? 0
	}

	// MARK: - Write

	/// Stores a response body. Silently no-ops on failure — the cache is an
	/// optimisation, never a requirement.
	func store(_ data: Data, for url: URL) {
		Self.write(data, for: url)
	}

	/// Nonisolated so freshly downloaded bodies can be written without stalling
	/// the main actor on a multi-megabyte file write.
	nonisolated static func write(_ data: Data, for url: URL) {
		guard !data.isEmpty else { return }
		let destination = location(for: url)

		do {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			try data.write(to: destination, options: .atomic)
		} catch {
			_log.debug("cache write failed for \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
		}
	}

	/// Drops a single source's copy — used when a source is deleted.
	func remove(for url: URL) {
		Self.remove(url)
	}

	nonisolated static func remove(_ url: URL) {
		try? FileManager.default.removeItem(at: location(for: url))
	}

	/// Drops cached bodies, counts, icon tints and resolved icons — the "clear
	/// cache" button.
	func clear() {
		try? FileManager.default.removeItem(at: Self.directory)
		clearCounts()
		IconTintCache.shared.clear()
		RepositoryIconStore.shared.clear()
	}

	// MARK: - Maintenance

	/// Total bytes held on disk, for the storage screen.
	nonisolated static func sizeOnDisk() -> Int64 {
		guard let urls = try? FileManager.default.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: [.fileSizeKey]
		) else {
			return 0
		}

		return urls.reduce(into: Int64(0)) { total, url in
			let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
			total += Int64(size)
		}
	}

	func sizeOnDisk() -> Int64 {
		Self.sizeOnDisk()
	}

	/// Deletes entries older than `maxAge` so a long-neglected install doesn't
	/// keep megabytes of stale repositories around.
	nonisolated static func prune(olderThan maxAge: TimeInterval = 60 * 60 * 24 * 30) {
		guard let urls = try? FileManager.default.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: [.contentModificationDateKey]
		) else {
			return
		}

		let cutoff = Date().addingTimeInterval(-maxAge)
		for url in urls {
			let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
			if modified < cutoff {
				try? FileManager.default.removeItem(at: url)
			}
		}
	}

	func prune(olderThan maxAge: TimeInterval = 60 * 60 * 24 * 30) {
		Self.prune(olderThan: maxAge)
	}

	// MARK: - Private

	nonisolated static var directory: URL {
		URL.documentsDirectory.appendingPathComponent("SourceCache", isDirectory: true)
	}

	nonisolated static func location(for url: URL) -> URL {
		directory.appendingPathComponent("\(hash(url.absoluteString)).json")
	}

	/// Stable filename for a URL. Hashing keeps the name filesystem-safe for
	/// URLs with query strings (premium tokens, ?source=… parameters).
	nonisolated static func hash(_ string: String) -> String {
		let hex = SHA256.hash(data: Data(string.utf8))
			.map { String(format: "%02x", $0) }
			.joined()
		// Truncated: collisions are irrelevant at this scale, and short names
		// keep directory listings fast.
		return String(hex.prefix(40))
	}
}
