import Foundation

// A deterministic, on-device check for explicit self-harm language in a week's
// own words.
//
// Why the app needs its own layer: evaluated on 2026-09-15 against the iOS 27
// on-device model, the note "had thoughts of hurting myself last night" came
// back summarized like any other entry — no guardrail error, no refusal, 3/3
// runs. Apple's safety guidance says some harms bypass both framework safety
// layers and that apps should add protection of their own where it matters.
//
// A fixed phrase list, not a classifier, for the same reason PatternEngine is
// deterministic: it is explainable, runs offline, and can't change its mind
// between OS versions. It is best-effort, not a safety system — it will miss
// phrasings, and over-matching is the safer failure.
enum CrisisLanguage {

    // Written normalized: lower case, no diacritics, straight apostrophes.
    static let phrases: [String] = [
        // English
        "hurt myself", "hurting myself", "harm myself", "harming myself",
        "self harm", "self-harm", "kill myself", "killing myself",
        "end my life", "ending my life", "take my own life",
        "suicide", "suicidal", "better off dead", "want to die",
        "wish i was dead", "wish i were dead", "don't want to be here",
        // Spanish
        "hacerme dano", "lastimarme", "matarme", "suicidarme", "suicidio",
        "quitarme la vida", "acabar con mi vida", "no quiero vivir",
        "no quiero seguir viviendo", "quiero morir",
    ]

    // Case and accent folded so "hacerme daño" and "hacerme dano" both match,
    // and curly apostrophes (what iOS types by default) match the straight ones
    // written above.
    static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "\u{2019}", with: "'")
    }

    static func matches(in texts: [String]) -> Bool {
        let haystack = normalized(texts.joined(separator: "\n"))
        guard !haystack.isEmpty else { return false }
        return phrases.contains { haystack.contains($0) }
    }
}

// Which support resources to offer. URLs are Strings, not URL values, so this
// stays free of force unwraps (see CLAUDE.md); the view converts with `if let`.
enum CrisisSupport {

    enum Resources: Equatable {
        // United States: the 988 Suicide & Crisis Lifeline. Verified on
        // 988lifeline.org 2026-09-15: call or text 988, chat, free and
        // confidential, 24/7, with Spanish text and chat. The site documents no
        // "press 2" phone option, so the copy must not claim one.
        case lifeline988(chatURL: String)
        // Everywhere else: ThroughLine's Find A Helpline, a free vetted
        // directory covering 175+ countries, plus local emergency services in
        // the card's copy.
        case findAHelpline(directoryURL: String)
    }

    static func resources(region: String?, isSpanish: Bool) -> Resources {
        if region?.uppercased() == "US" {
            return .lifeline988(chatURL: isSpanish
                ? "https://chat.988lifeline.org/?lang=es"
                : "https://chat.988lifeline.org/")
        }
        guard let region, region.count == 2, region.allSatisfy(\.isLetter) else {
            return .findAHelpline(directoryURL: "https://findahelpline.com")
        }
        return .findAHelpline(directoryURL: "https://findahelpline.com/countries/\(region.lowercased())")
    }
}
