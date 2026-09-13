//
//  SourcesViewModel.swift
//  RyukSign
//
//  Created by samara on 30.04.2025.
//

import Foundation
import AltSourceKit
import SwiftUI
import NimbleJSON
import OSLog

// MARK: - Class
final class SourcesViewModel: ObservableObject {
	static let shared = SourcesViewModel()

	typealias RepositoryDataHandler = Result<ASRepository, Error>

	private let _dataService = NBFetchService()

	/// `true` when no load is in progress (idle).
	@Published var isFinished = true
	@Published var sources: [AltSource: ASRepository] = [:]

	/// The single in-flight load. All loads are serialized through this.
	private var currentFetchTask: Task<Void, Never>?
	/// Monotonic token identifying the active load (Task isn't Equatable).
	private var fetchGeneration = 0
	/// Source URLs of the last completed load; skips re-fetching an identical set.
	private var lastLoadedKey: Set<String>?
	private var backgroundTaskManager: BackgroundTaskManager?

	private func key(for sources: [AltSource]) -> Set<String> {
		Set(sources.compactMap { $0.sourceURL?.absoluteString })
	}

	/// Reset the loading state - useful when app returns from background
	@MainActor
	func resetLoadingState() {
		currentFetchTask?.cancel()
		currentFetchTask = nil
		fetchGeneration += 1
		isFinished = true
		lastLoadedKey = nil
		backgroundTaskManager?.stop()
		backgroundTaskManager = nil
	}

	/// Loads every source's repository. Concurrent calls are serialized and coalesced.
	@MainActor
	func fetchSources(_ sources: FetchedResults<AltSource>, refresh: Bool = false, batchSize: Int = 4) async {
		let sourcesArray = Array(sources)
		let newKey = key(for: sourcesArray)

		// Coalesce: wait out any in-flight load. The task self-clears in its own
		// defer so awaiters exit instead of busy-spinning the main actor (0x8BADF00D).
		while let running = currentFetchTask {
			await running.value
		}

		// Same source set already loaded — skip (pull-to-refresh bypasses this).
		if !refresh, newKey == lastLoadedKey {
			return
		}

		fetchGeneration += 1
		let generation = fetchGeneration
		let task = Task {
			defer {
				// Self-clear exactly once, unless a newer load already replaced us.
				if generation == self.fetchGeneration {
					self.currentFetchTask = nil
				}
			}
			await self._performFetch(sourcesArray, key: newKey, batchSize: batchSize)
		}
		currentFetchTask = task
		await task.value
	}

