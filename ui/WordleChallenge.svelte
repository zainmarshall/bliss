<script>
  import { onMount } from "svelte";

  let { onSuccess, onCancel } = $props();

  function getConfig() {
    try {
      let c = JSON.parse(localStorage.getItem("bliss_panic_configs") || "{}");
      let d = c.wordle_difficulty || "easy";
      return { easy: 6, medium: 5, hard: 4 }[d] || 6;
    } catch { return 6; }
  }

  const WORD_LENGTH = 5;
  const MAX_GUESSES = getConfig();

  const answers = [
    "about","above","abuse","actor","acute","admit","adopt","adult","after","again",
    "agent","agree","ahead","alarm","album","alert","alien","align","alive","alley",
    "allow","alone","along","alter","among","angel","anger","angle","angry","ankle",
    "apart","apple","apply","arena","argue","arise","armor","array","arrow","aside",
    "asset","atlas","audio","audit","avoid","awake","award","aware","bacon","badge",
    "badly","baker","basic","basin","basis","batch","beach","beard","beast","begun",
    "being","below","bench","berry","bible","birth","black","blade","blame","bland",
    "blank","blast","blaze","bleed","blend","bless","blind","blink","bliss","block",
    "blood","bloom","blown","board","boast","bonus","booth","bound","brain","brand",
    "brave","bread","break","breed","brick","bride","brief","bring","broad","broke",
    "brook","brush","buddy","build","bunch","burst","buyer","cabin","cable","camel",
    "candy","cargo","carry","catch","cause","cedar","chain","chair","chalk","champ",
    "chaos","charm","chart","chase","cheap","check","cheek","cheer","chess","chest",
    "chief","child","chill","china","choir","chunk","civil","claim","clash","class",
    "clean","clear","clerk","click","cliff","climb","cling","clock","clone","close",
    "cloth","cloud","coach","coast","color","comet","comic","coral","couch","could",
    "count","court","cover","crack","craft","crane","crash","crazy","cream","creek",
    "creep","crime","crisp","cross","crowd","crown","cruel","crush","cubic","curve",
    "cycle","daily","dance","dealt","debug","decay","decoy","decor","delay","delta",
    "demon","dense","depot","depth","derby","devil","diary","dirty","disco","ditch",
    "dodge","doing","donor","doubt","dough","draft","drain","drama","drank","drape",
    "drawn","dream","dress","dried","drift","drill","drink","drive","drone","drown",
    "dryer","dying","eager","eagle","early","earth","eight","elder","elect","elite",
    "email","ember","empty","enemy","enjoy","enter","entry","equal","equip","error",
    "essay","event","every","exact","exile","exist","extra","fable","faith","false",
    "fancy","fatal","fault","feast","fence","fiber","field","fifth","fifty","fight",
    "final","first","fixed","flame","flash","flask","flesh","flick","fling","float",
    "flock","flood","floor","flora","flour","fluid","flute","focal","focus","force",
    "forge","forth","forum","found","frame","frank","fraud","fresh","front","frost",
    "fruit","fully","funny","ghost","giant","given","glass","gleam","globe","gloom",
    "glory","gloss","glove","going","grace","grade","grain","grand","grant","graph",
    "grasp","grass","grave","great","green","greet","grief","grill","grind","gross",
    "group","grove","grown","guard","guess","guest","guide","guild","guilt","quest",
    "quiet","quite","quote","habit","happy","harsh","haven","heart","heavy","hedge",
    "hence","honor","horse","hotel","house","human","humor","ideal","image","imply",
    "index","indie","inner","input","ivory","jewel","joint","joker","judge","juice",
    "juicy","knife","knock","known","label","labor","layer","learn","lease","leave",
    "legal","lemon","level","light","limit","liner","logic","loose","lover","lower",
    "loyal","lunar","lunch","magic","major","maker","manor","maple","march","match",
    "maybe","mayor","medal","media","mercy","merge","merit","metal","meter","might",
    "miner","minor","minus","model","money","month","moral","motel","motor","mount",
    "mouse","mouth","movie","music","night","noble","noise","north","noted","novel",
    "nurse","ocean","offer","often","olive","opera","orbit","order","organ","other",
    "outer","owner","oxide","ozone","paint","panel","paper","paste","patch","pause",
    "peace","peach","pearl","penny","phase","phone","photo","piano","piece","pilot",
    "pinch","pitch","pixel","pizza","place","plain","plane","plant","plate","plaza",
    "plead","plumb","plume","plump","point","polar","polka","pound","power","press",
    "price","pride","prime","prince","print","prior","prize","probe","proof","proud",
    "prove","proxy","pulse","punch","pupil","purse","queen","query","quick","radar",
    "radio","raise","rally","ranch","range","rapid","ratio","reach","ready","rebel",
    "reign","relax","relay","renal","renew","repay","reply","rider","ridge","rifle",
    "right","rigid","rival","river","robot","rocky","roger","roman","rough","round",
    "route","royal","rugby","ruler","rumor","rural","salad","sauce","scale","scare",
    "scene","scent","scope","score","scout","screw","seize","sense","serve","seven",
    "sever","shade","shake","shall","shame","shape","share","shark","sharp","sheep",
    "sheer","sheet","shelf","shell","shift","shine","shirt","shock","shoot","shore",
    "short","shout","sight","silly","since","sixth","sixty","skate","skill","skull",
    "slash","slave","sleep","slice","slide","slope","smart","smell","smile","smoke",
    "snake","solar","solid","solve","sonic","sorry","sound","south","space","spare",
    "spark","speak","spear","speed","spell","spend","spice","spill","spine","spite",
    "split","spoke","spoon","sport","spray","squad","stack","staff","stage","stain",
    "stair","stake","stale","stall","stamp","stand","stare","start","state","steak",
    "steal","steam","steel","steep","steer","stern","stick","stiff","still","stock",
    "stone","stood","store","storm","story","stove","strap","straw","strip","stuck",
    "stuff","style","sugar","suite","super","surge","swamp","swear","sweep","sweet",
    "swept","swift","swing","sword","syrup","table","taste","teach","teeth","tempo",
    "thank","theme","thick","thing","think","third","thorn","those","three","throw",
    "thumb","tiger","tight","timer","tired","title","toast","today","token","topic",
    "total","touch","tough","tower","toxic","trace","track","trade","trail","train",
    "trait","trash","treat","trend","trial","tribe","trick","troop","truck","truly",
    "trump","trunk","trust","truth","tumor","twist","ultra","uncle","under","union",
    "unite","unity","until","upper","upset","urban","usage","usual","valid","value",
    "valve","vapor","vault","video","vigor","vinyl","viral","virus","visit","vista",
    "vital","vivid","vocal","vodka","voice","voter","waist","waste","watch","water",
    "weave","weigh","weird","wheat","wheel","where","which","while","white","whole",
    "whose","width","witch","woman","world","worry","worst","worth","wound","wrath",
    "write","wrong","wrote","yacht","young","youth","zones",
  ];

  let answer = $state("");
  let guesses = $state([]);
  let currentRow = $state(0);
  let currentCol = $state(0);
  let won = $state(false);
  let gameOver = $state(false);
  let keyStates = $state({});
  let shakeRow = $state(-1);
  let submitting = $state(false);

  const keyboardRows = [
    ["Q","W","E","R","T","Y","U","I","O","P"],
    ["A","S","D","F","G","H","J","K","L"],
    ["ENTER","Z","X","C","V","B","N","M","DEL"],
  ];

  function initGame() {
    answer = answers[Math.floor(Math.random() * answers.length)].toUpperCase();
    guesses = Array.from({ length: MAX_GUESSES }, () =>
      Array.from({ length: WORD_LENGTH }, () => ({ ch: "", state: "empty" }))
    );
    currentRow = 0;
    currentCol = 0;
    won = false;
    gameOver = false;
    keyStates = {};
    shakeRow = -1;
  }

  function typeLetter(ch) {
    if (gameOver || currentCol >= WORD_LENGTH) return;
    guesses[currentRow][currentCol].ch = ch;
    currentCol++;
  }

  function deleteLetter() {
    if (gameOver || currentCol <= 0) return;
    currentCol--;
    guesses[currentRow][currentCol].ch = "";
    guesses[currentRow][currentCol].state = "empty";
  }

  function submitGuess() {
    if (gameOver || currentCol !== WORD_LENGTH) return;
    let word = guesses[currentRow].map(g => g.ch).join("").toLowerCase();
    // Check if it's a valid word (in our answer list or 5 alpha chars)
    if (!answers.includes(word) && !/^[a-z]{5}$/.test(word)) {
      shakeRow = currentRow;
      setTimeout(() => { shakeRow = -1; }, 500);
      return;
    }

    let answerChars = answer.split("");
    let guessChars = word.toUpperCase().split("");
    let remaining = {};
    for (let ch of answerChars) remaining[ch] = (remaining[ch] || 0) + 1;

    // First pass: correct
    for (let i = 0; i < WORD_LENGTH; i++) {
      if (guessChars[i] === answerChars[i]) {
        guesses[currentRow][i].state = "correct";
        remaining[guessChars[i]]--;
      }
    }

    // Second pass: misplaced/absent
    for (let i = 0; i < WORD_LENGTH; i++) {
      if (guesses[currentRow][i].state === "correct") continue;
      if ((remaining[guessChars[i]] || 0) > 0) {
        guesses[currentRow][i].state = "misplaced";
        remaining[guessChars[i]]--;
      } else {
        guesses[currentRow][i].state = "absent";
      }
    }

    // Update keyboard
    for (let i = 0; i < WORD_LENGTH; i++) {
      let ch = guessChars[i];
      let newState = guesses[currentRow][i].state;
      let old = keyStates[ch];
      let rank = { empty: 0, absent: 1, misplaced: 2, correct: 3 };
      if (!old || rank[newState] > rank[old]) {
        keyStates[ch] = newState;
      }
    }

    if (guesses[currentRow].every(g => g.state === "correct")) {
      won = true;
      gameOver = true;
      handleWin();
    } else if (currentRow === MAX_GUESSES - 1) {
      gameOver = true;
    } else {
      currentRow++;
      currentCol = 0;
    }
  }

  function handleKeyboard(ch) {
    if (ch === "ENTER") submitGuess();
    else if (ch === "DEL") deleteLetter();
    else typeLetter(ch);
  }

  function handleKeydown(e) {
    if (e.key === "Enter") { e.preventDefault(); submitGuess(); }
    else if (e.key === "Backspace") deleteLetter();
    else if (/^[a-zA-Z]$/.test(e.key)) typeLetter(e.key.toUpperCase());
  }

  async function handleWin() {
    submitting = true;
    await onSuccess();
    submitting = false;
  }

  onMount(initGame);
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="panic-view">
  <div class="panic-card">
    <div class="panic-header">
      <h2>Wordle</h2>
      <p class="subtitle">Guess the 5-letter word in {MAX_GUESSES} tries.</p>
    </div>

    <div class="board">
      {#each guesses as row, r}
        <div class="row" class:shake={shakeRow === r}>
          {#each row as cell, c}
            <div class="tile {cell.state}" class:current={r === currentRow && c === currentCol && !gameOver}>
              {cell.ch}
            </div>
          {/each}
        </div>
      {/each}
    </div>

    <div class="keyboard">
      {#each keyboardRows as row}
        <div class="kb-row">
          {#each row as key}
            <button
              class="key {keyStates[key] || ''}"
              class:wide={key === "ENTER" || key === "DEL"}
              onclick={() => handleKeyboard(key)}
            >
              {key}
            </button>
          {/each}
        </div>
      {/each}
    </div>

    <div class="actions">
      {#if gameOver && !won}
        <span class="result-text error">The word was {answer}</span>
        <button class="retry-btn" onclick={initGame}>Try Again</button>
      {:else if won && submitting}
        <span class="result-text success">Correct!</span>
        <span class="spinner"></span>
      {:else}
        <button class="cancel-btn" onclick={onCancel}>Cancel</button>
      {/if}
    </div>
  </div>
</div>

<style>
  .panic-view {
    height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    padding: 24px;
  }

  .panic-card {
    max-width: 400px;
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 16px;
    align-items: center;
  }

  .panic-header {
    width: 100%;
  }

  .panic-header h2 {
    font-size: 18px;
    font-weight: 600;
    margin: 0;
    color: #e0e0e0;
  }

  .subtitle {
    font-size: 13px;
    color: #888;
    margin: 4px 0 0;
  }

  .board {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .row {
    display: flex;
    gap: 6px;
  }

  .row.shake {
    animation: shake 0.4s ease;
  }

  @keyframes shake {
    0%, 100% { transform: translateX(0); }
    20% { transform: translateX(-6px); }
    40% { transform: translateX(6px); }
    60% { transform: translateX(-4px); }
    80% { transform: translateX(4px); }
  }

  .tile {
    width: 52px;
    height: 52px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 22px;
    font-weight: 700;
    border-radius: 6px;
    text-transform: uppercase;
    transition: background 0.2s, border-color 0.2s;
    border: 2px solid #333;
    color: #e0e0e0;
    background: transparent;
  }

  .tile.current {
    border-color: #666;
  }

  .tile.correct {
    background: #538d4e;
    border-color: #538d4e;
  }

  .tile.misplaced {
    background: #b59f3b;
    border-color: #b59f3b;
  }

  .tile.absent {
    background: #3a3a3c;
    border-color: #3a3a3c;
  }

  .keyboard {
    display: flex;
    flex-direction: column;
    gap: 6px;
    width: 100%;
  }

  .kb-row {
    display: flex;
    justify-content: center;
    gap: 4px;
  }

  .key {
    padding: 10px 6px;
    min-width: 30px;
    font-size: 12px;
    font-weight: 600;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    background: #555;
    color: #e0e0e0;
    transition: background 0.15s;
  }

  .key:hover {
    filter: brightness(1.15);
  }

  .key.wide {
    min-width: 52px;
    font-size: 11px;
  }

  .key.correct { background: #538d4e; }
  .key.misplaced { background: #b59f3b; }
  .key.absent { background: #2a2a2a; color: #666; }

  .actions {
    display: flex;
    align-items: center;
    justify-content: space-between;
    width: 100%;
    min-height: 32px;
  }

  .result-text {
    font-size: 14px;
    font-weight: 500;
  }

  .result-text.error { color: #ef4444; }
  .result-text.success { color: #4ade80; }

  .cancel-btn, .retry-btn {
    padding: 6px 16px;
    font-size: 13px;
    background: none;
    color: #888;
    border: 1px solid #333;
    border-radius: 6px;
    cursor: pointer;
    transition: border-color 0.15s;
  }

  .cancel-btn:hover, .retry-btn:hover {
    border-color: #555;
  }

  .spinner {
    display: inline-block;
    width: 14px;
    height: 14px;
    border: 2px solid #444;
    border-top-color: #e0e0e0;
    border-radius: 50%;
    animation: spin 0.6s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }
</style>
