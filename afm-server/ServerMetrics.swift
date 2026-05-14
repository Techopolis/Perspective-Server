//
//  ServerMetrics.swift
//  afm-server
//
//  Tracks server usage metrics: requests, tokens, time-to-first-token.
//

import Foundation

/// Centralized metrics collector for the afm-server.
/// All properties are isolated to this actor for thread safety.
actor ServerMetrics {
    static let shared = ServerMetrics()

    // MARK: - Request Tracking

    /// Total requests handled since server start (all endpoints)
    private(set) var totalRequests: Int = 0

    /// Total inference requests (chat/completions endpoints only)
    private(set) var totalInferenceRequests: Int = 0

    /// Timestamps of recent requests for rolling window calculations
    private var recentRequestTimestamps: [Date] = []

    // MARK: - Token Tracking

    /// Total tokens generated across all inference requests
    private(set) var totalTokens: Int = 0

    // MARK: - Timing

    /// Time-to-first-token values for recent requests (seconds)
    private var recentTTFT: [Double] = []
    private let maxTTFTHistory = 100

    // MARK: - Recording

    /// Record that a request was received (call for every HTTP request)
    func recordRequest() {
        totalRequests += 1
        let now = Date()
        recentRequestTimestamps.append(now)
        pruneOldTimestamps(now: now)
    }

    /// Record an inference request with token count and TTFT
    func recordInference(tokens: Int, timeToFirstToken: Double?) {
        totalInferenceRequests += 1
        totalTokens += tokens

        if let ttft = timeToFirstToken {
            recentTTFT.append(ttft)
            if recentTTFT.count > maxTTFTHistory {
                recentTTFT.removeFirst()
            }
        }
    }

    // MARK: - Queries

    /// Number of requests in the last N minutes
    func requestsInLast(minutes: Int) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(minutes * 60))
        return recentRequestTimestamps.filter { $0 > cutoff }.count
    }

    /// Average time-to-first-token in seconds (nil if no data)
    var averageTTFT: Double? {
        guard !recentTTFT.isEmpty else { return nil }
        return recentTTFT.reduce(0, +) / Double(recentTTFT.count)
    }

    /// Last recorded TTFT in seconds (nil if no data)
    var lastTTFT: Double? {
        recentTTFT.last
    }

    /// Snapshot of all metrics for UI display
    var snapshot: MetricsSnapshot {
        let now = Date()
        pruneOldTimestamps(now: now)
        let cutoff5 = now.addingTimeInterval(-300)
        let reqs5min = recentRequestTimestamps.filter { $0 > cutoff5 }.count

        return MetricsSnapshot(
            totalRequests: totalRequests,
            totalInferenceRequests: totalInferenceRequests,
            totalTokens: totalTokens,
            requestsLast5Min: reqs5min,
            averageTTFT: averageTTFT,
            lastTTFT: lastTTFT
        )
    }

    /// Reset all metrics (e.g. on server restart)
    func reset() {
        totalRequests = 0
        totalInferenceRequests = 0
        totalTokens = 0
        recentRequestTimestamps.removeAll()
        recentTTFT.removeAll()
    }

    // MARK: - Private

    /// Remove timestamps older than 10 minutes to bound memory
    private func pruneOldTimestamps(now: Date) {
        let cutoff = now.addingTimeInterval(-600)
        recentRequestTimestamps.removeAll { $0 <= cutoff }
    }
}

// MARK: - Stream Metrics Tracker

/// Lightweight tracker for a single streaming inference request.
/// Used to capture TTFT and token count from within a @Sendable closure.
/// Access is safe because streaming emit callbacks are called sequentially.
nonisolated final class StreamMetricsTracker: @unchecked Sendable {
    private let start = ContinuousClock.now
    private var _firstTokenEmitted = false
    private(set) var ttft: Double? = nil
    private(set) var tokenCount: Int = 0

    func recordDelta(_ delta: String) {
        if !_firstTokenEmitted {
            _firstTokenEmitted = true
            let elapsed = ContinuousClock.now - start
            ttft = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        }
        tokenCount += max(1, delta.count / 4)
    }
}

// MARK: - Snapshot Type

struct MetricsSnapshot: Sendable {
    let totalRequests: Int
    let totalInferenceRequests: Int
    let totalTokens: Int
    let requestsLast5Min: Int
    let averageTTFT: Double?
    let lastTTFT: Double?
}
