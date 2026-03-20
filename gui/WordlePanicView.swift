import SwiftUI

enum WordleDifficulty: String, CaseIterable {
    case easy = "easy"
    case medium = "medium"
    case hard = "hard"

    var maxGuesses: Int {
        switch self {
        case .easy: return 6
        case .medium: return 5
        case .hard: return 4
        }
    }

    var displayName: String {
        switch self {
        case .easy: return "Easy (6)"
        case .medium: return "Medium (5)"
        case .hard: return "Hard (4)"
        }
    }
}

enum WordleChallenge {
    static let definition = PanicChallengeDefinition(
        id: "wordle",
        displayName: "Wordle",
        iconName: "character.textbox",
        shortDescription: "Guess the 5-letter word to unlock.",
        makeChallengeView: { onSuccess in
            AnyView(WordlePanicViewWrapper(onSuccess: onSuccess))
        },
        makeSettingsView: { vm in
            AnyView(WordleSettingsView(vm: vm))
        },
        makeWizardConfigView: {
            AnyView(WordleWizardConfigView())
        }
    )
}

struct WordlePanicViewWrapper: View {
    let onSuccess: () async -> Bool
    @EnvironmentObject var vm: BlissViewModel

    var body: some View {
        WordlePanicView(maxGuesses: vm.wordleDifficulty.maxGuesses, onUnlock: onSuccess)
    }
}

enum WordleLetter {
    case correct
    case misplaced
    case absent
    case empty
}

struct WordleGuessLetter {
    var character: Character = " "
    var state: WordleLetter = .empty
}

@MainActor
class WordleGame: ObservableObject {
    let maxGuesses: Int
    let wordLength = 5

    @Published var guesses: [[WordleGuessLetter]]
    @Published var currentRow = 0
    @Published var currentCol = 0
    @Published var won = false
    @Published var gameOver = false
    @Published var answer: String
    @Published var keyStates: [Character: WordleLetter] = [:]
    @Published var shakeRow = -1

    init(maxGuesses: Int = 6) {
        self.maxGuesses = maxGuesses
        let word = WordleWordList.answers.randomElement()!
        self.answer = word.uppercased()
        self.guesses = Array(
            repeating: Array(repeating: WordleGuessLetter(), count: 5),
            count: maxGuesses
        )
    }

    func typeLetter(_ ch: Character) {
        guard !gameOver, currentCol < wordLength else { return }
        guesses[currentRow][currentCol].character = ch
        currentCol += 1
    }

    func deleteLetter() {
        guard !gameOver, currentCol > 0 else { return }
        currentCol -= 1
        guesses[currentRow][currentCol].character = " "
        guesses[currentRow][currentCol].state = .empty
    }

    func submitGuess() {
        guard !gameOver, currentCol == wordLength else { return }

        let word = String(guesses[currentRow].map(\.character)).lowercased()
        guard WordleWordList.validGuesses.contains(word) || WordleWordList.answers.contains(word) else {
            shakeRow = currentRow
            BlissSounds.playError()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.shakeRow = -1
            }
            return
        }

        let answerChars = Array(answer)
        let guessChars = Array(word.uppercased())
        var remaining: [Character: Int] = [:]
        for ch in answerChars { remaining[ch, default: 0] += 1 }

        // First pass: mark correct
        for i in 0..<wordLength {
            if guessChars[i] == answerChars[i] {
                guesses[currentRow][i].state = .correct
                remaining[guessChars[i], default: 0] -= 1
            }
        }

        // Second pass: mark misplaced/absent
        for i in 0..<wordLength {
            guard guesses[currentRow][i].state != .correct else { continue }
            if remaining[guessChars[i], default: 0] > 0 {
                guesses[currentRow][i].state = .misplaced
                remaining[guessChars[i], default: 0] -= 1
            } else {
                guesses[currentRow][i].state = .absent
            }
        }

        // Update keyboard states
        for i in 0..<wordLength {
            let ch = guesses[currentRow][i].character
            let newState = guesses[currentRow][i].state
            let existing = keyStates[ch]
            if existing == nil || betterState(newState, than: existing!) {
                keyStates[ch] = newState
            }
        }

        if guesses[currentRow].allSatisfy({ $0.state == .correct }) {
            won = true
            gameOver = true
            BlissSounds.playSuccess()
        } else if currentRow == maxGuesses - 1 {
            gameOver = true
        } else {
            currentRow += 1
            currentCol = 0
        }
    }

    func reset() {
        let word = WordleWordList.answers.randomElement()!
        answer = word.uppercased()
        guesses = Array(
            repeating: Array(repeating: WordleGuessLetter(), count: 5),
            count: 6
        )
        currentRow = 0
        currentCol = 0
        won = false
        gameOver = false
        keyStates = [:]
        shakeRow = -1
    }

    private func betterState(_ new: WordleLetter, than old: WordleLetter) -> Bool {
        let rank: [WordleLetter: Int] = [.empty: 0, .absent: 1, .misplaced: 2, .correct: 3]
        return (rank[new] ?? 0) > (rank[old] ?? 0)
    }
}

struct WordlePanicView: View {
    var maxGuesses: Int = 6
    let onUnlock: () async -> Bool

    @StateObject private var game: WordleGame

    init(maxGuesses: Int = 6, onUnlock: @escaping () async -> Bool) {
        self.maxGuesses = maxGuesses
        self.onUnlock = onUnlock
        self._game = StateObject(wrappedValue: WordleGame(maxGuesses: maxGuesses))
    }
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool
    @State private var isSubmitting = false
    @State private var resultText = ""

    private static let correctColor = Color(red: 0.42, green: 0.67, blue: 0.35)
    private static let misplacedColor = Color(red: 0.71, green: 0.63, blue: 0.31)
    private static let absentColor = Color(red: 0.23, green: 0.24, blue: 0.25)
    private static let emptyColor = Color(red: 0.15, green: 0.16, blue: 0.17)
    private static let borderColor = Color(red: 0.33, green: 0.34, blue: 0.35)

    private let tileSize: CGFloat = 52
    private let tileSpacing: CGFloat = 5

