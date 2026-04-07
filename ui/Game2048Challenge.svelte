<script>
  import { onMount } from "svelte";

  let { onSuccess, onCancel } = $props();

  function getConfig() {
    try {
      let c = JSON.parse(localStorage.getItem("bliss_panic_configs") || "{}");
      let d = c["2048_difficulty"] || "medium";
      return { easy: 128, medium: 512, hard: 2048 }[d] || 512;
    } catch { return 512; }
  }

  const TARGET = getConfig();
  let grid = $state(Array.from({ length: 4 }, () => Array(4).fill(0)));
  let score = $state(0);
  let won = $state(false);
  let gameOver = $state(false);
  let submitting = $state(false);

  function initGame() {
    grid = Array.from({ length: 4 }, () => Array(4).fill(0));
    score = 0;
    won = false;
    gameOver = false;
    spawnTile();
    spawnTile();
  }

  function spawnTile() {
    let empty = [];
    for (let r = 0; r < 4; r++)
      for (let c = 0; c < 4; c++)
        if (grid[r][c] === 0) empty.push([r, c]);
    if (empty.length === 0) return;
    let [r, c] = empty[Math.floor(Math.random() * empty.length)];
    grid[r][c] = Math.random() < 0.9 ? 2 : 4;
  }

  function mergeRow(row) {
    let compact = row.filter(v => v !== 0);
    let result = [];
    let i = 0;
    while (i < compact.length) {
      if (i + 1 < compact.length && compact[i] === compact[i + 1]) {
        let merged = compact[i] * 2;
        result.push(merged);
        score += merged;
        if (merged >= TARGET) won = true;
        i += 2;
      } else {
        result.push(compact[i]);
        i++;
      }
    }
    while (result.length < 4) result.push(0);
    return result;
  }

  function move(dir) {
    if (gameOver || won) return;
    let prev = grid.map(r => [...r]);

    if (dir === "left") {
      for (let r = 0; r < 4; r++) grid[r] = mergeRow(grid[r]);
    } else if (dir === "right") {
      for (let r = 0; r < 4; r++) grid[r] = mergeRow([...grid[r]].reverse()).reverse();
    } else if (dir === "up") {
      for (let c = 0; c < 4; c++) {
        let col = [0,1,2,3].map(r => grid[r][c]);
        let merged = mergeRow(col);
        for (let r = 0; r < 4; r++) grid[r][c] = merged[r];
      }
    } else if (dir === "down") {
      for (let c = 0; c < 4; c++) {
        let col = [0,1,2,3].map(r => grid[r][c]).reverse();
        let merged = mergeRow(col).reverse();
        for (let r = 0; r < 4; r++) grid[r][c] = merged[r];
      }
    }

    let changed = false;
    for (let r = 0; r < 4; r++)
      for (let c = 0; c < 4; c++)
        if (grid[r][c] !== prev[r][c]) changed = true;

    if (changed) {
      spawnTile();
      if (!won && !hasMovesAvailable()) gameOver = true;
      if (won) handleWin();
    }
  }

  function hasMovesAvailable() {
    for (let r = 0; r < 4; r++)
      for (let c = 0; c < 4; c++) {
        if (grid[r][c] === 0) return true;
        if (c + 1 < 4 && grid[r][c] === grid[r][c + 1]) return true;
        if (r + 1 < 4 && grid[r][c] === grid[r + 1][c]) return true;
      }
    return false;
  }

  function handleKeydown(e) {
    let map = { ArrowLeft: "left", ArrowRight: "right", ArrowUp: "up", ArrowDown: "down" };
    if (map[e.key]) {
      e.preventDefault();
      move(map[e.key]);
    }
  }

  async function handleWin() {
    submitting = true;
    await onSuccess();
    submitting = false;
  }

  const tileColors = {
    0: "transparent",
    2: "#776e65", 4: "#776e65", 8: "#f9f6f2", 16: "#f9f6f2",
    32: "#f9f6f2", 64: "#f9f6f2", 128: "#f9f6f2", 256: "#f9f6f2",
    512: "#f9f6f2", 1024: "#f9f6f2", 2048: "#f9f6f2",
  };

  const tileBgs = {
    0: "#2a2a2a",
    2: "#eee4da", 4: "#ede0c8", 8: "#f2b179", 16: "#f59563",
    32: "#f67c5f", 64: "#f65e3b", 128: "#edcf72", 256: "#edcc61",
    512: "#edc850", 1024: "#edc53f", 2048: "#edc22e",
  };

  function tileColor(v) { return tileColors[v] || "#f9f6f2"; }
  function tileBg(v) { return tileBgs[v] || "#3c3a32"; }
  function tileFontSize(v) {
    if (v >= 1024) return "20px";
    if (v >= 128) return "24px";
    return "28px";
  }

  onMount(initGame);
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="panic-view">
  <div class="panic-card">
    <div class="panic-header">
      <div class="header-row">
        <div>
          <h2>2048</h2>
          <p class="subtitle">Use arrow keys to merge tiles. Reach {TARGET} to unlock.</p>
        </div>
        <div class="score-box">
          <span class="score-label">Score</span>
          <span class="score-value">{score}</span>
        </div>
      </div>
    </div>

    <div class="board">
      {#each grid as row, r}
        {#each row as val, c}
          <div
            class="tile"
            style="background: {tileBg(val)}; color: {tileColor(val)}; font-size: {tileFontSize(val)}"
          >
            {#if val > 0}{val}{/if}
          </div>
        {/each}
      {/each}
    </div>

    <div class="actions">
      {#if gameOver && !won}
        <span class="result-text error">No more moves!</span>
        <button class="retry-btn" onclick={initGame}>Try Again</button>
      {:else if won && submitting}
        <span class="result-text success">You reached {TARGET}!</span>
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
    max-width: 420px;
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 16px;
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

  .header-row {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
  }

  .score-box {
    display: flex;
    flex-direction: column;
    align-items: center;
    background: rgba(255, 255, 255, 0.06);
    border-radius: 6px;
    padding: 6px 16px;
  }

  .score-label {
    font-size: 11px;
    color: #888;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .score-value {
    font-size: 20px;
    font-weight: 700;
    color: #e0e0e0;
    font-variant-numeric: tabular-nums;
  }

  .board {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 8px;
    background: #1e1e1e;
    border-radius: 10px;
    padding: 8px;
  }

  .tile {
    aspect-ratio: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 6px;
    font-weight: 800;
    font-family: "SF Pro Rounded", -apple-system, sans-serif;
    transition: background 0.1s;
  }

  .actions {
    display: flex;
    align-items: center;
    justify-content: space-between;
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
