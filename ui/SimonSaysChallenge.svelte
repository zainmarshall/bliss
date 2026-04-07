<script>
  import { onMount, onDestroy } from "svelte";

  let { onSuccess, onCancel } = $props();

  function getConfig() {
    try {
      let c = JSON.parse(localStorage.getItem("bliss_panic_configs") || "{}");
      let d = c.simon_difficulty || "medium";
      let configs = { easy: { grid: 3, seq: 5 }, medium: { grid: 4, seq: 7 }, hard: { grid: 5, seq: 10 } };
      return configs[d] || configs.medium;
    } catch { return { grid: 4, seq: 7 }; }
  }

  let cfg = getConfig();
  const GRID_SIZE = cfg.grid;
  const SEQ_LENGTH = cfg.seq;

  const cellColors = [
    "#e64d4d", "#3399db", "#4db04f", "#ffc107",
    "#9c27b0", "#ff9800", "#00bcd4", "#e91e90",
    "#795548", "#8bc34a", "#607d8b", "#ff5722",
    "#3f51b5", "#cddc39", "#009688", "#f44336",
  ];

  let sequence = $state([]);
  let playerIndex = $state(0);
  let phase = $state("watching"); // watching | playing | wrong | won
  let highlightedCell = $state(null); // "r,c"
  let submitting = $state(false);
  let playbackTimeout = $state(null);

  function initGame() {
    sequence = Array.from({ length: SEQ_LENGTH }, () => [
      Math.floor(Math.random() * GRID_SIZE),
      Math.floor(Math.random() * GRID_SIZE),
    ]);
    playerIndex = 0;
    phase = "watching";
    highlightedCell = null;
    playSequence();
  }

  async function playSequence() {
    phase = "watching";
    highlightedCell = null;
    await sleep(500);
    for (let [r, c] of sequence) {
      highlightedCell = `${r},${c}`;
      await sleep(600);
      highlightedCell = null;
      await sleep(200);
    }
    phase = "playing";
  }

  function sleep(ms) {
    return new Promise(resolve => {
      playbackTimeout = setTimeout(resolve, ms);
    });
  }

  function tap(r, c) {
    if (phase !== "playing" || playerIndex >= sequence.length) return;
    let [er, ec] = sequence[playerIndex];
    if (r === er && c === ec) {
      highlightedCell = `${r},${c}`;
      playerIndex++;
      setTimeout(() => { highlightedCell = null; }, 150);
      if (playerIndex === SEQ_LENGTH) {
        phase = "won";
        handleWin();
      }
    } else {
      phase = "wrong";
      setTimeout(() => {
        playerIndex = 0;
        playSequence();
      }, 1000);
    }
  }

  async function handleWin() {
    submitting = true;
    await onSuccess();
    submitting = false;
  }

  function colorForCell(r, c) {
    return cellColors[(r * GRID_SIZE + c) % cellColors.length];
  }

  function isHighlighted(r, c) {
    return highlightedCell === `${r},${c}`;
  }

  onMount(initGame);

  onDestroy(() => {
    if (playbackTimeout) clearTimeout(playbackTimeout);
  });
</script>

<div class="panic-view">
  <div class="panic-card">
    <div class="panic-header">
      <h2>Simon Says</h2>
      <p class="subtitle">Watch the sequence, then repeat it from memory.</p>
    </div>

    <div class="info-row">
      <span class="phase-text">
        {#if phase === "watching"}
          Watch the sequence...
        {:else if phase === "playing"}
          Your turn - tap the cells in order
        {:else if phase === "wrong"}
          <span class="wrong-text">Wrong! Watch again...</span>
        {:else if phase === "won"}
          <span class="won-text">Correct!</span>
        {/if}
      </span>
      <span class="progress">{playerIndex}/{SEQ_LENGTH}</span>
    </div>

    <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions -->
    <div class="grid" style="grid-template-columns: repeat({GRID_SIZE}, 1fr)">
      {#each Array(GRID_SIZE) as _, r}
        {#each Array(GRID_SIZE) as _, c}
          <div
            class="cell"
            class:highlighted={isHighlighted(r, c)}
            class:dim={phase === "watching" && !isHighlighted(r, c)}
            style="background: {colorForCell(r, c)}"
            onclick={() => tap(r, c)}
          >
          </div>
        {/each}
      {/each}
    </div>

    <div class="actions">
      {#if phase === "won" && submitting}
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
    max-width: 380px;
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 14px;
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

  .info-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    width: 100%;
    font-size: 13px;
    color: #888;
  }

  .wrong-text { color: #ef4444; }
  .won-text { color: #4ade80; }

  .progress {
    font-variant-numeric: tabular-nums;
    font-size: 12px;
  }

  .grid {
    display: grid;
    gap: 8px;
    width: 100%;
    max-width: 320px;
  }

  .cell {
    aspect-ratio: 1;
    border-radius: 10px;
    cursor: pointer;
    transition: opacity 0.15s, transform 0.15s, box-shadow 0.15s;
    opacity: 0.65;
  }

  .cell:hover {
    opacity: 0.85;
    transform: scale(1.03);
  }

  .cell.highlighted {
    opacity: 1;
    transform: scale(1.08);
    box-shadow: 0 0 20px rgba(255, 255, 255, 0.3);
  }

  .cell.dim {
    opacity: 0.35;
    cursor: default;
  }

  .actions {
    display: flex;
    align-items: center;
    justify-content: flex-start;
    width: 100%;
    min-height: 32px;
  }

  .cancel-btn {
    padding: 6px 16px;
    font-size: 13px;
    background: none;
    color: #888;
    border: 1px solid #333;
    border-radius: 6px;
    cursor: pointer;
    transition: border-color 0.15s;
  }

  .cancel-btn:hover {
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
