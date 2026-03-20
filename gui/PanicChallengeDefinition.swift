import SwiftUI

struct PanicChallengeDefinition: Identifiable {
    let id: String
    let displayName: String
    let iconName: String
    let shortDescription: String

    let makeChallengeView: (@escaping () async -> Bool) -> AnyView

    let makeSettingsView: ((BlissViewModel) -> AnyView)?

    let makeWizardConfigView: (() -> AnyView)?
}

enum PanicChallengeRegistry {
    static let all: [PanicChallengeDefinition] = [
        TypingChallenge.definition,
        CompetitiveChallenge.definition,
        MinesweeperChallenge.definition,
        PipesChallenge.definition,
        SudokuChallenge.definition,
        Game2048Challenge.definition,
        WordleChallenge.definition,
        SimonSaysChallenge.definition,
    ]

    static func find(_ key: String) -> PanicChallengeDefinition? {
        all.first { $0.id == key }
    }
}
