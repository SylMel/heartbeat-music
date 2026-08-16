import Foundation

public enum HeartbeatMode: String, CaseIterable, Equatable, Sendable {
    case workout
    case relax
}

public struct TrackSelectionConfiguration: Equatable, Sendable {
    /// Weight given to the newest sample in the exponential moving average.
    public var smoothingFactor: Double

    /// A new track must improve the tempo distance by more than this value.
    public var switchAdvantageBPM: Double

    /// How long a lower-BPM candidate must remain preferred in Workout Mode.
    public var workoutSlowdownDelay: TimeInterval

    /// How far below the smoothed heart rate Relax Mode places its music target.
    public var relaxationOffsetBPM: Double

    public init(
        smoothingFactor: Double = 0.28,
        switchAdvantageBPM: Double = 3,
        workoutSlowdownDelay: TimeInterval = 210,
        relaxationOffsetBPM: Double = 15
    ) {
        precondition((0...1).contains(smoothingFactor))
        precondition(switchAdvantageBPM >= 0)
        precondition(workoutSlowdownDelay >= 0)
        precondition(relaxationOffsetBPM >= 0)
        self.smoothingFactor = smoothingFactor
        self.switchAdvantageBPM = switchAdvantageBPM
        self.workoutSlowdownDelay = workoutSlowdownDelay
        self.relaxationOffsetBPM = relaxationOffsetBPM
    }
}

public struct SelectionSnapshot: Equatable, Sendable {
    public let rawHeartRate: Double
    public let smoothedHeartRate: Double
    public let match: TrackMatch
    public let didChangeTrack: Bool
    public let mode: HeartbeatMode
    public let workoutSlowdownRemaining: TimeInterval?

    public init(
        rawHeartRate: Double,
        smoothedHeartRate: Double,
        match: TrackMatch,
        didChangeTrack: Bool,
        mode: HeartbeatMode,
        workoutSlowdownRemaining: TimeInterval?
    ) {
        self.rawHeartRate = rawHeartRate
        self.smoothedHeartRate = smoothedHeartRate
        self.match = match
        self.didChangeTrack = didChangeTrack
        self.mode = mode
        self.workoutSlowdownRemaining = workoutSlowdownRemaining
    }
}

public struct TrackSelectionEngine: Sendable {
    private let matcher: TempoMatcher
    private let configuration: TrackSelectionConfiguration
    private var smoothedHeartRate: Double?
    private var selectedTrack: Track?
    private var activeMode: HeartbeatMode?
    private var slowdownBeganAt: Date?

    public init(
        tracks: [Track],
        configuration: TrackSelectionConfiguration = .init()
    ) {
        matcher = TempoMatcher(tracks: tracks)
        self.configuration = configuration
    }

    public mutating func cancelPendingWorkoutSlowdown() {
        slowdownBeganAt = nil
    }

    public mutating func update(
        heartRate: Double,
        mode: HeartbeatMode = .workout,
        at date: Date = Date()
    ) -> SelectionSnapshot {
        if activeMode != mode {
            activeMode = mode
            slowdownBeganAt = nil
        }

        let smoothed = smooth(heartRate)
        let targetBPM = targetBPM(for: smoothed, mode: mode)
        let candidate = matcher.bestMatch(for: targetBPM)
        let previousTrack = selectedTrack

        if let currentTrack = selectedTrack, currentTrack != candidate.track {
            let current = matcher.bestMatch(for: currentTrack, heartRate: targetBPM)
            if candidate.distance + configuration.switchAdvantageBPM < current.distance {
                if mode == .workout, candidate.track.bpm < currentTrack.bpm {
                    holdOrAcceptWorkoutSlowdown(candidate.track, at: date)
                } else {
                    selectedTrack = candidate.track
                    slowdownBeganAt = nil
                }
            } else {
                slowdownBeganAt = nil
            }
        } else if selectedTrack == nil {
            selectedTrack = candidate.track
            slowdownBeganAt = nil
        } else {
            slowdownBeganAt = nil
        }

        let selectedMatch = matcher.bestMatch(for: selectedTrack!, heartRate: targetBPM)
        return SelectionSnapshot(
            rawHeartRate: heartRate,
            smoothedHeartRate: smoothed,
            match: selectedMatch,
            didChangeTrack: previousTrack != selectedTrack,
            mode: mode,
            workoutSlowdownRemaining: slowdownRemaining(at: date)
        )
    }

    private func targetBPM(for smoothedHeartRate: Double, mode: HeartbeatMode) -> Double {
        switch mode {
        case .workout:
            smoothedHeartRate
        case .relax:
            smoothedHeartRate - configuration.relaxationOffsetBPM
        }
    }

    private mutating func holdOrAcceptWorkoutSlowdown(_ candidate: Track, at date: Date) {
        guard let slowdownBeganAt else {
            self.slowdownBeganAt = date
            return
        }

        if date.timeIntervalSince(slowdownBeganAt) >= configuration.workoutSlowdownDelay {
            selectedTrack = candidate
            self.slowdownBeganAt = nil
        }
    }

    private func slowdownRemaining(at date: Date) -> TimeInterval? {
        guard let slowdownBeganAt else { return nil }
        return max(0, configuration.workoutSlowdownDelay - date.timeIntervalSince(slowdownBeganAt))
    }

    private mutating func smooth(_ sample: Double) -> Double {
        guard let previous = smoothedHeartRate else {
            smoothedHeartRate = sample
            return sample
        }

        let next = previous + configuration.smoothingFactor * (sample - previous)
        smoothedHeartRate = next
        return next
    }
}
