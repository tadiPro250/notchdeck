import Foundation
import NaturalLanguage
#if canImport(Translation)
import Translation
#endif

/// Puts a song's lyrics into English, line for line, so each line keeps its timestamp.
///
/// macOS translates on the device (Translation, macOS 26 and later) when the song's language is
/// installed under System Settings → General → Language & Region → Translation Languages. A
/// language it can't translate (or an older macOS) is spelled in Latin letters instead, so a
/// Hindi or Telugu song still reads in English letters rather than in a script you may not read.
enum LyricsTranslator {
    /// `texts` in English. Lines already in English, and the "♪" instrumental marks, are kept as
    /// they are. Always returns exactly one string per input, in the same order.
    static func english(_ texts: [String]) async -> [String] {
        let sung = texts.filter { !isBlank($0) }
        guard let language = songLanguage(sung), language != .english else { return texts }

        // Which lines need it: a mostly-Hindi song with an English hook keeps the hook.
        let needs = texts.map { !isBlank($0) && !isEnglish($0) }
        let wanted = zip(texts, needs).filter(\.1).map(\.0)
        guard !wanted.isEmpty else { return texts }

        var translated = await translate(wanted, from: language)
        if translated == nil {
            // No translation for this language here: at least spell it in Latin letters.
            let romanized = wanted.map(romanize)
            translated = romanized == wanted ? nil : romanized
        }
        guard let translated, translated.count == wanted.count else { return texts }
        var next = translated.makeIterator()
        return zip(texts, needs).map { text, need in need ? (next.next() ?? text) : text }
    }

    /// The song's language, from all its lines together (one line is too short to tell).
    ///
    /// Lyrics in Latin letters that read neither as English nor clearly as another language are
    /// taken as romanised Hindi: LRCLIB writes most Hindi and Urdu songs that way ("Hum tere bin
    /// ab reh nahi sakte"), the recogniser can only guess at them, and macOS's Hindi model
    /// translates them well.
    static func songLanguage(_ lines: [String]) -> NLLanguage? {
        let text = lines.joined(separator: "\n")
        guard !text.isEmpty else { return nil }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let hypotheses = recognizer.languageHypotheses(withMaximum: 3)
        guard let (top, confidence) = hypotheses.max(by: { $0.value < $1.value }) else { return nil }
        // A script of its own (Devanagari, Hangul, Kana…) is certain enough.
        guard isLatin(text) else { return top }
        if (hypotheses[.english] ?? 0) >= 0.5 { return .english }
        if confidence >= 0.8 { return top }
        return .hindi
    }

    /// A line positively reads as English. Short interjections that don't ("oh", "na na") go
    /// to translation too, which hands them back unchanged.
    static func isEnglish(_ line: String) -> Bool {
        guard isLatin(line) else { return false }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(line)
        return (recognizer.languageHypotheses(withMaximum: 3)[.english] ?? 0) >= 0.5
    }

    private static func isBlank(_ line: String) -> Bool {
        line == "♪" || line.trimmingCharacters(in: .whitespaces).isEmpty
    }

    static func isLatin(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return true }
        let latin = letters.filter { $0.value < 0x250 || (0x1E00...0x1EFF).contains($0.value) }
        return Double(latin.count) / Double(letters.count) > 0.9
    }

    /// "तुम ही हो" -> "tuma hi ho". Diacritics are dropped so it reads as plain English letters.
    static func romanize(_ text: String) -> String {
        guard !isLatin(text) else { return text }
        let latin = text.applyingTransform(.toLatin, reverse: false) ?? text
        return latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
    }

    /// Nil when macOS can't translate `language` to English here, or the translation failed.
    private static func translate(_ lines: [String], from language: NLLanguage) async -> [String]? {
        #if canImport(Translation)
        if #available(macOS 26.0, *) {
            let source = Locale.Language(identifier: language.rawValue)
            let target = Locale.Language(identifier: "en")
            // Only a language already on the Mac: downloading one needs a prompt, and the lyrics
            // shouldn't wait on it. Romanised text stands in until it's installed.
            guard await LanguageAvailability().status(from: source, to: target) == .installed else { return nil }
            let session = TranslationSession(installedSource: source, target: target)
            let requests = lines.enumerated().map {
                TranslationSession.Request(sourceText: $0.element, clientIdentifier: String($0.offset))
            }
            guard let responses = try? await session.translations(from: requests) else { return nil }
            var out = lines
            for response in responses {
                guard let id = response.clientIdentifier, let i = Int(id), out.indices.contains(i) else { continue }
                out[i] = response.targetText
            }
            return out
        }
        #endif
        return nil
    }
}