    var body: some View {
        VStack(spacing: 12) {
            // Header + tile grid wrapped in focusable for physical keyboard
            VStack(spacing: 12) {
                HStack {
                    Text("Wordle")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    Text("Guess the 5-letter word")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(spacing: tileSpacing) {
                    ForEach(0..<game.maxGuesses, id: \.self) { row in
                        HStack(spacing: tileSpacing) {
                            ForEach(0..<game.wordLength, id: \.self) { col in
                                tileView(row: row, col: col)
                            }
                        }
                        .offset(x: game.shakeRow == row ? -6 : 0)
                        .animation(
                            game.shakeRow == row
                                ? .default.repeatCount(3, autoreverses: true).speed(6)
                                : .default,
                            value: game.shakeRow
                        )
                    }
                }
            }
            .focusable()
            .focused($isFocused)
            .onKeyPress { keyPress in
                handleKeyPress(keyPress)
            }

            // On-screen keyboard is OUTSIDE the focusable container
            keyboardView()

            HStack {
                if game.gameOver && !game.won {
                    Text("The word was \(game.answer)")
                        .foregroundColor(.red)
                    Spacer()
                    Button("Try Again") {
                        game.reset()
                        resultText = ""
                    }
                } else if isSubmitting {
                    ProgressView().controlSize(.small)
                    Text("Unlocking...")
                        .foregroundColor(.secondary)
                } else if !resultText.isEmpty {
                    Text(resultText)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Spacer()
            }
            .frame(height: 28)
        }
        .onAppear { isFocused = true }
        .onChange(of: game.won) {
            if game.won { submitUnlock() }
        }
    }

    @ViewBuilder
    private func tileView(row: Int, col: Int) -> some View {
        let letter = game.guesses[row][col]
        let bg: Color = switch letter.state {
        case .correct: Self.correctColor
        case .misplaced: Self.misplacedColor
        case .absent: Self.absentColor
        case .empty: Self.emptyColor
        }

        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(bg)
            RoundedRectangle(cornerRadius: 4)
                .stroke(
                    letter.state == .empty ? Self.borderColor : bg,
                    lineWidth: 2
                )
            if letter.character != " " {
                Text(String(letter.character))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .frame(width: tileSize, height: tileSize)
    }

    @ViewBuilder
    private func keyboardView() -> some View {
        let rows: [[String]] = [
            ["Q","W","E","R","T","Y","U","I","O","P"],
            ["A","S","D","F","G","H","J","K","L"],
            ["ENTER","Z","X","C","V","B","N","M","DEL"]
        ]

        VStack(spacing: 4) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        let isWide = key == "ENTER" || key == "DEL"
        let bg: Color = {
            if key.count == 1 {
                let ch = Character(key)
                if let state = game.keyStates[ch] {
                    return switch state {
                    case .correct: Self.correctColor
                    case .misplaced: Self.misplacedColor
                    case .absent: Self.absentColor
                    case .empty: Color(red: 0.50, green: 0.51, blue: 0.53)
                    }
                }
            }
            return Color(red: 0.50, green: 0.51, blue: 0.53)
        }()

        Text(key)
            .font(.system(size: isWide ? 11 : 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: isWide ? 56 : 32, height: 40)
            .background(bg)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
            .onTapGesture {
                if key == "ENTER" {
                    game.submitGuess()
                } else if key == "DEL" {
                    game.deleteLetter()
                } else {
                    game.typeLetter(Character(key))
                }
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
    }

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        let ch = keyPress.characters.uppercased()
        if keyPress.key == .return {
            game.submitGuess()
            return .handled
        } else if keyPress.key == .delete {
            game.deleteLetter()
            return .handled
        } else if ch.count == 1, ch.first!.isLetter {
            game.typeLetter(Character(ch))
            return .handled
        }
        return .ignored
    }

    private func submitUnlock() {
        isSubmitting = true
        Task {
            let ok = await onUnlock()
            isSubmitting = false
            if ok {
                dismiss()
            } else {
                resultText = "Command failed — try again."
            }
        }
    }
}

enum WordleWordList {
    static let answers: [String] = [
        "about","above","abuse","actor","acute","admit","adopt","adult","after","again",
        "agent","agree","ahead","alarm","album","alert","alien","align","alive","alley",
        "allow","alone","along","alter","among","angel","anger","angle","angry","anime",
        "ankle","annex","apart","apple","apply","arena","argue","arise","armor","array",
        "arrow","aside","asset","atlas","audio","audit","avoid","awake","award","aware",
        "bacon","badge","badly","baker","basic","basin","basis","batch","beach","beard",
        "beast","begun","being","below","bench","berry","bible","bingo","birth","black",
        "blade","blame","bland","blank","blast","blaze","bleed","blend","bless","blind",
        "blink","bliss","block","blood","bloom","blown","board","boast","bonus","booth",
        "bound","brain","brand","brave","bread","break","breed","brick","bride","brief",
        "bring","broad","broke","brook","brush","buddy","build","bunch","burst","buyer",
        "cabin","cable","camel","candy","cargo","carry","catch","cause","cedar","chain",
        "chair","chalk","champ","chaos","charm","chart","chase","cheap","check","cheek",
        "cheer","chess","chest","chief","child","chill","china","choir","chunk","civil",
        "claim","clash","class","clean","clear","clerk","click","cliff","climb","cling",
        "clock","clone","close","cloth","cloud","coach","coast","color","comet","comic",
        "coral","couch","could","count","court","cover","crack","craft","crane","crash",
        "crazy","cream","creek","creep","crime","crisp","cross","crowd","crown","cruel",
        "crush","cubic","curve","cycle","daily","dance","dealt","debug","decay","decoy",
        "decor","delay","delta","demon","dense","depot","depth","derby","detox","devil",
        "diary","dirty","disco","ditch","dodge","doing","donor","doubt","dough","draft",
        "drain","drake","drama","drank","drape","drawn","dream","dress","dried","drift",
        "drill","drink","drive","drone","drown","dryer","dying","eager","eagle","early",
        "earth","eight","elder","elect","elite","email","ember","empty","enemy","enjoy",
        "enter","entry","equal","equip","error","essay","event","every","exact","exile",
        "exist","extra","fable","facet","faith","false","fancy","fatal","fault","feast",
        "fence","fiber","field","fifth","fifty","fight","final","first","fixed","flame",
        "flash","flask","flesh","flick","fling","float","flock","flood","floor","flora",
        "flour","fluid","flute","focal","focus","force","forge","forth","forum","fossil",
        "found","frame","frank","fraud","fresh","front","frost","fruit","fully","funny",
        "ghost","giant","given","glass","gleam","globe","gloom","glory","gloss","glove",
        "going","grace","grade","grain","grand","grant","graph","grasp","grass","grave",
        "gravel","great","green","greet","grief","grill","grind","grip","gross","group",
        "grove","grown","guard","guess","guest","guide","guild","guilt","quest","quiet",
        "quite","quote","habit","happy","harsh","haste","haven","heart","heavy","hedge",
        "heist","hence","herbs","homer","honor","horse","hotel","house","human","humor",
        "ideal","image","imply","index","indie","anger","inner","input","inter","intro",
        "ivory","japan","jewel","joint","joker","judge","juice","juicy","knack","kneel",
        "knife","knock","known","label","labor","latch","layer","learn","lease","leave",
        "legal","lemon","level","light","limit","linen","liner","lofty","logic","loose",
        "lover","lower","loyal","lunar","lunch","magic","major","maker","manor","maple",
        "march","match","maybe","mayor","medal","media","mercy","merge","merit","metal",
        "meter","midst","might","miner","minor","minus","mirth","model","money","month",
        "moral","motel","motor","mount","mouse","mouth","movie","music",
    ]

    static let validGuesses: [String] = [
        "aapas","aarti","abaca","abacs","abaht","abaka","abamp","aband","abask","abaya",
        "abbas","abbed","abbes","abcee","abeam","abear","abeat","abeer","abele","abeng",
        "abers","abets","abeys","abies","abius","abjad","abjud","abled","ables","ablet",
        "ablow","abmho","abnet","abohm","aboil","aboma","aboon","abord","abore","aborn",
        "abram","abray","abrim","abrin","abris","absey","absit","abuna","abune","abura",
        "aburn","abuts","abuzz","abyes","abysm","abyss","acais","acara","accas","accha",
        "accoy","accra","acedy","acene","acers","aceta","achar","acher","achey","acidy",
        "acies","acing","acini","ackee","acker","acmic","acock","acoel","acold","acone",
        "acral","acred","acron","acros","acryl","actas","actin","acton","actus","acyls",
        "adats","adawn","adaws","adays","adbot","addas","addax","addin","addio","addra",
        "adead","adeem","adhan","adhoc","adits","adlib","adman","admen","admix","adnex",
        "adobo","adoon","adorb","adown","adoze","adrad","adraw","adred","adret","adrip",
        "adsum","aduki","adunc","adust","advew","advts","adyta","adyts","adzed","adzes",
        "aecia","aedes","aeger","aeons","aerie","aeros","aesir","aevum","afald","afanc",
        "afara","afars","afear","affix","affly","afion","afire","afizz","aflaj","aflap",
        "aflow","afoam","afret","afrit","afros","aftos","agals","agama","agami","agamy",
        "agape","agars","agasp","agast","agaty","agaze","agbas","agene","agers","aggag",
        "agger","aggie","aggri","aggro","aggry","aghas","agidi","agila","agile","agism",
        "agita","aglee","aglet","agley","agloo","aglus","agmas","agoge","agogo","agons",
        "agood","agora","agria","agrin","agros","agrum","agued","agues","aguey","aguna",
        "agush","aguti","aheap","ahent","ahigh","ahind","ahing","ahint","ahold","ahole",
        "ahull","ahuru","aidas","aider","aidoi","aidos","aiery","aigas","aight","ailed",
        "aimag","aimak","ainee","ainga","aioli","airer","airns","airth","airts","aitch",
        "aitus","aiver","aixes","aiyah","aiyee","aiyoh","aiyoo","aizle","ajies","ajiva",
        "ajuga","ajupa","ajwan","akara","akees","akela","akene","aking","akita","akkas",
        "akker","akoia","akoja","akoya","aksed","akses","alaap","alack","alala","alamo",
        "aland","alane","alang","alans","alant","alapa","alaps","alary","alata","alate",
        "alays","albas","albee","albid","alcea","alces","alcid","alcos","aldea","aldol",
        "aleak","aleck","alecs","aleem","alefs","aleft","aleph","alews","aleye","alfas",
        "algal","algas","algid","algin","algor","algos","algum","alick","alifs","alike",
        "alims","alios","alist","aliya","alkie","alkin","alkos","alkyd","alkyl","allan",
        "allee","allel","allen","aller","allin","allis","allod","allus","allyl","almah",
        "almas","almeh","almes","almud","almug","alods","aloed","aloes","aloft","aloha",
        "aloin","aloos","alose","alowe","altho","altos","alula","alums","alumy","alure",
        "alurk","alvar","alway","amahs","amain","amari","amaro","amate","amaut","amban",
        "ambit","ambos","ambry","ameba","ameer","amene","amens","ament","amias","amice",
        "amici","amide","amido","amids","amies","amiga","amigo","amins","amirs","amlas",
        "amman","ammas","ammon","ammos","amnia","amnic","amnio","amoks","amole","amore",
        "amort","amour","amove","amowt","amped","amply","ampul","amrit","amuck","amyls",
        "anana","anata","ancho","ancle","ancon","andic","andro","anear","anele","anent",
        "angas","anglo","anigh","anile","anils","anima","animi","anion","anker","ankhs",
        "ankus","anlas","annal","annan","annas","annat","annul","annum","annus","anoas",
        "anode","anole","anomy","ansae","ansas","antae","antar","antas","anted","antes",
        "antis","antra","antre","antsy","anura","anyon","apace","apage","apaid","apayd",
        "apays","apeak","apeek","apers","apert","apery","apgar","aphid","aphis","apian",
        "apiol","apish","apism","apode","apods","apols","apoop","aport","appal","appam",
        "appay","appel","appro","appts","appui","appuy","apres","apses","apsis","apsos",
        "apted","apter","aquae","aquas","araba","araks","arame","arars","arbah","arbas",
        "arced","archi","arcos","arcus","ardeb","ardri","aread","areae","areal","arear",
        "areca","aredd","arede","arefy","areic","arene","arepa","arere","arete","arets",
        "arett","argal","argan","argil","argle","argol","argon","argot","argus","arhat",
        "arias","ariel","ariki","arils","ariot","arish","arith","arked","arled","arles",
        "armed","armer","armet","armil","arnas","arnis","arnut","aroba","aroha","aroid",
        "arpas","arpen","arrah","arras","arret","arris","arroz","arsed","arses","arsey",
        "arsis","artal","artel","arter","artic","artis","artly","artsy","aruhe","arums",
        "arval","arvee","arvos","aryls","asada","asana","ascon","ascot","ascus","asdic",
        "ashed","ashet","asity","askar","asker","askew","askoi","askos","aspen","asper",
        "aspic","aspie","aspis","aspro","assai","assam","assay","assed","asses","assez",
        "assot","astir","astun","asura","asway","aswim","asyla","ataps","ataxy","atigi",
        "atilt","atimy","atman","atmas","atmos","atocs","atoke","atoks","atoms","atomy",
        "atony","atopy","atria","atrip","attap","attar","attas","atter","atuas","aucht",
        "audad","audax","augen","auger","auges","aught","aulas","aulic","auloi","aulos",
        "aumil","aunes","aunty","aurae","aural","aurar","auras","aurei","aures","auric",
        "auris","aurum","autos","auxin","avale","avant","avast","avels","avens","avers",
        "avgas","avine","avion","avise","aviso","avize","avows","avyze","awari","awarn",
        "awash","awato","awave","aways","awdls","aweel","aweto","awkin","awmry","awned",
        "awner","awoke","awols","awork","axels","axile","axils","axing","axiom","axite",
        "axled","axman","axmen","axoid","axone","axons","ayahs","ayaya","ayelp","aygre",
        "ayins","aymag","ayont","ayres","ayrie","azans","azide","azido","azine","azlon",
        "azoic","azole","azons","azote","azoth","azuki","azurn","azury","azygy","azyme",
        "azyms","baaed","baals","baaps","babas","babby","babes","babka","baboo","babul",
        "babus","bacca","bacco","baccy","bacha","bachs","backs","backy","bacne","badam",
        "baddy","baels","baffs","baffy","bafta","bafts","baghs","bagie","bagsy","bagua",
        "bahts","bahus","bahut","baiks","baile","bails","bairn","baisa","baith","baits",
        "baiza","baize","bajan","bajra","bajri","bajus","baked","baken","bakes","bakra",
        "balas","balds","baldy","baled","baler","bales","balks","balky","ballo","bally",
        "baloi","balon","baloo","balot","balsa","balti","balun","balus","balut","bamas",
        "bambi","bamma","bammy","banak","banal","banco","bancs","banda","bandh","bandy",
        "baned","banes","bania","banky","banns","bants","bantu","banty","bantz","banya",
        "baons","baozi","bappu","bapus","barbe","barbs","barby","barca","barde","bardo",
        "bards","bardy","bared","barer","bares","barfi","barfs","barfy","barge","baric",
        "barks","barky","barms","barmy","barns","barny","barps","barra","barre","barro",
        "barry","barye","basal","basan","basas","basen","baser","basha","basho","basij",
        "basks","bason","basse","bassi","basso","bassy","basta","baste","basti","basto",
        "basts","bates","baths","batik","batos","batta","batts","battu","batty","bauds",
        "bauks","baulk","baurs","bavin","bawds","bawdy","bawks","bawls","bawns","bawrs",
        "bawty","bayas","bayed","bayer","bayes","bayle","bayts","bazar","bazas","bazoo",
        "bball","bdays","beaky","beals","beamy","beano","beany","beare","beath","beaty",
        "beaus","beaut","beaux","bebop","becap","becke","becks","bedad","bedel","bedes",
        "bedew","bedim","bedye","beedi","beery","befit","befog","begad","begar","begat",
        "begem","beget","begob","begot","begum","beige","beigy","beins","beira","beisa",
        "bekah","belah","belar","belch","belee","belga","belie","belit","belle","belli",
        "bello","belon","belve","bemad","bemas","bemix","bemud","bendy","benes","benet",
        "benga","benis","benji","benne","benni","benny","bento","bents","benty","bepat",
        "beray","beres","beret","bergs","berko","berks","berme","berms","berob","beryl",
        "besat","besaw","besee","beses","beset","besit","besom","besot","besti","bests",
        "betas","beted","betel","betes","beths","betid","beton","betta","betty","bevan",
        "bevel","bever","bevor","bevue","bevvy","bewdy","bewet","bewig","bezel","bezes",
        "bezil","bezzy","bhais","bhaji","bhang","bhats","bhava","bhels","bhoot","bhuna",
        "bhuts","biach","biali","bialy","bibbs","bibes","bibis","biccy","bices","bicky",
        "biddy","bided","bider","bides","bidet","bidis","bidon","bidri","bield","biers",
        "biffo","biffs","biffy","bifid","bigae","biggs","biggy","bigha","bight","bigly",
        "bigos","bigot","bihon","bijou","biked","biker","bikie","bikky","bilal","bilat",
        "bilbo","bilby","biled","biles","bilge","bilgy","bilks","billy","bimah","bimas",
        "bimbo","binal","bindi","binds","biner","bines","binge","bings","bingy","binit",
        "binks","binky","bints","biogs","bions","biont","biose","biota","biped","bipod",
        "bippy","birdo","biris","birks","birle","birls","biros","birrs","birse","birsy",
        "birze","birzz","bises","bisks","bisom","bitch","biter","bites","bitey","bitos",
        "bitou","bitsy","bitte","bitts","bitty","bivia","bivvy","bizes","bizzo","bizzy",
        "blabs","blads","blady","blaer","blaes","blaff","blags","blahs","blain","blams",
        "blanc","blart","blase","blash","blate","blats","blatt","blaud","blawn","blaws",
        "blays","bleah","blear","blebs","blech","bleep","blees","blent","blert","blest",
        "blets","bleys","blimy","bling","blini","blins","bliny","blips","blist","blite",
        "blits","blive","blobs","blocs","blogs","blonx","blook","bloop","blore","blots",
        "blowy","blubs","blude","bluds","bludy","blued","bluer","bluet","bluey","bluid",
        "blume","blunk","blype","boabs","boaks","boars","boart","boaty","bobac","bobak",
        "bobas","bobby","bobol","bobos","bocca","bocce","bocci","boche","bocks","boded",
        "bodes","bodge","bodgy","bodhi","bodle","bodoh","boeps","boers","boeti","boets",
        "boeuf","boffo","boffs","bogan","boggy","bogie","bogle","bogue","bohea","bohos",
        "boils","boing","boink","boite","boked","bokeh","bokes","bokos","bolar","bolas",
        "boldo","bolds","boles","bolet","bolix","bolks","bolls","bolos","bolus","bomas",
        "bombe","bombo","bomoh","bomor","bonce","boned","boner","boney","bongo","bongs",
        "bonie","bonks","bonne","bonny","bonum","bonza","bonze","booai","booay","boobs",
        "booby","boody","booed","boofy","boogy","boohs","booky","bools","booms","boomy",
        "boong","boons","boord","boors","boose","booty","booze","boozy","boppy","borak",
        "boral","boras","borde","bords","boree","borek","borel","borer","bores","borgo",
        "boric","borks","borms","borna","boron","borts","borty","bortz","bosey","bosie",
        "bosks","bosky","boson","bossa","bosun","botas","boteh","botel","botes","botew",
        "bothy","botos","botte","botts","botty","bouge","bough","bouks","boule","boult",
        "bouns","bourd","bourg","bourn","bouse","bousy","bouts","boutu","bovid","bowat",
        "bower","bowes","bowet","bowie","bowls","bowne","bowrs","bowse","boxed","boxen",
        "boxes","boxla","boxty","boyar","boyau","boyed","boyey","boyfs","boygs","boyla",
        "boyly","boyos","boysy","bozos","braai","brach","brack","bract","brads","braes",
        "brags","brahs","brail","braks","braky","brame","brane","brank","brans","brant",
        "brast","brats","brava","bravi","braws","braxy","brays","braza","braze","bream",
        "brede","breds","breem","breer","brees","breid","breis","breme","brens","brent",
        "brere","brers","breve","brews","breys","briar","bribe","brier","bries","brigs",
        "briki","briks","brill","brims","brins","brios","brise","briss","brith","brits",
        "britt","brize","broch","brock","brods","brogh","brogs","brome","bromo","bronc",
        "brond","brool","broos","brose","brosy","brows","bruck","brugh","bruhs","bruin",
        "bruit","bruja","brujo","brule","brume","brung","brusk","brust","brute","bruts",
        "bruvs","buats","buaze","bubal","bubas","bubba","bubbe","bubby","bubus","buchu",
        "bucko","bucks","bucku","budas","buded","budes","budis","budos","buena","buffa",
        "buffe","buffi","buffo","buffs","buffy","bufos","bufty","bugan","bugle","buhls",
        "buhrs","buiks","buist","bukes","bukos","bulbs","bulgy","bulks","bulla","bulls",
        "bulse","bumbo","bumfs","bumph","bumps","bumpy","bunas","bunce","bunco","bunde",
        "bundh","bunds","bundt","bundu","bundy","bungs","bungy","bunia","bunje","bunjy",
        "bunko","bunks","bunns","bunts","bunty","bunya","buoys","buppy","buran","buras",
        "burbs","burds","buret","burfi","burgh","burgs","burin","burka","burke","burks",
        "burls","burly","burns","burnt","buroo","burps","burqa","burra","burro","burrs",
        "burry","bursa","burse","busby","bused","busks","busky","bussu","busti","busts",
        "busty","butch","buteo","butes","butle","butoh","butte","butts","butty","butut",
        "butyl","buxom","buyin","buzzy","bwana","bwazi","byded","bydes","byked","bykes",
        "byres","byrls","byssi","byway","caaed","cabas","cabby","caber","cabob","caboc",
        "cabre","cacao","cacas","cache","cacks","cacky","cacti","caddy","cadee","cades",
        "cadge","cadgy","cadie","cadis","cadre","caeca","caese","cafes","caffe","caffs",
        "caged","cager","cages","cagey","cagot","cahow","caids","cains","caird","cairn",
        "cajon","cajun","caked","cakes","cakey","calfs","calid","calif","calix","calks",
        "calla","calle","calls","calms","calmy","calos","calpa","calps","calve","calyx",
        "caman","camas","cames","camis","camos","campi","campo","camps","campy","camus",
        "canal","cando","caneh","caner","canes","cangs","canid","canna","canns","canny",
        "canon","canso","canst","canti","canto","cants","canty","capas","capax","caped",
        "capes","capex","caphs","capiz","caple","capon","capos","capot","capri","capul",
        "caput","carap","carat","carbo","carbs","carby","cardi","cardy","cared","carer",
        "cares","caret","carex","carks","carle","carls","carne","carns","carny","carob",
        "carol","carom","caron","carpe","carpi","carps","carrs","carse","carta","carte",
        "carts","carvy","casas","casco","cased","caser","cases","casks","casky","caste",
        "casts","casus","cates","catty","cauda","cauks","cauld","caulk","cauls","caums",
        "caups","cauri","causa","cavas","caved","cavel","caver","caves","cavie","cavil",
        "cavus","cawed","cawks","caxon","ceaze","cebid","cecal","cecum","ceded","ceder",
        "cedes","cedis","ceiba","ceili","ceils","celeb","cella","celli","cello","cells",
        "celly","celom","celts","cense","cento","cents","centu","ceorl","cepes","cerci",
        "cered","ceres","cerge","ceria","ceric","cerne","ceroc","ceros","certs","certy",
        "cesse","cesta","cesti","cetes","cetyl","cezve","chaap","chaat","chace","chack",
        "chaco","chado","chads","chafe","chaff","chaft","chais","chals","chams","chana",
        "chang","chank","chape","chaps","chapt","chara","chard","chare","chark","charr",
        "chars","chary","chasm","chats","chava","chave","chavs","chawk","chawl","chaws",
        "chaya","chays","cheba","chedi","cheeb","cheep","cheet","chefs","cheka","chela",
        "chelp","chemo","chems","chere","chert","cheth","chevy","chews","chewy","chiao",
        "chias","chiba","chibs","chica","chich","chico","chics","chide","chiel","chiko",
        "chiks","chile","chimb","chimo","chimp","chine","ching","chink","chino","chins",
        "chirk","chirl","chirm","chiro","chirp","chirr","chirt","chiru","chiti","chits",
        "chiva","chive","chivs","chivy","chizz","chock","choco","chocs","chode","chogs",
        "choil","choke","choko","choky","chola","choli","cholo","chomp","chons","choof",
        "chook","choom","choon","chops","choss","chota","chott","chout","choux","chowk",
        "chows","chubs","chuck","chufa","chuff","chugs","chump","chums","churl","churr",
        "chuse","chute","chuts","chyle","chyme","chynd","cibol","cided","cides","ciels",
        "ciggy","cilia","cills","cimar","cimex","cinct","cines","cinqs","cions","cippi",
        "circa","circs","cires","cirls","cirri","cisco","cissy","cists","cital","cited",
        "citee","citer","cites","cives","civet","civic","civie","civvy","clach","clack",
        "clade","clads","claes","clags","clair","clame","clans","claps","clapt","claro",
        "clart","clary","clast","clats","claut","clave","clavi","clays","cleat","cleck",
        "cleek","cleep","clefs","cleft","clegs","cleik","clems","clepe","clept","cleve",
        "clews","clied","clies","clift","clime","cline","clink","clint","clipe","clipt",
        "clits","cloam","clods","cloff","clogs","cloke","clomb","clomp","clonk","clons",
        "cloop","cloot","clops","clote","clots","clour","clous","clove","clows","cloye",
        "cloys","cloze","cluey","clunk","clype","cnida","coact","coady","coala","coals",
        "coaly","coapt","coarb","coate","coati","cobbs","cobby","cobia","coble","cobot",
        "cobra","cobza","cocas","cocci","cocco","cocks","cocky","cocos","cocus","codas",
        "codec","coden","coder","codex","codon","coeds","coffs","cogie","cogon","cogue",
        "cohab","cohen","cohoe","cohog","cohos","coifs","coign","coirs","coits","coked",
        "cokes","cokey","colas","colby","colds","coled","coles","coley","colic","colin",
        "colle","colls","colly","colog","colts","colza","comae","comal","comas","combe",
        "combi","combo","combs","comby","comer","comes","comfy","comix","comme","commo",
        "comms","commy","compo","comps","compt","comte","comus","condo","coned","cones",
        "conex","coney","confs","conga","conge","congo","conia","conic","conin","conks",
        "conky","conne","conns","conte","conto","conus","convo","cooch","cooed","cooee",
        "cooer","cooey","coofs","cooks","cooky","cools","cooly","coomb","cooms","coomy",
        "coons","coops","coopt","coost","coots","cooty","cooze","copal","copay","coped",
        "copen","coper","copes","copha","coppy","copra","copse","copsy","coqui","coram",
        "corbe","corby","corda","cored","corer","corey","coria","corks","corky","corms",
        "corni","corno","corns","cornu","corny","corps","corse","corso","cosec","cosed",
        "coses","coset","cosey","cosie","costa","coste","costs","cotan","cotch","coted",
        "cotes","coths","cotta","cotts","coude","cough","coups","courb","courd","coure",
        "cours","couta","couth","coved","coven","coves","covey","covin","cowal","cowan",
        "cowed","cower","cowks","cowls","cowps","cowry","coxae","coxal","coxed","coxes",
        "coxib","coyau","coyed","coyer","coyly","coypu","cozed","cozen","cozes","cozey",
        "cozie","craal","crabs","crags","craic","craig","crake","crame","crams","crans",
        "crape","craps","crapy","crare","crass","craws","crays","credo","creds","creed",
        "creel","crees","crein","crema","creme","crems","crena","crepe","creps","crept",
        "crepy","cress","crewe","crias","cribo","cribs","crick","crier","cries","crimp",
        "crims","crine","crink","crins","crios","cripe","crips","crise","criss","crith",
        "crits","croci","crocs","croft","crogs","cromb","crome","crone","cronk","crons",
        "crony","crook","crool","croon","crops","crore","crost","croup","crout","crowl",
        "crows","croze","cruck","crudo","cruds","crudy","crues","cruet","cruft","crumb",
        "crump","crunk","cruor","crura","cruse","crusy","cruve","crwth","cryer","cryne",
        "crypt","ctene","cubby","cubeb","cubed","cuber","cubes","cubit","cucks","cudda",
        "cuddy","cueca","cuffo","cuffs","cuifs","cuing","cuish","cuits","cukes","culch",
        "culet","culex","culls","cully","culms","culpa","culti","cults","culty","cumec",
        "cumin","cundy","cunei","cunit","cunny","cunts","cupel","cuppa","cuppy","cupro",
        "curat","curbs","curch","curdy","curer","cures","curet","curfs","curia","curie",
        "curio","curli","curls","curns","curny","currs","cursi","curst","curvy","cusec",
        "cushy","cusks","cusps","cuspy","cusso","cusum","cutch","cuter","cutes","cutey",
        "cutie","cutin","cutis","cutto","cutty","cutup","cuvee","cuzes","cwtch","cyano",
        "cyans","cyber","cycad","cycas","cyclo","cyder","cylix","cymae","cymar","cymas",
        "cymes","cymol","cysts","cytes","cyton","czars","daals","dabba","daces","dacha",
        "dacks","dadah","dadas","dadis","dadla","dados","daffs","daffy","dagga","daggy",
        "dagos","dahis","dahls","daiko","daine","daint","daisy","daker","daled","dalek",
        "dales","dalis","dalle","dally","dalts","daman","damar","dames","damme","damna",
        "damns","damps","dampy","dancy","danda","dandy","dangs","danio","danks","danny",
        "danse","dants","dappy","daraf","darbs","darcy","dared","darer","dares","darga",
        "dargs","daric","daris","darks","darky","darls","darns","darre","darzi","dashi",
        "dashy","datal","dater","datil","datos","datto","daube","daubs","dauby","dauds",
        "dault","daurs","dauts","daven","davit","dawah","dawds","dawed","dawen","dawgs",
        "dawks","dawns","dawts","dayal","dayan","daych","daynt","dazed","dazer","dazes",
        "dbags","deads","deair","deals","deans","deare","dearn","dears","deary","deash",
        "deave","deaws","deawy","debag","debar","debby","debel","debes","debts","debud",
        "debur","debus","debye","decad","decaf","decan","decim","decko","decos","decyl",
        "dedal","deedy","deely","deems","deens","deeps","deere","deers","deets","deeve",
        "deevs","defat","defer","deffo","defis","defog","degas","degum","degus","deice",
        "deids","deify","deign","deils","deink","deism","deist","deked","dekes","dekko",
        "deled","deles","delfs","delft","delis","della","dells","delly","delos","delph",
        "delts","deman","demes","demic","demit","demob","demoi","demos","demot","dempt",
        "denar","denay","dench","denes","denet","denis","dente","dents","deoch","deoxy",
        "derat","deray","dered","deres","derig","derma","derms","derns","derny","deros",
        "derpy","derro","derry","derth","dervs","desex","deshi","desis","desse","detag",
        "deter","devas","devel","devis","devon","devos","devot","dewan","dewar","dewax",
        "dewed","dexes","dexie","dexys","dhaba","dhaks","dhals","dhikr","dhobi","dhole",
        "dholl","dhols","dhoni","dhoti","dhows","dhuti","diact","dials","diana","diane",
        "diazo","dibbs","diced","dicer","dices","dicht","dicks","dicky","dicot","dicta",
        "dicto","dicts","dictu","dicty","diddy","didie","didis","didos","didst","diebs",
        "diels","diene","diets","diffs","dight","dikas","diked","diker","dikes","dikey",
        "dildo","dilli","dills","dilly","dimbo","dimer","dimes","dimps","dinar","dined",
        "dines","dinge","dingo","dings","dinic","dinks","dinky","dinlo","dinna","dinos",
        "dints","dioch","diode","diols","diota","dippy","dipso","diram","direr","dirge",
        "dirke","dirks","dirls","dirts","disas","disci","discs","dishy","disks","disme",
        "dital","ditas","dited","dites","ditsy","ditts","ditzy","divan","divas","dived",
        "dives","divey","divis","divna","divos","divot","divvy","diwan","dixie","dixit",
        "diyas","dizen","djinn","djins","doabs","doats","dobby","dobes","dobie","dobla",
        "doble","dobra","dobro","docht","docks","docos","docus","doddy","dodos","doeks",
        "doers","doest","doeth","doffs","dogal","dogan","doges","dogey","doggo","doggy",
        "dogie","dogly","dogma","dohyo","doilt","doily","doits","dojos","dolce","dolci",
        "doled","dolee","doles","doley","dolia","dolie","dolly","dolma","dolor","dolos",
        "dolts","domal","domed","domes","domic","donah","donas","donee","doner","donga",
        "dongs","donko","donna","donne","donny","donsy","doobs","dooce","doody","doofs",
        "dooks","dooky","doole","dools","dooly","dooms","doomy","doona","doorn","doors",
        "doozy","dopas","doped","doper","dopes","dopey","doppe","dorad","dorba","dorbs",
        "doree","dores","doric","doris","dorje","dorks","dorky","dorms","dormy","dorps",
        "dorrs","dorsa","dorse","dorts","dorty","dosai","dosas","dosed","doseh","doser",
        "doses","dosha","dotal","doted","doter","dotes","dotty","douar","douce","doucs",
        "douks","doula","douma","doums","doups","doura","douse","douts","doved","doven",
        "dover","doves","dovie","dowak","dowar","dowds","dowdy","dowed","dowel","dower",
        "dowfs","dowie","dowle","dowls","dowly","downa","downy","dowps","dowry","dowse",
        "dowts","doxed","doxes","doxie","doyen","doyly","dozed","dozer","dozes","drabs",
        "drack","draco","draff","drags","drail","drams","drant","draps","drapy","drats",
        "drave","drawl","drays","drear","dreck","dreed","dreer","drees","dregs","dreks",
        "drent","drere","drest","dreys","dribs","drice","drier","dries","drily","dript",
        "drock","droid","droil","droke","drole","droll","drome","drony","droob","droog",
        "drook","dropt","drouk","drows","drubs","druid","drupe","druse","drusy","druxy",
        "dryad","dryas","dsobo","dsomo","duads","duals","duans","duars","dubbo","dubby",
        "ducat","duces","duchy","ducky","ducti","ducts","duddy","duded","duels","duets",
        "duett","duffs","dufus","duing","duits","dukas","duked","dukes","dukka","dukun",
        "dulce","dules","dulia","dully","dulse","dumas","dumbo","dumbs","dumka","dumky",
        "dumpy","dunam","dunch","dungs","dungy","dunno","dunny","dunsh","dunts","duomi",
        "duomo","duper","dupes","duple","duply","duppy","dural","duras","dured","dures",
        "durgy","durns","duroc","duros","duroy","durra","durrs","durry","durst","durum",
        "durzi","dusks","dusky","dusts","duvet","duxes","dwaal","dwale","dwalm","dwams",
        "dwamy","dwang","dwaum","dweeb","dwelt","dwile","dwine","dyads","dyers","dyked",
        "dykes","dykey","dykon","dynel","dynes","dynos","dzhos","eagly","eagre","ealed",
        "eales","eaned","eards","eared","earls","earns","earnt","earst","easer","eases",
        "easle","easts","eathe","eatin","eaved","eaver","eaves","ebank","ebbet","ebena",
        "ebene","ebike","ebons","ebook","ecads","ecard","ecash","eched","eches","echos",
        "ecigs","eclat","ecole","ecrus","edema","edger","edify","edile","edits","educe",
        "educt","eejit","eensy","eerie","eeven","eever","eevns","effed","effer","efits",
        "egads","egers","egest","eggar","egged","egger","egmas","egret","ehing","eider",
        "eidos","eigne","eiked","eikon","eilds","eiron","eisel","eject","ejido","ekdam",
        "eking","ekkas","elain","eland","elans","elate","elchi","eldin","eleet","elegy",
        "elemi","elfed","eliad","elide","elint","elmen","eloge","elogy","eloin","elops",
        "elpee","elsin","elute","elvan","elven","elver","elves","emacs","embar","embay",
        "embed","embog","embow","embox","embus","emeer","emend","emerg","emery","emeus",
        "emics","emirs","emits","emmas","emmer","emmet","emmew","emmys","emong","emote",
        "emove","empts","emule","emure","emyde","emyds","enact","enarm","enate","ender",
        "endew","endow","endue","enema","enews","enfix","eniac","enlit","enmew","ennog",
        "enoki","enols","enorm","enows","enrol","ensew","ensky","ensue","entia","entre",
        "enure","enurn","envoi","enzym","eolid","eorls","eosin","epact","epees","epena",
        "epene","ephah","ephas","ephod","ephor","epics","epode","epopt","epoxy","eppie",
        "epris","eques","equid","erbia","erect","erevs","ergon","ergos","ergot","erhus",
        "erica","erick","erics","ering","erned","ernes","erose","erred","erses","eruct",
        "erugo","erupt","eruvs","erven","ervil","escar","escot","esile","eskar","esker",
        "esnes","esrog","esses","ester","estoc","estop","estro","etage","etape","etats",
        "etens","ethal","ethne","ethos","ethyl","etics","etnas","etrog","ettin","ettle",
        "etude","etuis","etwee","etyma","eughs","euked","eupad","euros","eusol","evegs",
        "evens","evert","evets","evhoe","evils","evite","evohe","evoke","ewers","ewest",
        "ewhow","ewked","exeat","execs","exeem","exeme","exfil","exier","exies","exine",
        "exing","exite","exits","exode","exome","exons","expel","expos","exuls","exurb",
        "eyass","eyers","eying","eyots","eyras","eyres","eyrie","eyrir","ezine","fabbo",
        "fabby","facer","faces","facey","facia","facie","facta","facty","faddy","fader",
        "fades","fadge","fados","faena","faery","faffs","faffy","faggy","fagin","fagot",
        "faiks","faine","fains","faire","fairs","faked","faker","fakes","fakey","fakie",
        "fakir","falaj","fales","falsy","fames","fanal","fands","fanes","fanga","fango",
        "fanks","fanny","fanon","fanos","fanum","faqir","farad","farci","farcy","fards",
        "fared","farer","fares","farle","farls","farms","faros","farro","farse","farts",
        "fasci","fasti","fasts","fated","fates","fatly","fatso","fatwa","fauch","faugh",
        "fauld","fauns","faurd","faute","fauts","fauve","favas","favel","faver","faves",
        "favus","fawns","fawny","faxed","faxes","fayed","fayer","fayne","fayre","fazed",
        "fazes","feals","feard","feare","fears","feart","fease","feaze","fecal","feces",
        "fecht","fecit","fecks","fedai","fedex","feebs","feels","feely","feens","feers",
        "feese","feeze","fehme","feist","felch","felid","felix","fells","felly","felts",
        "felty","femal","femes","femic","femme","femmy","fends","fendy","fenis","fenks",
        "fenny","fents","feods","feoff","feral","ferer","feres","feria","ferly","fermi",
        "ferms","ferns","ferny","ferox","fesse","festa","fests","festy","fetal","fetas",
        "feted","fetes","fetid","fetor","fetta","fetts","fetus","fetwa","feuar","feuds",
        "feued","feyed","feyer","feyly","fezes","fezzy","fiars","fiats","fibro","fices",
        "fiche","fichu","ficin","ficos","ficta","ficus","fides","fidge","fidos","fidus",
        "fiefs","fient","fiere","fieri","fiers","fiery","fiest","fifed","fifer","fifes",
        "fifis","figgy","figos","fiked","fikes","filar","filer","files","filet","filii",
        "filks","fille","fillo","filly","filmi","filmy","filon","filos","filum","finca",
        "fined","fines","finis","finks","finny","finos","fiord","fiqhs","fique","firer",
        "firie","firks","firma","firni","firns","firry","firth","fiscs","fisho","fisks",
        "fists","fisty","fitch","fitly","fitna","fitte","fitts","fiver","fives","fixes",
        "fixie","fixit","fjeld","fjord","flabs","flack","flaff","flail","flaks","flamm",
        "flams","flamy","flane","flans","flary","flava","flawn","flawy","flaxy","flays",
        "fleam","fleas","fleck","fleek","fleer","flees","fleet","flegs","fleme","fleur",
        "flews","flexi","flexo","fleys","flics","flied","flimp","flims","flirs","flirt",
        "flisk","flite","flits","flitt","flobs","flocs","floes","flogs","flong","flops",
        "flore","flors","flory","flosh","flota","flote","flout","flown","flowy","flubs",
        "flued","flues","fluey","fluky","flume","flump","fluor","flurr","fluty","fluyt",
        "flyby","flyer","flyin","flype","flyte","fnarr","foals","foams","foamy","foehn",
        "fogey","fogie","fogle","fogos","fogou","fohns","foids","foins","foist","folds",
        "foley","folia","folic","folie","folio","folky","fomes","fonda","fonds","fondu",
        "fones","fonio","fonly","foods","foody","fools","foots","footy","foram","foray",
        "forbs","forby","fordo","fords","forel","fores","forex","forgo","forks","forky",
        "forma","forme","forts","forza","forze","fossa","fosse","fouat","fouds","fouer",
        "fouet","foule","fouls","fount","fours","fouth","fovea","fowls","fowth","foxed",
        "foxie","foyle","foyne","frabs","frack","fract","frags","fraim","frais","franc",
        "frape","fraps","frass","frate","frati","frats","fraus","freak","freer","frees",
        "freet","freit","fremd","frena","freon","frere","frets","fribs","frier","fries",
        "frigs","frise","frist","frita","frite","frith","frits","fritt","frize","frizz",
        "frock","froes","frogs","fromm","frond","frons","froom","frore","frorn","frory",
        "frosh","froth","frown","frows","frowy","froyo","frugs","frump","frush","frust",
        "fryer","fubar","fubby","fubsy","fucks","fucus","fuddy","fudge","fudgy","fuero",
        "fuffs","fuffy","fugal","fuggy","fugie","fugio","fugis","fugle","fugly","fugue",
        "fugus","fujis","fulla","fulls","fulth","fulwa","fumed","fumer","fumes","fumet",
        "funda","fundi","fundo","fundy","fungo","fungs","funic","funis","funks","funsy",
        "funts","fural","furan","furca","furls","furol","furor","furos","furrs","furth",
        "furze","furzy","fusee","fusel","fuses","fusil","fusks","fusts","fusty","futon",
        "fuzed","fuzee","fuzes","fuzil","fyces","fyked","fykes","fyles","fyrds","fytte",
        "gabba","gabby","gable","gaddi","gades","gadge","gadgy","gadid","gadis","gadje",
        "gadjo","gadso","gaffe","gaffs","gaged","gager","gages","gaids","gaily","gairs",
        "gaita","gaits","gaitt","gajos","galah","galax","galea","galed","galia","galis",
        "galls","gally","galop","galut","galvo","gamas","gamay","gamba","gambe","gambo",
        "gambs","gamed","gamer","gamey","gamic","gamin","gamme","gammy","gamps","gamut",
        "ganch","gandy","ganef","ganev","ganja","ganks","ganof","gants","gaols","gaped",
        "gaper","gapes","gapos","gappy","garam","garba","garbe","garbo","garbs","garda",
        "garde","gares","garis","garms","garni","garre","garri","garth","garum","gashy",
        "gasps","gaspy","gassy","gasts","gatch","gated","gater","gates","gaths","gator",
        "gauch","gaucy","gauds","gaudy","gauje","gault","gaums","gaumy","gaups","gaurs",
        "gauss","gauzy","gavel","gavot","gawcy","gawds","gawks","gawky","gawps","gawsy",
        "gayal","gayer","gayly","gazal","gazar","gazed","gazes","gazon","gazoo","geals",
        "geans","geare","geasa","geats","gebur","gecko","gecks","geeks","geeky","geeps",
        "geese","geest","geist","geits","gelds","gelee","gelid","gelly","gelts","gemel",
        "gemma","gemmy","gemot","genae","genal","genas","genet","genic","genii","genin",
        "genio","genip","genny","genoa","genom","genro","gents","genty","genua","geode",
        "geoid","gerah","gerbe","geres","gerle","germs","germy","gerne","gesse","gesso",
        "geste","gests","getas","geums","geyan","geyer","ghast","ghats","ghaut","ghazi",
        "ghees","ghest","ghoul","ghusl","ghyll","gibed","gibel","giber","gibes","gibli",
        "gibus","gigas","gighe","gigot","gigue","gilas","gilds","gilet","gilia","gills",
        "gilly","gilpy","gilts","gimel","gimme","gimps","gimpy","ginch","ginga","ginge",
        "gings","ginks","ginny","ginzo","gipon","gippo","gippy","gipsy","girds","girlf",
        "girls","girly","girns","giron","giros","girrs","girsh","girth","girts","gismo",
        "gisms","gists","gitch","gites","giust","gived","giver","gizmo","glace","glade",
        "glads","glady","glaik","glair","glamp","glams","glans","glary","glatt","glaum",
        "glaur","glazy","gleba","glebe","gleby","glede","gleds","gleed","gleek","glees",
        "gleet","gleis","glens","glent","gleys","glial","glias","glibs","gliff","glift",
        "glike","glime","glims","glisk","glits","gloam","globi","globs","globy","glode",
        "glogg","gloms","gloop","glops","glost","glout","glows","glowy","gloze","gluer",
        "glues","gluey","glugg","glugs","glume","glums","gluon","glute","gluts","glyph",
        "gnapi","gnarl","gnarr","gnars","gnats","gnawn","gnaws","gnows","goads","goafs",
        "goaft","goals","goary","goaty","goave","goban","gobar","gobbe","gobbi","gobbo",
        "gobby","gobis","gobos","godet","godso","goels","goers","goest","goeth","goety",
        "gofer","goffs","gogga","gogos","goier","gojis","gokes","golds","goldy","golem",
        "goles","golfs","golly","golpe","golps","gombo","gomer","gompa","gonad","gonch",
        "gonef","goner","gongs","gonia","gonif","gonks","gonna","gonof","gonys","gonzo",
        "gooby","goodo","goody","gooey","goofs","goofy","googs","gooks","gooky","goold",
        "gools","gooly","goomy","goons","goony","goops","goopy","goors","goory","goosy",
        "gopak","gopik","goral","goras","goray","gorbs","gordo","gored","gores","goris",
        "gorms","gormy","gorps","gorse","gorsy","gosht","gosse","gotch","goths","gothy",
        "gouch","gouks","goura","gouts","gouty","goved","goves","gowan","gowds","gowfs",
        "gowks","gowls","gowns","goxes","goyim","goyle","graal","grabs","grads","graff",
        "graip","grama","grame","gramp","grams","grana","grano","grans","grapy","grata",
        "grats","gravs","grays","grebe","grebo","grece","greek","grees","grege","grego",
        "grein","grens","greps","grese","greve","grews","greys","grice","gride","grids",
        "griff","grift","grigs","grike","grins","griot","gript","gripy","grise","grist",
        "grisy","grith","grits","grize","groat","grody","grogs","groks","groma","groms",
        "grone","groof","grosz","grots","grouf","grovy","grrls","grrrl","grued","gruel",
        "grues","grufe","grume","grump","grund","gryce","gryde","gryke","grype","grypt",
        "guaco","guana","guano","guans","guars","gubba","gucks","gucky","gudes","guffs",
        "gugas","guggl","guido","guids","guile","guimp","guiro","gulab","gulag","gular",
        "gulas","gules","gulet","gulfs","gulfy","gully","gulph","gulps","gulpy","gumbo",
        "gumma","gummi","gumps","gunas","gundi","gundy","gunge","gungy","gunks","gunky",
        "gunny","guppy","guqin","gurdy","gurge","gurks","gurls","gurly","gurns","gurry",
        "gursh","gurus","gushy","gusla","gusle","gusli","gussy","gutsy","gutta","gutty",
        "guyed","guyle","guyot","guyse","gwine","gyals","gyans","gybed","gybes","gyeld",
        "gymps","gynae","gynie","gynny","gynos","gyoza","gypes","gypos","gyppo","gyppy",
        "gyral","gyred","gyres","gyron","gyros","gyrus","gytes","gyved","gyver","gyves",
        "haafs","haars","haats","hable","habus","hacek","hacks","hacky","hadal","haded",
        "hades","hadji","hadst","haems","haere","haets","haffs","hafiz","hafta","hafts",
        "haggs","haham","hahas","haick","haika","haiks","hails","haily","hains","haint",
        "hairs","hairy","haith","hajes","hajis","hajji","hakam","hakas","hakea","hakes",
        "hakim","hakus","halal","haldi","haled","haler","hales","halfa","halfs","halid",
        "hallo","halls","halma","halms","halon","halos","halse","halsh","halts","halva",
        "halwa","hamal","hamba","hamed","hamel","hames","hammy","hamza","hanap","hance",
        "hanch","handi","hangi","hanks","hanky","hansa","hanse","hants","haole","haoma",
        "hapas","hapax","haply","happi","hapus","haram","hards","hared","hares","harim",
        "harks","harls","harms","harns","haros","harps","harpy","harry","harts","hashy",
        "hasks","hasps","hasta","hated","hater","hates","hatha","hathi","hatty","hauds",
        "haufs","haugh","haugo","hauld","haulm","hauls","hault","hauns","hause","haute",
        "havan","havel","haver","haves","havoc","hawed","hawks","hawms","hawse","hayed",
        "hayer","hayey","hayle","hazan","hazed","hazer","hazes","hazle","heald","heals",
        "heame","heaps","heapy","heard","heare","hears","heast","heath","heats","heaty",
        "heben","hebes","hecht","hecks","heder","hedgy","heedy","heels","heeze","hefte",
        "hefts","heiau","heids","heigh","heils","hejab","hejra","heled","heles","helio",
        "hella","hells","helly","helms","helos","helot","helve","hemal","hemes","hemic",
        "hemin","hemps","hempy","hench","hends","henge","henna","henny","henry","hents",
        "hepar","herby","heres","herls","herma","herms","herns","heros","herps","herry",
        "herse","hertz","herye","hesps","hests","hetes","heths","heuch","heugh","hevea",
        "hevel","hewed","hewer","hewgh","hexad","hexed","hexer","hexes","hexyl","heyed",
        "hiant","hibas","hicks","hided","hider","hides","hiems","hifis","highs","hight",
        "hijab","hijra","hiked","hiker","hikes","hikoi","hilar","hilch","hillo","hilsa",
        "hilts","hilum","hilus","himbo","hinau","hinds","hings","hinky","hinny","hints",
        "hiois","hiped","hiper","hipes","hiply","hippy","hiree","hirer","hires","hissy",
        "hists","hitch","hithe","hived","hiver","hives","hizen","hoach","hoaed","hoagy",
        "hoard","hoars","hoary","hoast","hobos","hocks","hocus","hodad","hodja","hoers",
        "hogan","hogen","hoggs","hoghs","hogoh","hogos","hohed","hoick","hoied","hoiks",
        "hoing","hoise","hoist","hokas","hoked","hokes","hokey","hokis","hokku","hokum",
        "holed","holey","holks","holla","hollo","holme","holms","holon","holos","holts",
        "homas","homed","homey","homie","homme","homos","honan","honda","honds","honed",
        "honer","hones","hongi","hongs","honks","honky","hooch","hoods","hoody","hooey",
        "hoofs","hoogo","hooha","hooka","hooky","hooly","hoons","hoops","hoord","hoors",
        "hoosh","hoots","hooty","hoove","hopak","hoper","hopes","hoppy","horah","horal",
        "horas","horde","horis","horks","horme","horny","horst","horsy","hosed","hosel",
        "hosen","hoser","hoses","hosey","hosta","hotch","hoten","hotis","hotly","hotte",
        "hotty","houff","houfs","hough","houri","houts","hovea","hoved","hovel","hoven",
        "hoves","howay","howbe","howdy","howes","howff","howfs","howks","howre","howso",
        "howto","hoxed","hoxes","hoyas","hoyed","hoyle","hubba","hubby","hucks","hudna",
        "hudud","huers","huffs","huffy","huger","huggy","huhus","huias","huies","hukou",
        "hulas","hules","hulks","hulky","hullo","hulls","hully","humas","humfs","humic",
        "humph","humpy","humus","hunch","hundo","hunks","hunky","hunts","hurds","hurls",
        "hurly","hurra","hurst","hurts","hurty","hushy","husks","husky","husos","hussy",
        "hutch","hutia","huzza","huzzy","hwyls","hydel","hydra","hydro","hyena","hyens",
        "hygge","hying","hykes","hylas","hyleg","hyles","hylic","hymen","hynde","hyoid",
        "hyped","hyper","hypes","hypha","hyphy","hypos","hyrax","hyson","hythe","iambi",
        "iambs","ibrik","icers","iched","iches","ichor","icier","icily","icker","ickle",
        "icons","ictal","ictic","ictus","idant","iddah","iddat","iddut","idees","ident",
        "idler","idles","idlis","idola","idols","idyll","idyls","iftar","igapo","igged",
        "igloo","iglus","ignis","ihram","iiwis","ikans","ikats","ikons","ileac","ileal",
        "ileum","ileus","iliac","iliad","ilial","ilium","iller","illth","imagy","imams",
        "imari","imaum","imbar","imbed","imbos","imide","imido","imids","imine","imino",
        "imlis","immew","immit","immix","imped","impis","impot","impro","imshi","imshy",
        "inapt","inarm","inbox","inbye","incas","incel","incle","incog","incus","incut",
        "indew","india","indol","indow","indri","indue","inerm","infix","infos","infra",
        "ingan","ingle","inion","inked","inker","inkle","inlay","inlet","inned","innie",
        "innit","inorb","inros","inrun","insee","inset","inspo","intel","intil","intis",
        "intra","inula","inure","inurn","inust","invar","inver","inwit","iodic","iodid",
        "iodin","ioras","iotas","ippon","irade","irids","iring","irked","iroko","irone",
        "irons","isbas","ishes","isled","isles","islet","isnae","issei","issue","istle",
        "itchy","items","ither","ivied","ivies","ixias","ixnay","ixora","ixtle","izard",
        "izars","izzat","jaaps","jacal","jacet","jacky","jades","jafas","jaffa","jagas",
        "jager","jaggs","jaggy","jagir","jagra","jails","jaker","jakes","jakey","jakie",
        "jalap","jaleo","jalop","jambe","jambo","jambs","jambu","james","jammy","jamon",
        "jamun","janes","janky","janns","janny","janty","japed","japer","japes","jarks",
        "jarls","jarps","jarta","jarul","jasey","jaspe","jasps","jatha","jatis","jatos",
        "jauks","jaune","jaups","javas","javel","jawan","jawed","jawns","jaxie","jeats",
        "jebel","jedis","jeels","jeely","jeeps","jeera","jeers","jeeze","jefes","jeffs",
        "jehad","jehus","jelab","jello","jells","jembe","jemmy","jenny","jeons","jerid",
        "jerry","jesse","jessy","jests","jesus","jetee","jetes","jeton","jetty","jeune",
        "jewed","jewie","jhala","jheel","jhils","jiaos","jibba","jibbs","jibed","jiber",
        "jibes","jiffs","jiggy","jigot","jihad","jills","jilts","jimpy","jingo","jings",
        "jinne","jinni","jinns","jirds","jirga","jirre","jisms","jitis","jitty","jived",
        "jiver","jives","jivey","jnana","jobed","jobes","jocko","jocks","jocky","jocos",
        "jodel","joeys","johns","joist","joked","jokes","jokey","jokol","joled","joles",
        "jolie","jollo","jolls","jolts","jolty","jomon","jomos","jones","jongs","jonty",
        "jooks","joram","jorts","jorum","jotas","jotty","jotun","joual","jougs","jouks",
        "joule","jours","jowar","jowed","jowls","jowly","joyed","jubas","jubes","jucos",
        "judas","judgy","judos","jugal","jugum","jujus","juked","jukes","jukus","julep",
        "julia","jumar","jumby","junco","junks","junky","junta","junto","jupes","jupon",
        "jural","jurat","jurel","jures","juris","juste","justs","jutes","jutty","juves",
        "juvie","kaama","kabab","kabar","kabob","kacha","kacks","kadai","kades","kadis",
        "kafir","kagos","kagus","kahal","kaiak","kaids","kaies","kaifs","kaika","kaiks",
        "kails","kaims","kaing","kains","kajal","kakas","kakis","kalam","kalas","kales",
        "kalif","kalis","kalpa","kalua","kamas","kames","kamik","kamis","kamme","kanae",
        "kanal","kanas","kanat","kandy","kaneh","kanes","kanga","kangs","kanji","kants",
        "kanzu","kaons","kapai","kapas","kapha","kaphs","kapok","kapow","kappa","kapur",
        "kapus","kaput","karai","karas","karat","karee","karez","karks","karma","karns",
        "karoo","karos","karri","karst","karsy","karts","karzy","kasha","kasme","katal",
        "katas","katis","katti","kaugh","kauri","kauru","kaury","kaval","kavas","kawas",
        "kawau","kawed","kayle","kayos","kazis","kazoo","kbars","kcals","keaki","kebar",
        "kebob","kecks","kedge","kedgy","keech","keefs","keeks","keema","keeno","keens",
        "keets","keeve","kefir","kehua","keirs","kelep","kelim","kells","kelly","kelps",
        "kelpy","kelts","kelty","kembo","kembs","kemps","kempt","kempy","kenaf","kench",
        "kendo","kenos","kente","kents","kepis","kerbs","kerel","kerfs","kerky","kerma",
        "kerne","kerns","keros","kerry","kerve","kesar","kests","ketas","ketch","ketes",
        "ketol","kevel","kevil","kexes","keyed","keyer","khadi","khads","khafs","khana",
        "khans","khaph","khats","khaya","khazi","kheda","kheer","kheth","khets","khirs",
        "khoja","khors","khoum","khuds","khula","khyal","kiaat","kiack","kiaki","kiang",
        "kiasu","kibbe","kibbi","kibei","kibes","kibla","kicky","kiddo","kiddy","kidel",
        "kideo","kidge","kiefs","kiers","kieve","kievs","kight","kikay","kikes","kikoi",
        "kiley","kilig","kilim","kills","kilns","kilos","kilps","kilts","kilty","kimbo",
        "kimet","kinas","kinda","kinds","kindy","kines","kings","kingy","kinin","kinks",
        "kinky","kinos","kiore","kiosk","kipah","kipas","kipes","kippa","kipps","kipsy",
        "kirby","kirks","kirns","kirri","kisan","kissy","kists","kitab","kited","kiter",
        "kites","kithe","kiths","kitke","kitty","kitul","kivas","kiwis","klang","klaps",
        "klett","klick","klieg","kliks","klong","kloof","kluge","klutz","knags","knaps",
        "knarl","knars","knaur","knave","knawe","kneed","knees","knell","knick","knish",
        "knits","knive","knoop","knops","knosp","knoud","knout","knowd","knowe","knubs",
        "knule","knurl","knurr","knurs","knuts","koans","koaps","koban","kobos","koels",
        "koffs","kofta","kogal","kohas","kohen","kohls","koine","koiwi","kojis","kokam",
        "kokas","koker","kokra","kokum","kolas","kolos","kombi","kombu","konbu","kondo",
        "konks","kooks","kooky","koori","kopek","kophs","kopje","koppa","korai","koran",
        "koras","korat","kores","koris","korma","koros","korun","korus","koses","kotch",
        "kotos","kotow","koura","kraal","krabs","kraft","krais","krait","krang","krans",
        "kranz","kraut","krays","kreef","kreen","kreep","kreng","krewe","krill","kriol",
        "krona","krone","kroon","krubi","krump","krunk","ksars","kubie","kudus","kudzu",
        "kufis","kugel","kuias","kukri","kukus","kulak","kulan","kulas","kulfi","kumis",
        "kumys","kunas","kunds","kuris","kurre","kurta","kurus","kusso","kusti","kutai",
        "kutas","kutch","kutis","kutus","kuyas","kuzus","kvass","kvell","kwaai","kwela",
        "kwink","kwirl","kyack","kyaks","kyang","kyars","kyats","kybos","kydst","kyles",
        "kylie","kylin","kylix","kyloe","kynde","kynds","kypes","kyrie","kytes","kythe",
        "kyudo","laarf","laari","labda","labia","labis","labne","labra","laccy","lacer",
        "laces","lacet","lacey","lacis","lacka","lacks","lacky","laddu","laddy","laded",
        "ladee","laden","lader","lades","ladle","ladoo","laers","laevo","lagan","lagar",
        "lager","laggy","lahal","lahar","laich","laics","laide","laids","laigh","laika",
        "laiks","laird","lairs","lairy","laith","laity","laked","laker","lakhs","lakin",
        "laksa","laldy","lalls","lamas","lamby","lamed","lamer","lames","lamia","lammy",
        "lanai","lanas","lanch","lande","laned","lanks","lanky","lants","lapas","lapel",
        "lapin","lapis","lapje","lappa","lappy","larch","lards","lardy","laree","lares",
        "larfs","larga","largo","laris","larks","larky","larns","larnt","larum","lased",
        "lases","lassi","lasso","lassu","lassy","lasts","latah","lated","laten","lathi",
        "laths","lathy","latke","latte","latus","lauan","lauch","laude","lauds","laufs",
        "laund","laura","laval","lavas","laved","laver","laves","lavra","lavvy","lawed",
        "lawer","lawin","lawks","lawns","lawny","lawsy","laxed","laxer","laxes","laxly",
        "layby","layed","layin","layup","lazar","lazed","lazes","lazos","lazzi","lazzo",
        "leach","leady","leafs","leaks","leams","leans","leant","leany","leapt","leare",
        "lears","leary","leats","leavy","leaze","leben","leccy","leche","ledes","ledgy",
        "ledum","leear","leech","leeks","leeps","leers","leery","leese","leets","leeze",
        "lefte","lefts","lefty","leger","leges","legge","leggo","leggy","legit","legno",
        "lehrs","lehua","leirs","leish","leman","lemed","lemel","lemes","lemma","lemme",
        "lemur","lenes","lengs","lenis","lenos","lense","lenti","lento","leone","lepak",
        "leper","lepid","lepra","lepta","lered","leres","lerps","lesbo","leses","lesos",
        "lests","letch","lethe","letty","letup","leuch","leuco","leuds","leugh","levas",
        "levee","leves","levin","levis","lewis","lexes","lexis","lezes","lezza","lezzo",
        "lezzy","liana","liane","liang","liard","liars","liart","libel","liber","libor",
        "libra","libre","libri","licet","lichi","licht","licit","licks","lidar","lidos",
        "liefs","liege","liens","liers","lieus","lieve","lifer","lifes","lifey","lifts",
        "ligan","liger","ligge","ligne","liked","liken","liker","likes","likin","lills",
        "lilos","lilts","lilty","liman","limas","limax","limba","limbi","limbo","limby",
        "limen","limes","limey","limma","limns","limos","limpa","linac","linch","linds",
        "lindy","liney","linga","lingo","lings","lingy","linin","linky","linns","linny",
        "linos","lints","linty","linum","linux","lipas","lipes","lipid","lipin","lipos",
        "lippy","liras","lirks","lirot","lises","lisks","lisle","lisps","litai","litas",
        "lited","litem","liter","lites","lithe","litho","liths","litie","litre","livid",
        "livor","livre","liwaa","liwas","llano","loach","loams","loamy","loast","loath",
        "loave","lobar","lobed","lobes","lobos","lobus","loche","lochs","lochy","locie",
        "locis","locky","locos","locum","locus","loden","lodes","loess","lofts","logan",
        "loges","loggy","logia","logie","login","logoi","logon","lohan","loids","loins",
        "loipe","loirs","lokes","lokey","lokum","lolas","loled","lollo","lolls","lolly",
        "lolog","lolos","lomas","lomed","lomes","loner","longa","longs","looby","looed",
        "looey","loofa","loofs","looie","looky","looms","loons","loony","loopy","loord",
        "loots","loped","loper","lopes","loppy","loral","loran","lordy","lorel","lores",
        "loric","loris","losed","losel","losen","loses","lossy","lotah","lotas","lotes",
        "lotic","lotos","lotsa","lotta","lotte","lotto","lotus","loued","lough","louie",
        "louis","louma","lound","louns","loupe","loups","loure","lours","loury","louse",
        "louts","lovat","lovee","loves","lovey","lovie","lowan","lowed","lowen","lowes",
        "lownd","lowne","lowns","lowps","lowry","lowse","lowth","lowts","loxed","loxes",
        "lozen","luach","luaus","lubed","lubes","lubra","luces","lucks","lucre","ludes",
        "ludic","ludos","luffa","luffs","luged","luger","luges","lulls","lulus","lumas",
        "lumbi","lumen","lumme","lummy","lunas","lunes","lunet","lungi","lunks","lunts",
        "lupin","lupus","lured","lurer","lures","lurex","lurgi","lurgy","lurid","lurks",
        "lurry","lurve","luser","lushy","lusks","lusts","lusus","lutea","luted","luter",
        "lutes","luvvy","luxed","luxer","luxes","lweis","lyams","lyard","lyart","lyase",
        "lycea","lycee","lycra","lymes","lymph","lynes","lyres","lysed","lyses","lysin",
        "lysis","lysol","lyssa","lyted","lytes","lythe","lytic","lytta","maaed","maare",
        "maars","maban","mabes","macas","macaw","macca","maced","macer","maces","mache",
        "machi","machs","macka","macks","macle","macon","macte","madal","madam","madar",
        "maddy","madge","madid","madly","mados","madre","maedi","maerl","mafic","mafts",
        "magas","mages","maggs","magna","magot","magus","mahal","mahem","mahis","mahoe",
        "mahrs","mahua","mahwa","maids","maiko","maiks","maile","maill","mailo","mails",
        "maims","mains","maire","mairs","maise","maist","maize","majas","majat","majoe",
        "majos","makaf","makai","makan","makar","makee","makes","makie","makis","makos",
        "malae","malai","malam","malar","malas","malax","maleo","malic","malik","malis",
        "malky","malms","malmy","malts","malus","malva","malwa","mamak","mamas","mamba",
        "mambo","mambu","mamee","mamey","mamie","mamil","mammy","manas","manat","mandi",
        "mands","mandy","maneb","maned","maneh","manes","manet","mange","mangi","mangs",
        "mangy","manic","manie","manis","manks","manky","manly","manna","manny","manoa",
        "manos","manse","manso","manta","mante","manto","mants","manty","manul","manus",
        "manzo","mapau","mapes","mapou","mappy","maqam","maqui","marae","marah","maral",
        "maran","maras","maray","marcs","mards","mardy","mares","marga","marge","margo",
        "margs","maria","marid","maril","marka","marle","marls","marly","marma","marms",
        "maron","maror","marra","marri","marry","marse","marts","marua","marvy","masas",
        "mased","maser","mases","masha","mashy","massa","masse","massy","masts","masty",
        "masur","masus","masut","matai","mated","mater","matey","mathe","maths","matin",
        "matlo","matra","matsu","matts","matty","matza","matzo","mauby","mauds","mauka",
        "maula","mauls","maums","maumy","maund","maunt","mauri","mausy","mauts","mauve",
        "mauvy","mauzy","maven","mavie","mavin","mavis","mawed","mawks","mawky","mawla",
        "mawns","mawps","mawrs","maxed","maxes","maxis","mayan","mayas","mayed","mayos",
        "mayst","mazac","mazak","mazar","mazas","mazed","mazel","mazer","mazes","mazet",
        "mazey","mazut","mbari","mbars","mbila","mbira","mbret","mbube","mbuga","meads",
        "meake","meaks","mealy","meane","meant","meany","meare","mease","meath","mebbe",
        "mebos","mecca","mecha","mechs","mecks","mecum","medii","medin","medle","meech",
        "meeds","meeja","meeps","meers","meets","meffs","meids","meiko","meils","meins",
        "meint","meiny","meism","meith","mekka","melam","melas","melba","melch","melds",
        "meles","melic","melik","mells","meloe","melos","melts","melty","memes","memic",
        "memos","menad","mence","mends","mened","menes","menge","mengs","menil","mensa",
        "mense","mensh","menta","mento","ments","menus","meous","meows","merch","mercs",
        "merde","merds","mered","merel","merer","meres","meril","meris","merks","merle",
        "merls","merse","mersk","mesad","mesal","mesas","mesca","mesel","mesem","meses",
        "meshy","mesia","mesic","mesne","meson","mesto","mesyl","metas","meted","meteg",
        "metel","metes","methi","metho","meths","methy","metic","metif","metis","metol",
        "metre","metro","metta","meums","meuse","meved","meves","mewed","mewls","meynt",
        "mezes","mezza","mezze","mezzo","mgals","mhorr","miais","miaou","miaow","miasm",
        "miaul","micas","miche","michi","micht","micks","micky","micos","micra","micro",
        "middy","midge","midgy","midis","miens","mieux","mieve","miffs","miffy","mifty",
        "miggs","migma","migod","mihas","mihis","mikan","miked","mikes","mikos","mikra",
        "mikva","milch","milds","miler","miles","milfs","milia","milko","milks","milky",
        "mille","milly","milor","milos","milpa","milts","milty","miltz","mimed","mimeo",
        "mimer","mimes","mimis","mimsy","minae","minar","minas","mincy","mindi","mines",
        "minge","mingi","mings","mingy","minim","minis","minke","minks","minny","minos",
        "minse","mints","minty","minxy","miraa","mirah","mirch","mired","mires","mirex",
        "mirid","mirin","mirkn","mirks","mirky","mirls","mirly","miros","mirrl","mirrs",
        "mirvs","mirza","misal","misch","misdo","mises","misgo","misky","misls","misos",
        "missa","missy","misto","mists","mitas","mitch","miter","mites","mitey","mitie",
        "mitis","mitre","mitry","mitta","mitts","mivey","mivvy","mixen","mixes","mixie",
        "mixis","mixte","mixup","miyas","mizen","mizes","mizzy","mmkay","mneme","moais",
        "moaky","moals","moana","moany","moars","mobby","mobed","mobee","mobes","mobey",
        "mobie","moble","mobos","mocap","mocha","mochi","mochs","mochy","mocks","mocky",
        "mocos","mocus","modal","moder","modge","modii","modin","modoc","modom","modus",
        "moeni","moers","mofos","mogar","mogas","moggy","mogos","mogra","mogue","mogul",
        "mohar","mohel","mohos","mohrs","mohua","mohur","moile","moils","moira","moire",
        "moits","moity","mojos","moker","mokes","mokey","mokis","mokky","mokos","mokus",
        "molal","molas","moled","moler","moles","moley","molie","molla","molle","mollo",
        "molls","molly","moloi","molos","molto","molts","molue","molvi","molys","momes",
        "momie","momma","momme","mommy","momos","mompe","momus","monad","monal","monas",
        "monde","mondo","moner","mongo","mongs","monic","monie","monos","monpe","monte",
        "monty","moobs","mooch","mooed","mooey","mooks","moola","mooli","mools","mooly",
        "moong","mooni","moons","moony","moops","moors","moory","mooth","moots","moove",
        "moped","moper","mopes","mopey","moppy","mopsy","mopus","morae","morah","moran",
        "moras","morat","moray","moree","morel","mores","morgy","moria","morin","mormo",
        "morna","morne","morns","moron","moror","morra","morro","morse","morts","moruk",
        "mosed","moses","mosey","mosks","mosso","mossy","moste","mosto","mosts","moted",
        "moten","motes","motet","motey","mothy","motif","motis","moton","motte","motts",
        "motty","motus","motza","mouch","moues","moufs","mould","moule","mouls","moult",
        "mouly","moups","moust","mousy","moves","mowas","mower","mowie","mowra","moxas",
        "moxie","moyas","moyle","moyls","mozed","mozes","mozos","mpret","mrads","msasa",
        "mtepe","mucho","mucic","mucid","mucin","mucko","mucks","mucky","mucor","mucro",
        "mudar","mudge","mudif","mudim","mudir","mudra","muffy","mufti","mugga","muggs",
        "muggy","mugho","mugil","mugos","muhly","muids","muils","muirs","muiry","muist",
        "mujik","mukim","mukti","mulai","mulct","muled","muley","mulga","mulie","mulla",
        "mulls","mulse","mulsh","mumbo","mumms","mummy","mumph","mumsy","mumus","munch",
        "munds","mundu","munga","munge","mungi","mungo","mungs","mungy","munia","munis",
        "munja","munjs","munts","muntu","muons","muras","mured","mures","murex","murgh",
        "murgi","murid","murks","murls","murly","murra","murre","murri","murrs","murry",
        "murth","murti","muruk","murva","musar","musca","mused","musee","muser","muses",
        "muset","musha","mushy","musit","musks","musky","musos","musse","mussy","musta",
        "musth","musts","mutas","mutch","muter","mutes","mutha","mutic","mutis","muton",
        "mutti","mutts","mutum","muvva","muxed","muxes","muzak","muzzy","mvula","mvule",
        "mvuli","myall","myals","mylar","mynah","mynas","myoid","myoma","myons","myope",
        "myops","myopy","myrrh","mysid","mysie","mythi","mythy","myxos","mzees","naams",
        "naans","naats","nabam","nabby","nabes","nabis","nabks","nabla","nabob","nache",
        "nacre","nadas","nadir","naeve","naevi","naffs","nagar","nagas","nages","naggy",
        "nagor","nahal","naiad","naibs","naice","naids","naieo","naifs","naiks","nails",
        "naily","nains","naios","naira","nairu","najib","nakas","naked","naker","nakfa",
        "nalas","naled","nalla","namad","namak","namaz","namer","names","namma","namus",
        "nanas","nance","nancy","nandu","nanna","nanos","nante","nanti","nanto","nants",
        "nanty","nanua","napas","naped","napes","napoh","napoo","nappa","nappe","nappy",
        "naras","narco","narcs","nards","nares","naric","naris","narks","narky","narod",
        "narra","narre","nasal","nashi","nasho","nasis","nason","nasty","nasus","natak",
        "natal","natch","nates","natis","natto","natty","natya","nauch","naunt","navar",
        "naved","naves","navew","navvy","nawab","nawal","nazar","nazes","nazir","nazis",
        "nazzy","nduja","neafe","neals","neant","neaps","nears","neath","neato","neats",
        "nebby","nebek","nebel","neche","necks","neddy","neebs","needy","neefs","neeld",
        "neele","neemb","neems","neeps","neese","neeze","nefie","negri","negro","negus",
        "neifs","neigh","neist","neive","nelia","nelis","nelly","nemas","nemic","nemns",
        "nempt","nenes","nenta","neons","neosa","neoza","neper","nepit","neral","neram",
        "nerds","nerdy","nerfs","nerka","nerks","nerol","nerts","nertz","nervy","neski",
        "nests","nesty","netas","netes","netop","netta","netts","netty","neuks","neume",
        "neums","nevel","neves","nevis","nevus","nevvy","newbs","newed","newel","newie",
        "newsy","newts","nexal","nexin","nexts","nexum","ngaio","ngaka","ngana","ngapi",
        "ngati","ngege","ngoma","ngoni","ngram","ngwee","nibby","nicad","niced","nicer",
        "nicey","nicht","nicks","nicky","nicol","nidal","nided","nides","nidor","nidus",
        "niece","niefs","niess","nieve","nifes","niffs","niffy","nifle","nifty","niger",
        "nigga","nighs","nigre","nigua","nihil","nikab","nikah","nikau","nilas","nills",
        "nimbi","nimbs","nimby","nimps","niner","nines","ninja","ninny","ninon","ninta",
        "niopo","nioza","nipas","nipet","nippy","niqab","nirls","nirly","nisei","nisin",
        "nisse","nisus","nital","niter","nites","nitid","niton","nitre","nitro","nitry",
        "nitta","nitto","nitty","nival","nivas","nivel","nixed","nixer","nixes","nixie",
        "nizam","njirl","nkosi","nmoli","nmols","noahs","nobby","nocks","nodal","noddy",
        "noded","nodes","nodum","nodus","noels","noema","noeme","nogal","noggs","noggy",
        "nohow","noias","noils","noily","noint","noire","noirs","nokes","noles","nolle",
        "nolls","nolos","nomad","nomas","nomen","nomes","nomic","nomoi","nomos","nonan",
        "nonas","nonce","noncy","nonda","nondo","nones","nonet","nongs","nonic","nonis",
        "nonna","nonno","nonny","nonyl","noobs","noois","nooit","nooks","nooky","noone",
        "noons","noops","noose","noove","nopal","noria","norie","noris","norks","norma",
        "norms","nosed","noser","noses","nosey","noshi","nosir","notal","notam","noter",
        "notum","nougs","nouja","nould","noule","nouls","nouns","nouny","noups","noust",
        "novae","novas","novia","novio","novum","noway","nowds","nowed","nowls","nowts",
        "nowty","noxal","noxas","noxes","noyau","noyed","noyes","nrtta","nrtya","nsima",
        "nubby","nubia","nucha","nucin","nuddy","nuder","nudes","nudgy","nudie","nudzh",
        "nuevo","nuffs","nugae","nujol","nuked","nukes","nulla","nullo","nulls","nully",
        "numbs","numen","nummy","numps","nunks","nunky","nunny","nunus","nuque","nurds",
        "nurdy","nurls","nurrs","nurts","nurtz","nused","nuses","nutso","nutsy","nutty",
        "nyaff","nyala","nyams","nying","nymph","nyong","nyssa","nyung","nyuse","nyuze",
        "oafos","oaked","oaker","oakum","oared","oarer","oasal","oases","oasts","oaten",
        "oater","oaths","oaves","obang","obbos","obeah","obeli","obese","obeys","obias",
        "obied","obiit","obits","objet","oboes","obole","oboli","obols","occam","ocher",
        "oches","ochre","ochry","ocker","ocote","ocrea","octad","octal","octan","octas",
        "octic","octli","octyl","oculi","odahs","odals","odder","oddly","odeon","odeum",
        "odism","odist","odium","odoom","odors","odour","odums","odyle","odyls","ofays",
        "offal","offed","offer","offie","oflag","often","ofter","ofuro","ogams","ogeed",
        "ogees","oggin","ogham","ogive","ogled","ogler","ogles","ogmic","ogres","ohelo",
        "ohias","ohing","ohmic","ohone","oicks","oidia","oiled","oiler","oilet","oinks",
        "oints","oiran","ojime","okapi","okays","okehs","okies","oking","okole","okras",
        "okrug","oktas","olate","olden","older","oldie","oldly","olehs","oleic","olein",
        "olent","oleos","oleum","oleyl","oligo","olios","oliva","ollas","ollav","oller",
        "ollie","ology","olona","olpae","olpes","omasa","omber","ombre","ombus","omdah",
        "omdas","omdda","omdeh","omees","omens","omers","omiai","omits","omlah","ommel",
        "ommin","omnes","omovs","omrah","omuls","oncer","onces","oncet","oncus","ondes",
        "ondol","onely","oners","onery","ongon","onion","onium","onkus","onlap","onlay",
        "onmun","onned","onsen","ontal","ontic","ooaas","oobit","oohed","ooids","oojah",
        "oomph","oonts","oopak","ooped","oopsy","oorie","ooses","ootid","ooyah","oozed",
        "oozes","oozie","oozle","opahs","opals","opens","opepe","opery","opgaf","opihi",
        "opine","oping","opium","oppos","opsat","opsin","opsit","opter","opzit","orach",
        "oracy","orals","orang","orans","orant","orate","orbat","orbed","orbic","orcas",
        "orcin","ordie","ordos","oread","orfes","orful","orgia","orgic","orgue","oribi",
        "oriel","origo","orixa","orles","orlon","orlop","ormer","ornee","ornis","orped",
        "orpin","orris","ortet","ortho","orval","orzos","osars","oscar","osetr","oseys",
        "oshac","osier","oskin","oslin","osmic","osmol","osone","ossia","ostia","otaku",
        "otary","othyl","otium","ottar","otter","ottos","oubit","ouche","oucht","oueds",
        "ouens","ouija","oulks","oumas","oundy","oupas","ouped","ouphe","ouphs","ourey",
        "ourie","ousel","ousia","ousts","outby","outdo","outed","outen","outie","outre",
        "outro","outta","ouzel","ouzos","ovals","ovate","ovels","overs","ovine","ovism",
        "ovist","ovoid","ovoli","ovolo","ovule","oware","owari","owche","owers","owies",
        "owled","owler","owlet","owned","owner","ownio","owres","owrie","owsen","oxbow",
        "oxeas","oxers","oxeye","oxids","oxies","oxime","oxims","oxine","oxlip","oxman",
        "oxmen","oxter","oyama","oyers","ozeki","ozena","ozzie","paaho","paals","paans",
        "pacai","pacas","pacay","pacer","paces","pacey","pacha","packy","pacos","pacta",
        "pacts","padam","padas","paddo","padis","padle","padma","padou","padre","padri",
        "paean","paedo","paeon","paged","pager","pagle","pagne","pagod","pagri","pahit",
        "pahos","pahus","paiks","pails","pains","paipe","paips","paire","paisa","paise",
        "pakay","pakka","pakki","pakua","pakul","palak","palar","palas","palay","palea",
        "paled","paler","pales","palet","palis","palki","palla","palls","pallu","pally",
        "palmy","palpi","palps","palsa","palsy","palus","pamby","pampa","panax","pance",
        "panch","pands","pandy","paned","panes","panga","pangs","panim","panir","panko",
        "panks","panna","panne","panni","panny","pansy","panto","panty","paoli","paolo",
        "papad","papal","papas","papaw","papes","papey","pappi","pappy","papri","parae",
        "paras","parch","parcs","pardi","pards","pardy","pared","paren","pareo","parer",
        "pares","pareu","parev","parge","pargo","parid","paris","parka","parki","parks",
        "parky","parle","parly","parma","parmo","parms","parol","parps","parra","parrs",
        "parry","parse","parte","parti","parts","parve","parvo","pasag","pasar","pasch",
        "paseo","pases","pasha","pashm","paska","pasmo","paspy","passe","passu","pasts",
        "pasty","patas","pated","patee","patel","paten","pater","pates","paths","patia",
        "patin","patka","patly","patsy","patta","patte","pattu","patty","patus","pauas",
        "pauls","pauxi","pavan","pavas","paved","paven","paver","paves","pavid","pavie",
        "pavin","pavis","pavon","pavvy","pawas","pawaw","pawed","pawer","pawks","pawky",
        "pawls","pawns","paxes","payed","payee","payer","payor","paysd","peace","peage",
        "peags","peake","peaky","peals","peans","peare","pears","peart","pease","peasy",
        "peats","peaty","peavy","peaze","pebas","pechs","pecia","pecke","pecks","pecky",
        "pects","pedes","pedis","pedon","pedos","pedro","peece","peeky","peely","peens",
        "peent","peeoy","peepe","peeps","peepy","peers","peery","peeve","peevo","peggy",
        "peghs","pegma","pegos","peine","peins","peise","peisy","peize","pekan","pekau",
        "pekea","pekes","pekid","pekin","pekoe","pelas","pelau","pelch","peles","pelfs",
        "pells","pelma","pelog","pelon","pelsh","pelta","pelts","pelus","penal","pence",
        "pends","pendu","pened","penes","pengo","penie","penis","penks","penna","penne",
        "penni","pense","pensy","pents","peola","peons","peony","pepla","peple","pepon",
        "pepos","peppy","pepsi","pequi","perae","perai","perce","percs","perdu","perdy",
        "perea","peres","perfs","peris","perle","perls","perms","permy","perne","perns",
        "perog","perps","perry","perse","persp","perst","perts","perve","pervo","pervs",
        "pervy","pesch","pesky","pesos","pesta","pesto","pests","pesty","petar","peter",
        "petit","petos","petre","petri","petti","petto","pewed","pewee","pewit","peyse",
        "pfftt","phage","phang","phare","pharm","phasm","pheer","pheme","phene","pheon",
        "phese","phial","phies","phish","phizz","phlox","phobe","phoca","phono","phons",
        "phony","phooh","phooo","phota","phots","photy","phpht","phubs","phuts","phutu",
        "phwat","phyla","phyle","phyma","phynx","physa","piais","piani","pians","pibal",
        "pical","picas","piccy","picey","pichi","picky","picon","picot","picra","picul",
        "pieds","piend","piers","piert","pieta","piets","piezo","pight","pigly","pigmy",
        "piing","pikas","pikau","piked","pikel","piker","pikes","pikey","pikis","pikul",
        "pilae","pilaf","pilao","pilar","pilau","pilaw","pilch","pilea","piled","pilei",
        "piler","piles","piley","pilin","pilis","pills","pilon","pilow","pilum","pilus",
        "pimas","pimps","pinas","pinax","pince","pinda","pinds","pined","piner","pines",
        "piney","pinga","pinge","pingo","pings","pinko","pinks","pinky","pinna","pinny",
        "pinol","pinon","pinot","pinta","pinto","pinup","pions","piony","pious","pioye",
        "pioys","pipal","pipas","piped","pipes","pipet","pipid","pipis","pipit","pippy",
        "pipul","pique","piqui","pirai","pirks","pirls","pirns","pirog","pirre","pirri",
        "pirrs","pisco","pises","pisky","pisos","pissy","piste","pitas","piths","pithy",
        "piton","pitot","pitso","pitsu","pitta","pittu","piuma","piums","pivos","pixes",
        "pixie","piyut","pized","pizer","pizes","plaas","plack","plaga","plage","plaig",
        "plait","planc","planh","plaps","plash","plasm","plast","plats","platt","platy",
        "plaud","plaur","plavs","playa","plays","pleas","plebe","plebs","pleck","pleep",
        "plein","plena","plene","pleno","pleon","plesh","plets","plews","plexi","plica",
        "plies","pligs","plims","pling","plink","plips","plish","ploat","ploce","plock",
        "ploit","plomb","plong","plonk","plook","ploot","plops","plore","plotz","plouk",
        "plout","plowt","ploye","ploys","pluds","plues","pluff","pluke","plumy","plung",
        "pluot","plups","plute","pluto","pluty","plyer","pneus","poach","poaka","poake",
        "poalo","pobby","poboy","pocan","poche","pocho","pocks","pocky","podal","poddy",
        "podex","podge","podgy","podia","podos","podus","poena","poeps","poesy","poete",
        "pogey","pogge","poggy","pogos","pogue","pohed","poilu","poind","poire","pokal",
        "poked","pokes","pokey","pokie","pokit","poled","poler","poles","poley","polio",
        "polis","polje","polka","polks","pollo","polly","polos","polts","polys","pomas",
        "pombe","pomes","pomme","pommy","pomos","pompa","pomps","ponce","poncy","pondy",
        "pones","poney","ponga","pongo","pongs","pongy","ponks","ponor","ponto","ponts",
        "ponty","ponzu","pooay","poods","pooed","pooey","poofs","poofy","poohs","poohy",
        "pooja","pooka","pooks","pooly","poons","poopa","poops","poopy","poori","poort",
        "poots","pooty","poove","poovy","popes","popia","popos","poppa","poppy","popsy",
        "popup","porae","poral","porer","pores","porey","porge","porgy","porin","porks",
        "porky","porno","porns","porny","porta","porte","porth","porty","porus","posca",
        "poser","poset","posey","posho","posit","posol","poste","posts","potae","potai",
        "potch","poted","potes","potin","potoo","potro","potsy","potto","potts","potty",
        "pouce","pouff","poufs","poufy","pouis","pouke","pouks","poule","poulp","poult",
        "poupe","poupt","pours","pousy","pouts","pouty","povos","powan","powie","powin",
        "powis","powlt","pownd","powns","powny","powre","powsy","poxed","poxes","poyas",
        "poynt","poyou","poyse","pozzy","praam","prads","prags","prahu","prams","prana",
        "prang","praos","praps","prase","prate","prats","pratt","praty","praus","prays",
        "preak","predy","preed","preem","preen","prees","preif","preke","prems","premy",
        "prent","preon","preop","preps","presa","prese","prest","preta","preux","preve",
        "prexy","preys","prial","prian","prick","pricy","pridy","pried","prief","prier",
        "pries","prigs","prill","prima","primi","primo","primp","prims","primy","pring",
        "prink","prion","prise","priss","prius","proal","proas","probs","proby","prodd",
        "prods","proem","profs","progs","proin","proke","prole","proll","promo","proms",
        "pronk","prook","proot","props","prora","prore","proso","pross","prost","prosy",
        "proto","proul","prowk","prows","proyn","pruno","prunt","pruny","pruta","pryan",
        "pryer","pryse","pseud","pshaw","pshut","psias","psion","psoae","psoai","psoas",
        "psora","psych","psyop","ptish","ptype","pubby","pubco","pubes","pubic","pubis",
        "pubsy","pucan","pucer","puces","pucka","pucks","puddy","pudge","pudgy","pudic",
        "pudor","pudsy","pudus","puers","puffa","puffs","puffy","puggy","pugil","puhas",
        "pujah","pujas","pukas","puked","puker","pukes","pukey","pukka","pukus","pulao",
        "pulas","puled","puler","pules","pulik","pulis","pulka","pulks","pulli","pulls",
        "pully","pulmo","pulps","pulpy","pulus","pulut","pumas","pumie","pumpy","punas",
        "punce","punga","pungi","pungo","pungs","pungy","punim","punji","punka","punks",
        "punky","punny","punto","punts","punty","pupae","pupal","pupas","puppa","pupus",
        "purao","purau","purda","purdy","pured","puree","purer","pures","purga","purin",
        "puris","purls","puros","purps","purpy","purre","purrs","purry","pursy","purty",
        "puses","pusle","pussy","putas","puter","putid","putin","puton","putos","putti",
        "putto","putts","puttu","putza","puuko","puyas","puzel","puzta","pwned","pyats",
        "pyets","pygal","pygmy","pyins","pylon","pyned","pynes","pyoid","pyots","pyral",
        "pyran","pyres","pyrex","pyric","pyros","pyrus","pyuff","pyxed","pyxes","pyxie",
        "pyxis","pzazz","qadis","qaids","qajaq","qanat","qapik","qibla","qilas","qipao",
        "qophs","qorma","quabs","quads","quaff","quags","quair","quais","quake","quaky",
        "quale","qualy","quank","quant","quare","quark","quarl","quash","quass","quate",
        "quats","quawk","quaws","quayd","quays","qubit","quean","queck","queek","queem",
        "quell","queme","quena","quern","queso","quete","queyn","queys","queyu","quibs",
        "quich","quids","quies","quiff","quila","quilt","quims","quina","quine","quink",
        "quino","quins","quint","quipo","quips","quipu","quire","quirl","quirt","quist",
        "quits","quoad","quods","quoif","quoin","quois","quoit","quoll","quonk","quops",
        "quork","quorl","quoth","quouk","quoys","quran","qursh","quyte","raads","raake",
        "rabat","rabic","rabis","races","rache","racon","raddi","raddy","radge","radgy",
        "radif","radii","radix","radon","rafee","raffs","raffy","rafik","rafiq","rafty",
        "ragas","ragde","ragee","rager","rages","ragga","raggs","raggy","ragis","ragus",
        "rahed","rahui","raiah","raias","raike","raiks","raile","raine","rains","raird",
        "raita","raith","raits","rajah","rajas","rajes","raked","rakee","raker","rakes",
        "rakhi","rakia","rakis","rakki","raksi","rakus","rales","ralli","ralph","ramal",
        "ramee","ramen","rames","ramet","ramie","ramin","ramis","rammy","ramon","ramps",
        "ramse","ramsh","ramus","ranas","rance","rando","rands","randy","raned","ranee",
        "ranes","ranga","rangi","rangs","rangy","ranid","ranis","ranke","ranns","ranny",
        "ranse","rants","ranty","raped","rapee","raper","rapes","raphe","rapin","rappe",
        "rapso","rared","raree","rares","rarks","rasam","rasas","rased","raser","rases",
        "rasps","raspy","rasse","rasta","ratal","ratan","ratas","ratch","ratel","rater",
        "rates","ratha","rathe","raths","ratoo","ratos","ratti","ratty","ratus","rauli",
        "rauns","raupo","raved","ravel","raven","raver","raves","ravey","ravin","rawdy",
        "rawer","rawin","rawks","rawly","rawns","raxed","raxes","rayah","rayas","rayed",
        "rayle","rayls","rayne","rayon","razai","razed","razee","razer","razes","razet",
        "razoo","razor","react","readd","reais","reaks","realo","reals","reame","reamy",
        "reans","reaps","reard","rearm","rears","reast","reata","reate","reave","rebab",
        "rebar","rebbe","rebec","rebid","rebit","rebop","rebud","rebus","rebut","rebuy",
        "recal","recce","recco","reccy","recep","recit","recks","recta","recte","recti",
        "recue","recur","recut","redan","redds","reddy","reded","redes","redia","redid",
        "redif","redig","redip","redly","redon","redos","redox","redry","redub","redug",
        "redye","reeaf","reech","reede","reefy","reeks","reeky","reels","reely","reems",
        "reens","reerd","reest","reeve","reeze","refan","refed","refel","refer","reffo",
        "refis","refit","refix","refly","refry","regal","regar","reges","reget","regex",
        "reggo","regia","regie","regle","regma","regna","regos","regot","regur","rehab",
        "rehem","reifs","reify","reiki","reiks","reine","reing","reink","reird","reist",
        "reive","rejas","rejig","rejon","reked","rekes","rekey","relet","relic","relie",
        "relit","rello","relos","reman","remap","remen","remet","remex","remix","remou",
        "renay","rends","rendu","reney","renga","rengs","renig","renin","renks","renne",
        "renos","rente","rents","reoil","reorg","repas","repat","repeg","repen","repin",
        "repla","repos","repot","repps","repro","repun","reput","reran","rerig","rerun",
        "resam","resat","resaw","resay","resee","reses","reset","resew","resid","resit",
        "resod","resol","resow","resto","rests","resty","resue","resus","retag","retam",
        "retax","retch","retem","retia","retie","retin","retip","retox","retry","reune",
        "reups","revet","revie","revow","revue","rewan","rewax","rewed","rewet","rewin",
        "rewon","rewth","rexes","rezes","rhabd","rheas","rheid","rheme","rheum","rhies",
        "rhime","rhine","rhino","rhody","rhomb","rhone","rhumb","rhyme","rhymy","rhyne",
        "rhyta","riads","rials","riant","riata","riato","ribas","ribby","ribes","riced",
        "ricer","rices","ricey","riche","richt","ricin","ricks","rider","rides","ridgy",
        "ridic","riels","riems","rieve","rifer","riffs","riffy","rifte","rifts","rifty",
        "riggs","rigmo","rigol","rigor","rikka","rikwa","riled","riles","riley","rille",
        "rills","rilly","rimae","rimed","rimer","rimes","rimon","rimus","rince","rindy",
        "rines","ringe","ringy","rinks","rioja","rione","riots","rioty","riped","ripen",
        "riper","ripes","ripps","riqqs","riser","rises","rishi","risps","rists","risus",
        "rites","rithe","ritts","ritzy","rivas","rived","rivel","riven","rives","riyal",
        "rizas","roach","roady","roake","roaky","roans","roany","roary","roate","robbo",
        "robed","rober","roble","robug","robur","roche","rocks","roded","rodeo","rodes",
        "rodny","roers","rogan","roger","roguy","rohan","rohes","rohun","rohus","roids",
        "roils","roily","roins","roist","rojak","rojis","roked","roker","rokes","rokey",
        "rokos","rolag","roleo","roles","rolfs","rolly","romal","romeo","romer","romps",
        "rompu","rompy","ronde","rondo","roneo","rones","ronin","ronne","ronte","ronts",
        "ronuk","roods","roofs","roofy","rooks","rooky","roons","roops","roopy","roosa",
        "roose","roost","rooty","roped","roper","ropey","roque","roral","rores","roric",
        "rorid","rorie","rorts","rorty","rosal","rosco","rosed","roset","rosha","roshi",
        "rosin","rosit","rosps","rossa","rosso","rosti","rosts","rotal","rotan","rotas",
        "rotch","roted","rotes","rotis","rotls","roton","rotor","rotos","rotta","rotte",
        "rotto","rotty","rouen","roues","rouet","roufs","rougy","rouks","rouky","roule",
        "rouls","roums","roups","roupy","rouse","roust","routh","routs","roved","roven",
        "roves","rowan","rowed","rowel","rowen","rower","rowet","rowie","rowme","rownd",
        "rowns","rowth","rowts","royet","royne","royst","rozes","rozet","rozit","ruach",
        "ruana","rubai","ruban","rubby","rubel","rubes","rubin","rubio","ruble","rubli",
        "rubor","rubus","ruche","ruchy","rucks","rudas","rudds","ruddy","ruder","rudes",
        "rudie","rudis","rueda","ruers","ruffe","ruffs","ruffy","rufus","rugae","rugal",
        "rugas","ruggy","ruice","ruing","rukhs","rully","rumal","rumbo","rumen","rumes",
        "rumly","rummy","rumpo","rumps","rumpy","runce","runch","runds","runed","runer",
        "runes","runic","runny","runos","runts","runty","runup","ruote","rupee","rupia",
        "rurps","rurus","rusas","ruses","rushy","rusks","rusky","rusma","russe","rusts",
        "ruths","rutin","rutty","ruvid","ryals","rybat","ryiji","ryijy","ryked","rykes",
        "rymer","rymme","rynds","ryoti","ryots","ryper","rypin","rythe","ryugi","saags",
        "sabal","sabed","saber","sabes","sabha","sabin","sabir","sabji","sable","sabos",
        "sabot","sabra","sabre","sabzi","sacks","sacra","sacre","saddo","saddy","sades",
        "sadhe","sadhu","sadic","sadis","sados","sadza","saeta","safed","safes","sagar",
        "sagas","sager","sages","saggy","sagos","sagum","sahab","saheb","sahib","saice",
        "saick","saics","saids","saiga","sails","saims","saine","sains","sairs","saist",
        "saith","sajou","sakai","saker","sakes","sakia","sakis","sakti","salal","salas",
        "salat","salep","salet","salic","salis","salix","salle","sally","salmi","salol",
        "salop","salpa","salps","salse","salto","salts","salud","salue","salut","salvo",
        "saman","samas","samba","sambo","samek","samel","samen","sames","samey","samfi",
        "samfu","sammy","sampi","samps","sanad","saned","sanes","sanga","sangh","sango",
        "sangs","sanko","sansa","santo","sants","saola","sapan","sapid","sapor","sappy",
        "saran","sards","sared","saree","sarge","sargo","sarin","sarir","saris","sarks",
        "sarky","sarod","saros","sarus","sarvo","saser","sasin","sasse","sassy","satai",
        "satay","sated","satem","sater","sates","satis","satyr","sauba","sauch","saucy",
        "saugh","sauls","sault","saunf","saunt","saury","saute","sauts","sauve","saver",
        "saves","savey","savin","savoy","savvy","sawah","sawed","sawer","saxes","sayas",
        "sayed","sayee","sayer","sayid","sayne","sayon","sayst","sazes","scabs","scads",
        "scaff","scags","scail","scala","scall","scaly","scand","scans","scapa","scape",
        "scapi","scarp","scars","scart","scath","scats","scatt","scaud","scaup","scaur",
        "scaws","sceat","scena","scend","schav","schif","schmo","schul","schwa","scifi",
        "scind","scion","scire","sclim","scobe","scody","scoff","scogs","scoog","scoot",
        "scopa","scops","scorp","scote","scots","scoug","scoup","scour","scowp","scows",
        "scrab","scrae","scrag","scran","scrat","scraw","scray","scree","scrim","scrip",
        "scrob","scrod","scrog","scroo","scrow","scrum","scuba","scudi","scudo","scuds",
        "scuff","scuft","scugs","sculk","scull","sculp","sculs","scums","scups","scurf",
        "scurs","scuse","scuta","scute","scuts","scuzz","scyes","sdayn","sdein","seame",
        "seamy","seans","seare","sears","sease","seats","seaze","sebum","secco","sechs",
        "sects","sedan","seder","sedes","sedge","sedgy","sedum","seeld","seels","seely",
        "seeps","seepy","seers","sefer","segar","segas","segni","segno","segol","segos",
        "segue","sehri","seifs","seils","seine","seirs","seise","seism","seity","seiza",
        "sekos","sekts","selah","seles","selfs","selfy","selky","sella","selle","sells",
        "selva","semas","semee","semen","semes","semie","semis","senas","sends","senes",
        "senex","sengi","senna","senor","sensa","sensi","sensu","sente","senti","sents",
        "senvy","senza","sepad","sepal","sepia","sepic","sepoy","seppo","septa","septs",
        "serac","serai","seral","sered","serer","seres","serfs","serge","seria","seric",
        "serin","serir","serks","seron","serow","serra","serre","serrs","serry","serum",
        "servo","sesey","sessa","setae","setal","seter","seths","seton","setts","sevak",
        "sevir","sewan","sewar","sewed","sewel","sewen","sewer","sewin","sexed","sexer",
        "sexes","sexor","sexto","sexts","seyen","sezes","shads","shags","shahs","shaka",
        "shako","shakt","shale","shalm","shalt","shaly","shama","shams","shand","shank",
        "shans","shaps","sharn","shart","shash","shaul","shawm","shawn","shaws","shaya",
        "shays","shchi","sheaf","sheal","sheas","sheel","sheik","shend","sheng","shent",
        "sheol","sherd","shere","shero","shets","sheva","shewn","shews","shiai","shied",
        "shiel","shier","shies","shill","shily","shins","shiok","ships","shirk","shirr",
        "shirs","shish","shiso","shist","shite","shits","shiur","shiva","shive","shivs",
        "shlep","shlub","shmek","shmoe","shoal","shoat","shoed","shoer","shogi","shogs",
        "shoji","shojo","shola","shonk","shool","shoon","shoos","shope","shorl","shorn",
        "shote","shots","shott","shoud","showd","showy","shoyu","shred","shris","shrow",
        "shtar","shtik","shtum","shtup","shuba","shule","shuln","shuls","shuns","shura",
        "shush","shute","shuts","shwas","shyer","shyly","sials","sibbs","sibia","sibyl",
        "sices","sicht","sicko","sicks","sicky","sidas","sider","sides","sidey","sidha",
        "sidhe","sidle","sield","siens","sient","sieth","sieur","sieve","sifts","sighs",
        "sigil","sigla","signa","sigri","sijos","sikas","siker","sikes","silds","siled",
        "silen","siler","siles","silex","silks","sills","silos","silts","silty","silva",
        "simar","simas","simba","simis","simps","simul","sinds","sined","sines","sinew",
        "singe","sings","sinhs","sinks","sinky","sinsi","sinus","siped","sipes","sippy",
        "sired","siree","siren","sires","sirih","siris","siroc","sirra","sirup","sisal",
        "sises","sissy","sista","sists","sitar","sitch","sited","sites","sithe","sitka",
        "situp","situs","siver","sixer","sixes","sixmo","sixte","sizar","sizel","sizer",
        "skags","skail","skald","skank","skarn","skart","skats","skatt","skaws","skean",
        "skear","skeds","skeed","skeef","skeen","skeer","skees","skeet","skeev","skeez",
        "skegg","skegs","skein","skelf","skell","skelm","skelp","skene","skens","skeos",
        "skeps","skerm","skers","skets","skews","skids","skied","skies","skiey","skiff",
        "skimo","skims","skink","skint","skios","skirl","skirr","skite","skits","skive",
        "skivy","sklim","skoal","skobe","skody","skoff","skofs","skogs","skols","skool",
        "skort","skosh","skran","skrik","skroo","skuas","skugs","skulk","skunk","skyed",
        "skyer","skyey","skyfs","skyre","skyrs","skyte","slabs","slade","slaes","slags",
        "slaid","slake","slams","slane","slank","slart","slats","slaty","slaws","slays",
        "slebs","sleds","sleer","slews","sleys","slick","slier","slily","slims","slipe",
        "slips","slipt","slish","slits","slive","sloan","slobs","sloes","slogs","sloid",
        "slojd","sloka","slomo","sloom","sloop","sloot","slops","slopy","slorm","slosh",
        "slove","slows","sloyd","slubb","slubs","slued","slues","sluff","sluit","slurb",
        "slurp","slurs","sluse","slush","sluts","slyer","slyly","slype","smaak","smack",
        "smaik","smalm","smalt","smarm","smaze","smeek","smees","smeik","smeke","smerk",
        "smews","smick","smily","smirr","smirs","smite","smits","smize","smogs","smoko",
        "smolt","smoor","smoot","smore","smorg","smote","smout","smowt","smugs","smurs",
        "smush","smuts","snabs","snafu","snaky","snarf","snark","snars","snary","snash",
        "snath","snaws","snead","sneap","snebs","sneck","sneds","sneed","snees","snell",
        "snibs","snick","snied","snies","snift","snigs","snipe","snips","snipy","snirt",
        "snits","snive","snobs","snods","snoek","snoep","snogs","snoke","snood","snook",
        "snool","snoop","snoot","snots","snowk","snows","snubs","snugs","snush","snyes",
        "soaks","soaps","soare","soars","soave","sobas","socas","soces","socia","socko",
        "socle","sodas","soddy","sodic","sodom","sofar","sofas","softa","softs","softy",
        "soger","soggy","sohur","soils","soily","sojas","sojus","sokah","soken","sokes",
        "sokol","solah","solan","solas","solde","soldi","soldo","solds","soled","solei",
        "soler","soles","solon","solos","solum","solus","soman","somas","sonar","sonce",
        "sonde","sones","songo","songs","songy","sonly","sonne","sonny","sonse","sonsy",
        "sooey","sooks","sooky","soole","sools","sooms","soops","soote","sooth","soots",
        "sooty","sophs","sophy","sopor","soppy","sopra","soral","soras","sorbi","sorbo",
        "sorbs","sorda","sordo","sords","sored","soree","sorel","sorer","sores","sorex",
        "sorgo","sorns","sorra","sorta","sorts","sorus","soths","sotol","sotto","souce",
        "souct","sough","souks","souls","souly","soums","soups","soupy","sours","souse",
        "souts","sowar","sowce","sowed","sower","sowff","sowfs","sowle","sowls","sowms",
        "sownd","sowne","sowps","sowse","sowth","soxes","soyas","soyle","soyuz","sozin",
        "spack","spacy","spado","spads","spaed","spaer","spaes","spags","spahi","spail",
        "spain","spait","spake","spald","spale","spall","spalt","spams","spane","spang",
        "spank","spans","spard","spars","spart","spasm","spate","spats","spaul","spawl",
        "spaws","spayd","spays","spaza","spazz","speal","spean","speat","speck","spect",
        "speel","speer","speil","speir","speks","speld","spelk","spelt","speos","sperm",
        "spesh","spets","speug","spews","spewy","spial","spica","spick","spics","spide",
        "spiel","spier","spies","spiff","spifs","spiks","spiky","spile","spilt","spims",
        "spina","spink","spins","spiny","spire","spirt","spiry","spits","spitz","spivs",
        "splat","splay","splog","spode","spods","spoil","spoof","spook","spool","spoom",
        "spoor","spoot","spore","spork","sposa","sposh","sposo","spout","sprad","sprag",
        "sprat","spred","sprew","sprit","sprod","sprog","sprue","sprug","spuds","spued",
        "spuer","spues","spugs","spule","spume","spumy","spunk","spurn","spurs","spurt",
        "sputa","spyal","spyre","squab","squaw","squee","squeg","squib","squit","squiz",
        "srsly","stabs","stade","stags","stagy","staid","staig","stane","stang","stans",
        "staph","staps","starn","starr","stary","stats","statu","staun","stave","staws",
        "stead","stean","stear","stedd","stede","steds","steed","steek","steem","steen",
        "steez","steik","steil","stein","stela","stele","stell","steme","stend","steno",
        "stens","stent","stept","stere","stets","stews","stewy","steys","stich","stied",
        "sties","stilb","stile","stilt","stime","stims","stimy","stipa","stipe","stire",
        "stirk","stirp","stirs","stive","stivy","stoae","stoai","stoas","stoat","stobs",
        "stoep","stogs","stogy","stoit","stoln","stoma","stond","stong","stonk","stonn",
        "stook","stoor","stope","stops","stopt","stoss","stots","stott","stoun","stoup",
        "stour","stown","stowp","stows","strad","strae","strag","strak","strep","strew",
        "stria","strig","strim","strop","strow","stroy","strum","stubs","stucs","stude",
        "studs","stull","stulm","stumm","stums","stuns","stupa","stupe","sture","sturt",
        "stush","styed","styes","styli","stylo","styme","stymy","styre","styte","subah",
        "subak","subas","subby","suber","subha","succi","sucks","sucky","sucre","sudan",
        "sudds","sudor","sudsy","suede","suent","suers","suete","suets","suety","sugan",
        "sughs","sugos","suhur","suids","suing","suint","suits","sujee","sukhs","sukis",
        "sukuk","sulci","sulfa","sulfo","sulks","sulls","sully","sulph","sulus","sumac",
        "sumis","summa","sumos","sumph","sumps","sunis","sunks","sunna","sunns","sunts",
        "sunup","suona","suped","supes","supra","surah","sural","suras","surat","surds",
        "sured","surer","sures","surfs","surfy","surgy","surly","surra","sused","suses",
        "susus","sutor","sutra","sutta","swabs","swack","swads","swage","swags","swail",
        "swain","swale","swaly","swami","swamy","swang","swank","swapt","sward","sware",
        "swarf","swart","swash","swath","swats","swayl","sways","sweal","swede","sweed",
        "sweel","sweer","swees","sweir","swell","swelt","swerf","sweys","swies","swigs",
        "swile","swims","swink","swire","swish","swiss","swith","swits","swive","swizz",
        "swobs","swole","swoll","swoln","swoon","swoop","swops","swopt","sword","swots",
        "swoun","sybbe","sybil","syboe","sybow","sycee","syces","sycon","syeds","syens",
        "syker","sykes","sylis","sylph","sylva","symar","synch","syncs","synds","syned",
        "synes","synod","synth","syped","sypes","syphs","syrah","syren","sysop","sythe",
        "syver","taals","taata","tabac","taber","tabes","tabid","tabis","tabla","tabls",
        "taboo","tabor","tabos","tabun","tabus","tacan","taces","tacet","tache","tachi",
        "tacho","tachs","tacit","tacks","tacky","tacos","tacts","tadah","taels","tafia",
        "taggy","tagma","tagua","tahas","tahrs","taiga","taigs","taiko","tails","tains",
        "taira","taish","taits","tajes","takas","taker","takes","takhi","takht","takin",
        "takis","takky","talak","talaq","talar","talas","talcs","talcy","talea","taler",
        "talik","talks","talky","talls","tally","talma","talpa","taluk","talus","tamal",
        "tamas","tamer","tames","tamin","tamis","tammy","tamps","tanas","tanga","tangi",
        "tango","tangs","tanhs","tania","tanka","tanky","tanna","tansu","tansy","tante",
        "tanti","tanto","tanty","tapas","taped","tapen","taper","tapet","tapir","tapis",
        "tappa","tapus","taras","tardo","tards","tared","tares","targa","targe","tarka",
        "tarns","taroc","tarok","taros","tarot","tarps","tarre","tarry","tarse","tarsi",
        "tarte","tarts","tarty","tarzy","tasar","tasca","tased","taser","tases","tassa",
        "tasse","tasso","tasto","tatar","tater","tates","taths","tatie","tatou","tatts",
        "tatty","tatus","taube","tauld","tauon","taupe","tauts","tauty","tavah","tavas",
        "taver","tawaf","tawai","tawas","tawed","tawer","tawie","tawny","tawse","tawts",
        "taxed","taxer","taxis","taxol","taxon","taxor","taxus","tayra","tazza","tazze",
        "teade","teads","teaed","teaks","teals","teams","teary","teats","teaze","techs",
        "techy","tecta","tecum","teddy","teels","teems","teend","teene","teens","teeny",
        "teers","teets","teffs","teggs","tegua","tegus","tehee","tehrs","teiid","teils",
        "teind","teins","tekke","telae","telco","teles","telex","telia","telic","tells",
        "telly","teloi","telos","temed","temes","tempi","temps","tempt","temse","tench",
        "tendu","tenes","tenet","tenge","tenia","tenne","tenno","tenny","tenon","tents",
        "tenty","tenue","tepal","tepas","tepee","tepoy","terai","teras","terce","terek",
        "teres","terfe","terfs","terga","terne","terns","terra","terre","terry","terse",
        "terts","terza","tesla","testa","teste","testy","tetes","teths","tetra","tetri",
        "teuch","teugh","tewed","tewel","tewit","texas","texes","texta","texts","thack",
        "thagi","thaim","thale","thali","thana","thane","thang","thank","thans","thanx",
        "tharm","thars","thaws","thawt","thawy","thebe","theca","theed","theek","thees",
        "thegn","theic","thein","their","thelf","thema","thens","theor","theow","therm",
        "thesp","theta","thete","thews","thewy","thigs","thilk","thill","thine","thins",
        "thiol","thirl","thoft","thole","tholi","thong","thoro","thorp","thots","thous",
        "thowl","thrae","thraw","thrid","thrip","throb","throe","thuds","thugs","thuja",
        "thump","thunk","thurl","thuya","thyme","thymi","thymy","tians","tiare","tiars",
        "tibia","tical","ticca","ticed","tices","tichy","ticks","ticky","tiddy","tided",
        "tides","tiefs","tiffs","tifos","tifts","tiges","tigon","tikas","tikes","tikia",
        "tikis","tikka","tilak","tilde","tiler","tills","tilly","tilth","timbo","timed",
        "timon","timps","tinas","tinct","tinds","tinea","tined","tines","tinge","tings",
        "tinks","tinny","tinto","tints","tinty","tipis","tippy","tipup","tired","tires",
        "tirls","tiros","tirrs","tirth","titar","titas","titch","titer","tithe","tithi",
        "titin","titir","titis","titre","titty","titup","tiyin","tiyns","tizes","tizzy",
        "toads","toady","toaze","tocks","tocky","tocos","todde","toddy","todea","todos",
        "toeas","toffs","toffy","tofts","tofus","togae","togas","toged","toges","togue",
        "tohos","toidy","toile","toils","toing","toise","toits","toity","tokay","toked",
        "toker","tokes","tokos","tolan","tolar","tolas","toled","toles","tolly","tolts",
        "tolus","tolyl","toman","tombo","tombs","tomen","tomes","tomia","tomin","tomme",
        "tommy","tomos","tomoz","tondi","tondo","toner","tones","toney","tonga","tonic",
        "tonka","tonks","tonne","tonus","tooms","toons","toots","toped","topee","topek",
        "toper","topes","tophe","tophi","tophs","topis","topoi","topos","toppy","toque",
        "torah","toran","toras","torcs","tores","toric","torii","toros","torot","torrs",
        "torse","torsi","torsk","torso","torta","torte","torts","torus","tosas","tosed",
        "toses","toshy","tossy","tosyl","toted","totem","toter","totes","totty","touks",
        "touns","touse","tousy","touts","touze","touzy","towai","towed","towie","towno",
        "towny","towse","towsy","towts","towze","towzy","toxin","toyed","toyer","toyon",
        "toyos","tozed","tozes","tozie","trabs","trads","trady","traga","tragi","trags",
        "tragu","traik","trams","trank","tranq","trans","trant","trape","trapo","trapt",
        "trass","trats","tratt","trave","trayf","trays","treck","treed","treen","trefa",
        "treif","treks","trema","trems","tress","trest","trets","trews","treyf","treys",
        "triac","trice","tride","trier","tries","trifa","triff","trigo","trigs","trike",
        "trild","trill","trine","trins","triol","trior","trios","tripe","trips","tripy",
        "trist","troad","troak","troat","trock","trode","trods","trogs","trois","troke",
        "tromp","trona","tronc","trone","tronk","trons","trooz","tropo","trots","trove",
        "trows","troys","trued","truer","trues","trugo","trugs","trull","tryer","tryke",
        "tryma","tryps","tryst","tsade","tsadi","tsars","tsked","tsuba","tsubo","tuans",
        "tuart","tuath","tubae","tubal","tubar","tubas","tubby","tubed","tubes","tufas",
        "tuffe","tuffs","tufts","tufty","tugra","tuile","tuina","tuism","tuktu","tules",
        "tulle","tulpa","tulps","tulsi","tumid","tummy","tumps","tumpy","tunas","tunds",
        "tungs","tunic","tunny","tupek","tupik","tuple","tuque","turbo","turds","turfs",
        "turfy","turks","turme","turms","turnt","turon","turps","turrs","tushy","tusks",
        "tusky","tutee","tutes","tutti","tutty","tutus","tuxes","tuyer","twaes","twain",
        "twals","twank","twats","tways","tweel","tween","tweep","tweer","tweet","twerk",
        "twerp","twier","twill","twilt","twink","twins","twiny","twire","twirk","twirp",
        "twite","twits","twixt","twocs","twoer","twonk","twyer","tyees","tyers","tying",
        "tyiyn","tykes","tyler","tymps","tynde","tyned","tynes","typal","typed","types",
        "typey","typic","typos","typps","typto","tyran","tyred","tyres","tyros","tythe",
        "tzars","ubacs","ubity","udals","udons","udyog","ugali","ugged","uhlan","uhuru",
        "ukase","ulama","ulans","ulema","ulmin","ulmos","ulnad","ulnae","ulnar","ulnas",
        "ulpan","ulvas","ulyie","ulzie","umami","umbel","umber","umble","umbos","umbre",
        "umiac","umiak","umiaq","ummah","ummas","ummed","umped","umphs","umpie","umpty",
        "umrah","umras","unagi","unais","unapt","unarm","unary","unaus","unbag","unban",
        "unbar","unbed","unbid","unbox","uncap","unces","uncia","uncos","uncoy","uncus",
        "uncut","undam","undee","undos","undug","uneth","unfed","unfix","ungag","unget",
        "ungod","ungot","ungum","unhat","unhip","unica","unios","units","unjam","unked",
        "unket","unkey","unkid","unkut","unlap","unlaw","unlay","unled","unleg","unlet",
        "unlid","unmad","unman","unmet","unmew","unmix","unode","unold","unown","unpay",
        "unpeg","unpen","unpin","unply","unpot","unput","unred","unrid","unrig","unrip",
        "unsaw","unsay","unsee","unset","unsew","unsex","unsod","unsub","untag","untax",
        "untie","untin","unwed","unwet","unwit","unwon","unzip","upbow","upbye","updos",
        "updry","upend","upful","upjet","uplay","upled","uplit","upped","upran","uprun",
        "upsee","upsey","uptak","upter","uptie","uraei","urali","uraos","urare","urari",
        "urase","urate","urbex","urbia","urdee","ureal","ureas","uredo","ureic","ureid",
        "urena","urent","urger","urges","urial","urine","urite","urman","urnal","urned",
        "urped","ursae","ursid","urson","urubu","urupa","urvas","usens","users","useta",
        "using","usnea","usnic","usque","ustad","uster","usure","usurp","usury","uteri",
        "utero","utile","uveal","uveas","uvula","vacas","vacay","vacua","vacui","vacuo",
        "vadas","vaded","vades","vadge","vagal","vagus","vaids","vails","vaire","vairs",
        "vairy","vajra","vakas","vakil","vales","valet","valis","valli","valse","value",
        "vamps","vampy","vanda","vaned","vanes","vanga","vangs","vants","vaped","vaper",
        "vapes","vapid","varan","varas","varda","vardo","vardy","varec","vares","varia",
        "varix","varna","varus","varve","vasal","vases","vasts","vasty","vatas","vatha",
        "vatic","vatje","vatos","vatus","vauch","vaunt","vaute","vauts","vawte","vaxes",
        "veale","veals","vealy","veena","veeps","veers","veery","vegan","vegas","veges",
        "veggo","vegie","vegos","vehme","veily","veiny","velar","velds","veldt","veles",
        "vells","velum","venae","venal","venas","vends","vendu","veney","venge","venin",
        "venom","venti","vents","venus","verba","verbs","verde","verra","verre","verry",
        "versa","verso","verst","verte","verts","vertu","verve","vespa","vesta","vests",
        "vetch","veuve","veves","vexed","vexer","vexes","vexil","vezir","vials","viand",
        "vibed","vibes","vibex","vibey","vicar","viced","vices","vichy","vicus","video",
        "viers","vieux","views","viewy","vifda","viffs","vigas","vigia","vigil","vilde",
        "viler","villa","ville","villi","vills","vimen","vinal","vinas","vinca","vined",
        "viner","vines","vinew","vinho","vinic","vinny","vinos","vints","viold","viols",
        "vired","vireo","vires","virga","virge","virgo","virid","virls","virtu","virus",
        "visas","vised","vises","visie","visna","visne","vison","visto","vitae","vitas",
        "vitex","vitro","vitta","vivas","vivat","vivda","viver","vives","vivos","vivre",
        "vixen","vizir","vizor","vlast","vleis","vlies","vlogs","voars","vobla","vocab",
        "voces","voddy","vodou","vodun","voema","vogie","voici","voids","voila","voile",
        "voips","volae","volar","voled","voles","volet","volke","volks","volta","volte",
        "volti","volts","volva","volve","vomer","vomit","voted","votes","vouge","voulu",
        "vowed","vower","voxel","voxes","vozhd","vraic","vrils","vroom","vrous","vrouw",
        "vrows","vuggs","vuggy","vughs","vughy","vulgo","vulns","vutty","vygie","vying",
        "waacs","wacke","wacko","wacks","wadas","wadds","waddy","wader","wades","wadge",
        "wadis","wadts","wafer","waffs","wafts","waged","wagga","wagyu","wahay","wahey",
        "wahoo","waide","waifs","waift","wails","wains","wairs","waite","waits","waive",
        "wakas","waked","waken","waker","wakes","wakfs","waldo","walds","waled","waler",
        "wales","walie","walis","walla","wally","walty","wamed","wames","wamus","waned",
        "wanes","waney","wangs","wanks","wanky","wanle","wanly","wanna","wanta","wanty",
        "wanze","waqfs","warbs","warby","wared","wares","warez","warks","warms","warns",
        "warps","warre","warst","warts","warty","wases","washi","washy","wasms","wasps",
        "waspy","wasts","watap","watts","wauff","waugh","wauks","waulk","wauls","waurs",
        "waved","waver","wavey","wawas","wawes","wawls","waxed","waxen","waxer","waxes",
        "wayed","wazir","wazoo","weald","weals","weamb","weans","wears","webby","weber",
        "wecht","wedel","wedgy","weedy","weeis","weeke","weeks","weels","weems","weens",
        "weeny","weeps","weepy","weest","weete","weets","wefte","wefts","weids","weils",
        "weirs","weise","weize","wekas","welch","welds","welke","welks","welkt","welly",
        "welsh","welts","wembs","wench","wends","wenge","wenny","wents","werfs","weros",
        "wersh","wests","wetas","wetly","wexed","wexes","whamo","whams","whang","whaps",
        "whare","wharf","whata","whats","whaup","whaur","wheal","whear","wheek","wheen",
        "wheep","wheft","whelk","whelm","whelp","whens","whets","whews","wheys","whids",
        "whies","whiff","whift","whigs","whilk","whims","whins","whios","whipt","whirr",
        "whirs","whish","whisk","whiss","whist","whits","whity","whizz","whomp","whoof",
        "whoop","whoot","whops","whore","whorl","whort","whoso","whows","whump","whups",
        "whyda","wicca","wicks","wicky","widdy","wides","wiels","wifed","wifes","wifey",
        "wifie","wifts","wifty","wigan","wigga","wiggy","wight","wikis","wilco","wilds",
        "wiled","wiles","wilga","wilis","wilja","wills","willy","wilts","wimps","wimpy",
        "wince","winch","wined","winey","winge","wingy","winks","winky","winna","winns",
        "winos","winze","wiper","wipes","wirer","wirra","wirri","wised","wiser","wises",
        "wisha","wisht","wisps","wispy","wists","witan","wited","wites","withe","withs",
        "withy","witty","wived","wiver","wives","wizen","wizes","wizzo","woads","woady",
        "woald","wocks","wodge","wodgy","woful","wojus","woken","woker","wokka","wolds",
        "wolfs","wolly","wolve","womas","wombs","womby","womyn","wonga","wongi","wonks",
        "wonky","wonts","woods","woody","wooed","wooer","woofs","woofy","woold","wools",
        "wooly","woons","woops","woopy","woose","woosh","wootz","woozy","wordy","works",
        "worky","wormy","worts","woven","wowed","wowee","wowse","woxen","wrack","wrang",
        "wrapt","wrast","wrate","wrawl","wreak","wrens","wrest","wrick","wried","wrier",
        "wries","wring","write","writs","wroke","wrong","wroot","wroth","wrung","wryer",
        "wryly","wuddy","wudus","wuffs","wulls","wunga","wurst","wuses","wushu","wussy",
        "wuxia","wyled","wyles","wynds","wynns","wyted","wytes","wythe","xebec","xenia",
        "xenic","xenon","xeric","xerox","xerus","xoana","xolos","xrays","xviii","xylan",
        "xylem","xylic","xylol","xylyl","xysti","xysts","yaars","yaass","yabas","yabba",
        "yabby","yacca","yacka","yacks","yadda","yaffs","yager","yages","yagis","yagna",
        "yahoo","yaird","yajna","yakka","yakow","yales","yamen","yampa","yampy","yamun",
        "yandy","yangs","yanks","yapok","yapon","yapps","yappy","yarak","yarco","yards",
        "yarer","yarfa","yarks","yarns","yarra","yarrs","yarta","yarto","yates","yatra",
        "yauds","yauld","yaups","yawed","yawey","yawls","yawns","yawny","yawps","yayas",
        "ybore","yclad","ycled","ycond","ydrad","ydred","yeads","yeahs","yealm","yeans",
        "yeard","yecch","yechs","yechy","yedes","yeeds","yeeek","yeesh","yeggs","yelks",
        "yells","yelms","yelps","yelts","yenta","yente","yerba","yerds","yerks","yeses",
        "yesks","yests","yesty","yetis","yetts","yeuch","yeuks","yeuky","yeven","yeves",
        "yewen","yexed","yexes","yfere","yiked","yikes","yills","yince","yipes","yippy",
        "yirds","yirks","yirrs","yirth","yites","yitie","ylems","ylide","ylids","ylike",
        "ylkes","ymolt","ympes","yobbo","yobby","yocks","yodel","yodhs","yodle","yogas",
        "yogee","yoghs","yogic","yogin","yogis","yohah","yohay","yoick","yojan","yokan",
        "yoked","yokeg","yokel","yoker","yokes","yokul","yolks","yolky","yolps","yomim",
        "yomps","yonic","yonis","yonks","yonny","yoofs","yoops","yopos","yoppo","yores",
        "yorga","yorks","yorps","youks","yourn","yours","yourt","youse","yowed","yowes",
        "yowie","yowls","yowsa","yowza","yoyos","yrapt","yrent","yrivd","yrneh","ysame",
        "ytost","yuans","yucas","yucca","yucch","yucko","yucks","yucky","yufts","yugas",
        "yuked","yukes","yukky","yukos","yulan","yules","yummo","yummy","yumps","yupon",
        "yuppy","yurta","yurts","yuzus","zabra","zacks","zaida","zaide","zaidy","zaire",
        "zakat","zamac","zamak","zaman","zambo","zamia","zamis","zanja","zante","zanza",
        "zanze","zappy","zarda","zarfs","zaris","zatis","zawns","zaxes","zayde","zayin",
        "zazen","zeals","zebec","zebub","zebus","zedas","zeera","zeins","zendo","zerda",
        "zerks","zeros","zests","zetas","zexes","zezes","zhomo","zhush","zhuzh","zibet",
        "ziffs","zigan","zikrs","zilas","zilch","zilla","zills","zimbi","zimbs","zinco",
        "zincs","zincy","zineb","zines","zings","zingy","zinke","zinky","zinos","zippo",
        "zippy","ziram","zitis","zitty","zizel","zizit","zlote","zloty","zoaea","zobos",
        "zobus","zocco","zoeae","zoeal","zoeas","zoism","zoist","zokor","zolle","zombi",
        "zonae","zonal","zonda","zoned","zoner","zonks","zooea","zooey","zooid","zooks",
        "zooms","zoomy","zoons","zooty","zoppa","zoppo","zoril","zoris","zorro","zorse",
        "zouks","zowee","zowie","zulus","zupan","zupas","zuppa","zurfs","zuzim","zygal",
        "zygon","zymes","zymic"
    ]
}

// MARK: - Wordle Settings

struct WordleSettingsView: View {
    @ObservedObject var vm: BlissViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Difficulty")
            Text("Number of guesses allowed")
                .font(.caption)
                .foregroundColor(.secondary)
            Picker("", selection: Binding(
                get: { vm.wordleDifficulty },
                set: { vm.setWordleDifficulty($0) }
            )) {
                ForEach(WordleDifficulty.allCases, id: \.self) { diff in
                    Text(diff.displayName).tag(diff)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

struct WordleWizardConfigView: View {
    @EnvironmentObject var wizardState: SetupWizardState

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Wordle Difficulty")
                    .font(.title2.weight(.semibold))
                Text("How many guesses do you get?")
                    .foregroundColor(.secondary)
            }

            VStack(spacing: 8) {
                WizardOptionCard(title: "Easy", subtitle: "6 guesses", selected: wizardState.wordleDifficulty == .easy) { wizardState.wordleDifficulty = .easy }
                WizardOptionCard(title: "Medium", subtitle: "5 guesses", selected: wizardState.wordleDifficulty == .medium) { wizardState.wordleDifficulty = .medium }
                WizardOptionCard(title: "Hard", subtitle: "4 guesses", selected: wizardState.wordleDifficulty == .hard) { wizardState.wordleDifficulty = .hard }
            }
        }
    }
}
