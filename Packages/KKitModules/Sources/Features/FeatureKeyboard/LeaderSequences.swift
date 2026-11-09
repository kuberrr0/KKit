import Foundation

/// Matching typed keys against leader sequences, kept pure for tests.
enum LeaderMatcher {
    enum Step: Equatable {
        /// Exactly one sequence is typed and nothing longer starts with it.
        case run(LeaderSequence)
        /// More keys could follow. `exact` runs if the user stops here.
        case waiting(exact: LeaderSequence?, candidates: [LeaderSequence])
        case noMatch
    }

    static func step(_ typed: String, sequences: [LeaderSequence]) -> Step {
        let typed = typed.lowercased()
        let candidates = sequences.filter { sequence in
            let keys = sequence.normalizedKeys
            return !keys.isEmpty && keys.hasPrefix(typed)
        }
        guard !candidates.isEmpty else { return .noMatch }
        let exact = candidates.first { $0.normalizedKeys == typed }
        if let exact, candidates.count == 1 {
            return .run(exact)
        }
        return .waiting(exact: exact, candidates: candidates)
    }

    /// What each candidate needs next: ("d", "New Daily Note").
    static func nextKeys(after typed: String, candidates: [LeaderSequence]) -> [(key: String, title: String)] {
        let typed = typed.lowercased()
        return candidates.compactMap { sequence in
            let keys = sequence.normalizedKeys
            guard keys.count > typed.count else { return nil }
            let rest = String(keys.dropFirst(typed.count))
            return (rest, sequence.title)
        }
        .sorted { $0.key < $1.key }
    }
}
