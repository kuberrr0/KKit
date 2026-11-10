import Foundation

/// Scores how well a typed query matches a title, from 0 to 1. Every search provider
/// uses it, so "ns" finds Night Shift and "sys set" finds System Settings the same way
/// everywhere.
///
/// Roughly: exact 1.0 › title starts with the query 0.9 › a word starts with it 0.8 ›
/// every query word starts a title word, in order 0.78 › in any order 0.76 › initials
/// ("ns") 0.75 › contains 0.65 › letters in order 0.3–0.6. Matches on keywords count
/// 85% of a title match.
///
/// Words are also compared in a loose form (`canonical`): British and American
/// spellings, plurals and endings like -er and -ing are folded together, so "color
/// picker", "pick color" and "colours" all find "Pick Colour". A loose match scores
/// 98% of the same match on the text as typed.
public enum FuzzyMatch {
    public static func score(_ query: String, in candidate: String) -> Double? {
        let needle = normalize(query)
        let haystack = normalize(candidate)
        guard !needle.isEmpty, !haystack.isEmpty else { return nil }
        let typed = strictScore(needle, in: haystack)
        let looseNeedle = canonical(needle)
        let looseHaystack = canonical(haystack)
        guard looseNeedle != needle || looseHaystack != haystack else { return typed }
        let loose = strictScore(looseNeedle, in: looseHaystack).map { $0 * 0.98 }
        switch (typed, loose) {
        case let (typed?, loose?): return max(typed, loose)
        case let (typed?, nil): return typed
        case let (nil, loose?): return loose
        case (nil, nil): return nil
        }
    }

    /// The best of the title and the keywords (keywords count a little less). A query of
    /// several words also matches when its words are spread over the title and the
    /// keywords ("hex picker" for Pick Colour with the keyword "hex"), as long as one
    /// of them is in the title.
    public static func score(_ query: String, title: String, keywords: [String] = []) -> Double? {
        var best = score(query, in: title)
        for keyword in keywords {
            guard let keywordScore = score(query, in: keyword) else { continue }
            let weighted = keywordScore * 0.85
            if weighted > (best ?? 0) {
                best = weighted
            }
        }
        if (best ?? 0) < spreadScore, spreadOverTitleAndKeywords(query, title: title, keywords: keywords) {
            best = spreadScore
        }
        return best
    }

    /// Lowercased, accents removed, runs of spaces collapsed.
    public static func normalize(_ text: String) -> String {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        return folded.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// `normalize`d text with every word in its loose form: "Favourite Colours" →
    /// "favorite color", "color picker" → "color pick".
    public static func canonical(_ text: String) -> String {
        normalize(text)
            .split(separator: " ")
            .map { canonicalWord(String($0)) }
            .joined(separator: " ")
    }

    // MARK: Private

    private static let spreadScore = 0.62

    private static func spreadOverTitleAndKeywords(_ query: String, title: String, keywords: [String]) -> Bool {
        let queryWords = words(of: canonical(query))
        guard queryWords.count > 1, !keywords.isEmpty else { return false }
        let titleWords = words(of: canonical(title))
        let allWords = titleWords + keywords.flatMap { words(of: canonical($0)) }
        let inTitle = queryWords.contains { word in titleWords.contains { $0.hasPrefix(word) } }
        let everywhere = queryWords.allSatisfy { word in allWords.contains { $0.hasPrefix(word) } }
        return inTitle && everywhere
    }

    /// Words spelt differently in British and American English, and a few synonyms.
    private static let variants: [String: String] = [
        "colour": "color", "colours": "color", "coloured": "colored",
        "favourite": "favorite", "favourites": "favorite",
        "grey": "gray", "greys": "gray",
        "labelled": "labeled", "labelling": "labeling",
        "cancelled": "canceled", "cancelling": "canceling",
        "travelled": "traveled", "modelling": "modeling",
        "programme": "program", "programmes": "program",
        "catalogue": "catalog", "dialogue": "dialog",
        "licence": "license", "defence": "defense", "offence": "offense",
        "judgement": "judgment", "aluminium": "aluminum", "maths": "math",
        "preferences": "settings", "preference": "settings", "prefs": "settings",
        "begin": "start", "launch": "open",
    ]

    /// One word's loose form: the American spelling, without a plural or an -er,
    /// -ing or -ed ending. Both sides of a comparison get the same treatment, so the
    /// stems only have to agree with each other.
    private static func canonicalWord(_ typed: String) -> String {
        guard typed.count >= 4, typed.allSatisfy(\.isLetter) else { return typed }
        var word = variants[typed] ?? typed
        // organise → organize, analyse → analyze.
        for (british, american) in [("isation", "ization"), ("ise", "ize"), ("ised", "ized"), ("ising", "izing"), ("yse", "yze"), ("ysed", "yzed")]
        where word.count > british.count + 2 && word.hasSuffix(british) {
            word = String(word.dropLast(british.count)) + american
            break
        }
        if word.hasSuffix("s"), !word.hasSuffix("ss"), word.count >= 4 {
            word.removeLast()
        }
        for ending in ["ing", "er", "ed"] where word.count >= ending.count + 3 && word.hasSuffix(ending) {
            word.removeLast(ending.count)
            break
        }
        // colour → color, centre → center.
        if word.count >= 5, word.hasSuffix("our") {
            word = String(word.dropLast(3)) + "or"
        } else if word.count >= 5, word.hasSuffix("tre") {
            word = String(word.dropLast(3)) + "ter"
        }
        return word
    }

    /// The tiers in the type's comment, on already normalized text.
    private static func strictScore(_ needle: String, in haystack: String) -> Double? {
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
        if queryWords.count > 1, queryWords.allSatisfy({ queryWord in words.contains { $0.hasPrefix(queryWord) } }) {
            return 0.76
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
