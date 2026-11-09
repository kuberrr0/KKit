import Foundation

/// Scores how well a typed query matches a title, from 0 to 1. Every search provider
/// uses it, so "ns" finds Night Shift and "sys set" finds System Settings the same way
/// everywhere.
///
/// Roughly: exact 1.0 › title starts with the query 0.9 › a word starts with it 0.8 ›
/// every query word starts a title word 0.78 › initials ("ns") 0.75 › contains 0.65 ›
/// letters in order 0.3–0.6. Matches on keywords count 85% of a title match.
public enum FuzzyMatch {
    public static func score(_ query: String, in candidate: String) -> Double? {
        let needle = normalize(query)
        let haystack = normalize(candidate)
        guard !needle.isEmpty, !haystack.isEmpty else { return nil }
        if haystack == needle {
            return 1
        }
        let ratio = Double(needle.count) / Double(max(haystack.count, 1))
        if haystack.hasPrefix(needle) {
            return 0.9 + 0.09 * ratio
        }
        let words = words(of: haystack)
        if words.contains(where: { $0.hasPrefix(needle) }) {
            return 0.8 + 0.05 * ratio
        }
        let queryWords = needle.split(separator: " ").map(String.init)
        if queryWords.count > 1, wordsMatchInOrder(queryWords, words) {
            return 0.78
        }
        if needle.count >= 2, !needle.contains(" "), initialsMatch(needle, words) {
            return 0.75
        }
        if haystack.contains(needle) {
            return 0.65 + 0.05 * ratio
        }
        let compact = needle.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 2, let span = subsequenceSpan(compact, in: haystack) else { return nil }
        return 0.3 + 0.3 * Double(compact.count) / Double(span)
    }

    /// The best of the title and the keywords (keywords count a little less).
    public static func score(_ query: String, title: String, keywords: [String] = []) -> Double? {
        var best = score(query, in: title)
        for keyword in keywords {
            guard let keywordScore = score(query, in: keyword) else { continue }
            let weighted = keywordScore * 0.85
            if weighted > (best ?? 0) {
                best = weighted
            }
        }
        return best
    }

    /// Lowercased, accents removed, runs of spaces collapsed.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    // MARK: Private

    private static func words(of text: String) -> [String] {
        text.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    /// Each query word starts a title word, in order.
    private static func wordsMatchInOrder(_ queryWords: [String], _ words: [String]) -> Bool {
        var index = 0
        for queryWord in queryWords {
            var found = false
            while index < words.count {
                defer { index += 1 }
                if words[index].hasPrefix(queryWord) {
                    found = true
                    break
                }
            }
            if !found {
                return false
            }
        }
        return true
    }

    /// "ns" → "Night Shift", "vsc" → "Visual Studio Code".
    private static func initialsMatch(_ needle: String, _ words: [String]) -> Bool {
        let initials = words.compactMap(\.first)
        guard initials.count >= needle.count else { return false }
        var remaining = needle[...]
        for initial in initials where remaining.first == initial {
            remaining = remaining.dropFirst()
            if remaining.isEmpty {
                return true
            }
        }
        return false
    }

    /// The length of the shortest stretch of `haystack` that holds `needle`'s letters
    /// in order (greedy), or `nil` if they aren't all there.
    private static func subsequenceSpan(_ needle: String, in haystack: String) -> Int? {
        let letters = Array(haystack)
        let wanted = Array(needle)
        var best: Int?
        for start in letters.indices where letters[start] == wanted[0] {
            var position = start
            var matched = 0
            while position < letters.count, matched < wanted.count {
                if letters[position] == wanted[matched] {
                    matched += 1
                }
                position += 1
            }
            guard matched == wanted.count else { break }
            let span = position - start
            if span < (best ?? Int.max) {
                best = span
            }
        }
        return best
    }
}
