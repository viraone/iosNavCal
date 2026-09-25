import Foundation

/// Extracts a navigable destination from free text when an event has no `location`.
///
/// Strategy, in order:
/// 1. A postal address found by `NSDataDetector` (e.g. "123 Main St, Portland, OR").
/// 2. A "store name + store number" pattern common in merchandising and delivery
///    schedules (e.g. "Safeway 555", "Fred Meyer #658", "Reset - WinCo Foods 12").
enum LocationParser {
    /// Returns the best destination string found in `texts`, checked in order (e.g. title, then notes).
    static func destination(in texts: [String?]) -> String? {
        let candidates = texts.compactMap { $0 }.filter { !$0.isEmpty }
        for text in candidates {
            if let address = address(in: text) { return address }
        }
        for text in candidates {
            if let store = storeReference(in: text) { return store }
        }
        return nil
    }

    // MARK: - Addresses

    private static let addressDetector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.address.rawValue
    )

    static func address(in text: String) -> String? {
        guard let detector = addressDetector else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, range: range),
              let swiftRange = Range(match.range, in: text) else { return nil }
        return normalize(String(text[swiftRange]))
    }

    // MARK: - Store references

    /// One to four capitalized words, an optional "#" / "No." / "Store", then a 2–5 digit number
    /// that isn't part of a time ("10:30", "10 am").
    private static let storePattern = try! NSRegularExpression(pattern: #"""
        (?<![\w\x23])
        ((?:[A-Z][A-Za-z'&.\-]*\s+){0,3}[A-Z][A-Za-z'&.\-]*)   # name words
        \s*(?:\x23|No\.?|Store)?\s*
        (\d{2,5})                                               # store number
        (?![\d:])(?!\s*(?:am|pm|AM|PM)\b)\b
        """#, options: [.allowCommentsAndWhitespace])

    /// Leading words that describe the task rather than the place ("Reset Safeway 555").
    /// A match that is nothing but these ("Shift 12", "Route 66") is rejected.
    private static let taskWords: Set<String> = [
        "shift", "reset", "merch", "merchandising", "visit", "delivery", "deliver", "pickup", "pick",
        "drop", "dropoff", "route", "stop", "audit", "restock", "service", "order", "job", "gig", "task",
        "call", "meeting", "at", "to", "the", "store", "room", "gate", "suite", "unit", "apt", "floor",
        "zone", "batch", "block", "week", "day", "hours", "hour", "no", "q", "fy", "shop", "survey",
    ]

    private static let numberPrefixes: Set<String> = ["store", "no", "number", "num"]

    private static func key(_ word: Substring) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    static func storeReference(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        for match in storePattern.matches(in: text, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: text),
                  let numberRange = Range(match.range(at: 2), in: text) else { continue }

            var words = text[nameRange].split(whereSeparator: \.isWhitespace)
                .drop { taskWords.contains(key($0)) }
            // "Safeway Store 555" / "Safeway No 555" -> "Safeway 555"
            while let last = words.last, numberPrefixes.contains(key(last)) {
                words = words.dropLast()
            }
            let name = words.joined(separator: " ")
            guard !name.isEmpty else { continue }
            return "\(name) \(text[numberRange])"
        }
        return nil
    }

    // MARK: - Helpers

    /// Collapses multi-line calendar locations ("Safeway\n123 Main St") into a single line.
    static func normalize(_ raw: String) -> String {
        raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}
