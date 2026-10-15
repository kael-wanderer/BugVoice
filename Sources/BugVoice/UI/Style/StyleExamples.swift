import VoiceCore

enum StyleExamples {
    static func example(for style: Style) -> (said: String, written: String) {
        switch style {
        case .personal:
            ("um hey are you free tonight like around 7 for dinner", "Hey, are you free tonight around 7 for dinner?")
        case .work:
            ("so the deploy is friday no I mean thursday and uh can you check the API", "The deploy is Thursday. Can you check the API?")
        case .email:
            ("hi anna thanks for the update um I'll review it tomorrow best kael", "Hi Anna,\n\nThanks for the update. I'll review it tomorrow.\n\nBest,\nKael")
        case .document:
            ("first install the app second grant the mic third hold right option", "1. Install the app.\n2. Grant the microphone.\n3. Hold Right Option.")
        case .terminal:
            ("um git status", "git status")
        case .other:
            ("so I think we should uh ship it", "I think we should ship it.")
        }
    }
}