	@MainActor
	private func _performFetch(_ sourcesArray: [AltSource], key: Set<String>, batchSize: Int) async {
		isFinished = false

		if backgroundTaskManager == nil {
			backgroundTaskManager = BackgroundTaskManager(
				taskName: "SourcesViewModel",
				expirationTitle: "Loading repositories",
				expirationBody: "Repository loading will continue when you reopen the app"
			)
			backgroundTaskManager?.start()
		}

		defer {
			lastLoadedKey = key
			isFinished = true
			backgroundTaskManager?.stop()
			backgroundTaskManager = nil
		}

		// Read CoreData (AltSource) fields on the main actor — it's not thread-safe.
		struct FetchItem {
			let source: AltSource
			let url: URL
			let headers: [String: String]
			let isPremium: Bool
		}

		let items: [FetchItem] = sourcesArray.compactMap { source in
			guard let url = source.sourceURL else {
				Logger.misc.error("Source has no URL: \(source.name ?? "Unknown", privacy: .public)")
				return nil
			}
			return FetchItem(
				source: source,
				url: RyukSignAPI.catalogURL(for: url),
				headers: RyukSignAPI.authHeaders(for: url),
				isPremium: RyukSignAPI.isPremiumSource(url)
			)
		}

		Logger.misc.info("fetchSources START: \(items.count, privacy: .public) sources")

		let service = _dataService
		// Publish into a working copy cumulatively so `sources` is never blanked mid-load.
		var working: [AltSource: ASRepository] = [:]

		// Disk cache first: render every repository we already have before the
		// network is touched, so a large source set is on screen immediately
		// instead of after the slowest request.
		//
		// The reads and the decodes happen off the main actor. They used to run
		// right here, synchronously, one multi-megabyte body at a time — which is
		// precisely the cost this cache exists to remove, so the cache was paying
		// it back on the main thread before anything could draw.
		let cachedURLs = items.map(\.url)
		let cached: [(index: Int, repo: ASRepository)] = await Task.detached(priority: .userInitiated) {
			cachedURLs.enumerated().compactMap { index, url in
				guard
					let body = SourceCache.cachedData(for: url),
					let repo = try? JSONDecoder().decode(ASRepository.self, from: body)
				else {
					return nil
				}
				return (index, repo)
			}
		}.value

		if !cached.isEmpty {
			// Counts come off the cached copy too, so the browser can sort by size
			// the moment the app launches instead of after the first refresh.
			var counts: [URL: Int] = [:]
			for entry in cached {
				working[items[entry.index].source] = entry.repo
				counts[items[entry.index].url] = entry.repo.apps.count
			}
			SourceCache.shared.recordAppCounts(counts)

			Logger.misc.info("fetchSources CACHE: \(cached.count, privacy: .public)/\(items.count, privacy: .public) sources rendered from disk")
			self.sources = working
		}

		for startIndex in stride(from: 0, to: items.count, by: batchSize) {
			let endIndex = min(startIndex + batchSize, items.count)
			let batch = Array(items[startIndex..<endIndex])

			// Child tasks touch only Sendable values, never the NSManagedObject.
			// Raw bytes come back too so the response can be cached verbatim.
			let fetched: [(Int, ASRepository?, Data?)] = await withTaskGroup(of: (Int, ASRepository?, Data?).self) { group in
				for (offset, item) in batch.enumerated() {
					let globalIndex = startIndex + offset
					let url = item.url
					let headers = item.headers
					let isPremium = item.isPremium

					group.addTask {
						await withCheckedContinuation { (continuation: CheckedContinuation<(Int, ASRepository?, Data?), Never>) in
							service.fetchRaw(from: url, headers: headers) { result in
								switch result {
								case .success(let data):
									do {
										let repo = try JSONDecoder().decode(ASRepository.self, from: data)
										continuation.resume(returning: (globalIndex, repo, data))
									} catch {
										Logger.misc.error("Source parse FAILED\(isPremium ? " [PREMIUM]" : "", privacy: .public) \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
										continuation.resume(returning: (globalIndex, nil, nil))
									}
								case .failure(let error):
									Logger.misc.error("Source fetch FAILED\(isPremium ? " [PREMIUM]" : "", privacy: .public) \(url.absoluteString, privacy: .public): \(error.localizedDescription, privacy: .public)")
									continuation.resume(returning: (globalIndex, nil, nil))
								}
							}
						}
					}
				}

				var collected: [(Int, ASRepository?, Data?)] = []
				for await triple in group {
					collected.append(triple)
				}
				return collected
			}

			// `items` holds NSManagedObjects, so the batch is applied here — but only
			// the values are touched, and one sidecar write now covers the whole batch
			// instead of one per source.
			var counts: [URL: Int] = [:]
			var bodies: [(URL, Data)] = []

			for (idx, repo, data) in fetched {
				guard let repo else { continue }
				working[items[idx].source] = repo
				counts[items[idx].url] = repo.apps.count
				// Keep the newest successful body for the next cold start.
				if let data {
					bodies.append((items[idx].url, data))
				}
			}

			SourceCache.shared.recordAppCounts(counts)

			// The bodies are only needed on the next launch, so they go to disk off
			// the main actor rather than stalling the rows that are about to appear.
			if !bodies.isEmpty {
				await Task.detached(priority: .utility) {
					for (url, data) in bodies {
						SourceCache.write(data, for: url)
					}
				}.value
			}

			// Publish progress (grows, never empties).
			self.sources = working
		}

		// Directory-wide maintenance off the main actor: it stats every cached file
		// and has nothing to do with what the user is looking at.
		await Task.detached(priority: .background) {
			SourceCache.prune()
		}.value

		Logger.misc.info("fetchSources DONE: \(working.count, privacy: .public)/\(items.count, privacy: .public) loaded")
	}
}
