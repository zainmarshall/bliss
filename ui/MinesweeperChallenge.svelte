<script>
  import { onMount } from "svelte";

  let { onSuccess, onCancel } = $props();

  function getConfig() {
    try {
      let c = JSON.parse(localStorage.getItem("bliss_panic_configs") || "{}");
      return c.minesweeper_size || "medium";
    } catch { return "medium"; }
  }

  let size = getConfig();
  let sizes = { small: { rows: 8, cols: 8, mines: 10 }, medium: { rows: 10, cols: 10, mines: 15 }, large: { rows: 14, cols: 14, mines: 30 } };
  let { rows, cols, mines: mineCount } = $derived(sizes[size] || sizes.medium);
  let grid = $state([]);
  let gameOver = $state(false);
  let won = $state(false);
  let firstClick = $state(true);
  let submitting = $state(false);
  let flagCount = $derived(grid.flat().filter(c => c.flagged).length);

  function initGrid() {
    grid = Array.from({ length: rows }, () =>
      Array.from({ length: cols }, () => ({
        mine: false, revealed: false, flagged: false, adjacent: 0
      }))
    );
    gameOver = false;
    won = false;
    firstClick = true;
  }

  function placeMines(safeR, safeC) {
    let placed = 0;
    while (placed < mineCount) {
      let r = Math.floor(Math.random() * rows);
      let c = Math.floor(Math.random() * cols);
      if (Math.abs(r - safeR) <= 1 && Math.abs(c - safeC) <= 1) continue;
      if (grid[r][c].mine) continue;
      grid[r][c].mine = true;
      placed++;
    }
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        if (grid[r][c].mine) continue;
        let count = 0;
        for (let dr = -1; dr <= 1; dr++) {
          for (let dc = -1; dc <= 1; dc++) {
            let nr = r + dr, nc = c + dc;
            if (nr >= 0 && nr < rows && nc >= 0 && nc < cols && grid[nr][nc].mine) count++;
          }
        }
        grid[r][c].adjacent = count;
      }
    }
  }

  function reveal(r, c) {
    if (gameOver || grid[r][c].flagged || grid[r][c].revealed) return;
    if (firstClick) {
      firstClick = false;
      placeMines(r, c);
    }
    grid[r][c].revealed = true;
    if (grid[r][c].mine) {
      gameOver = true;
      won = false;
      for (let row of grid) for (let cell of row) cell.revealed = true;
      return;
    }
    if (grid[r][c].adjacent === 0) floodFill(r, c);
    checkWin();
  }

  function floodFill(row, col) {
    for (let dr = -1; dr <= 1; dr++) {
      for (let dc = -1; dc <= 1; dc++) {
        let nr = row + dr, nc = col + dc;
        if (nr < 0 || nr >= rows || nc < 0 || nc >= cols) continue;
        if (grid[nr][nc].revealed || grid[nr][nc].mine || grid[nr][nc].flagged) continue;
        grid[nr][nc].revealed = true;
        if (grid[nr][nc].adjacent === 0) floodFill(nr, nc);
      }
    }
  }

  function toggleFlag(r, c) {
    if (gameOver || grid[r][c].revealed) return;
    grid[r][c].flagged = !grid[r][c].flagged;
  }

  function checkWin() {
    let totalSafe = rows * cols - mineCount;
    let revealed = grid.flat().filter(c => c.revealed && !c.mine).length;
    if (revealed === totalSafe) {
      gameOver = true;
      won = true;
      handleWin();
    }
  }

  async function handleWin() {
    submitting = true;
    await onSuccess();
    submitting = false;
  }

  function handleContext(e, r, c) {
    e.preventDefault();
    toggleFlag(r, c);
  }

  const numberColors = ["", "#1a75d1", "#388e3c", "#d32f2f", "#7b1fa2", "#994d00", "#00838f", "#333", "#808080"];

  onMount(initGrid);
</script>

<div class="panic-view">
  <div class="panic-card">
    <div class="panic-header">
      <h2>Minesweeper</h2>
      <p class="subtitle">Clear the board without hitting a mine. Right-click to flag.</p>
    </div>

    <div class="info-row">
      <span class="mine-count">Mines: {mineCount}</span>
      <span class="flag-count">Flags: {flagCount}/{mineCount}</span>
    </div>

    <div class="grid" style="grid-template-columns: repeat({cols}, 1fr)">
      {#each grid as row, r}
        {#each row as cell, c}
          <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
          <div
            class="cell"
            class:revealed={cell.revealed}
            class:mine={cell.revealed && cell.mine}
            class:grass-light={(r + c) % 2 === 0 && !cell.revealed}
            class:grass-dark={(r + c) % 2 === 1 && !cell.revealed}
            class:dirt-light={(r + c) % 2 === 0 && cell.revealed && !cell.mine}
            class:dirt-dark={(r + c) % 2 === 1 && cell.revealed && !cell.mine}
            onclick={() => reveal(r, c)}
            oncontextmenu={(e) => handleContext(e, r, c)}
          >
            {#if cell.revealed && cell.mine}
              <span class="mine-icon">💣</span>
            {:else if cell.revealed && cell.adjacent > 0}
              <span class="number" style="color: {numberColors[cell.adjacent]}">{cell.adjacent}</span>
            {:else if !cell.revealed && cell.flagged}
              <span class="flag-icon">🚩</span>
            {/if}
          </div>
        {/each}
      {/each}
    </div>

    <div class="actions">
      {#if gameOver && !won}
        <span class="result-text error">You hit a mine!</span>
        <button class="retry-btn" onclick={initGrid}>Try Again</button>
      {:else if won}
        <span class="result-text success">Cleared!</span>
        {#if submitting}
          <span class="spinner"></span>
        {/if}
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
    max-width: 500px;
    width: 100%;
    display: flex;
    flex-direction: column;
    gap: 12px;
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
    font-size: 12px;
    color: #888;
    font-variant-numeric: tabular-nums;
  }

  .grid {
    display: grid;
    gap: 0;
    border-radius: 8px;
    overflow: hidden;
    user-select: none;
  }

  .cell {
    aspect-ratio: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    cursor: pointer;
    font-size: 13px;
    font-weight: 700;
    transition: filter 0.05s;
  }

  .cell:hover:not(.revealed) {
    filter: brightness(1.1);
  }

  .grass-light { background: #7ab446; }
  .grass-dark { background: #6da33a; }
  .dirt-light { background: #e2d4b9; }
  .dirt-dark { background: #d8c8ac; }
  .mine { background: rgba(239, 68, 68, 0.7); }

  .number {
    font-family: "SF Pro Rounded", -apple-system, sans-serif;
    font-size: 14px;
    font-weight: 800;
  }

  .mine-icon, .flag-icon {
    font-size: 14px;
    line-height: 1;
  }

  .actions {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-top: 4px;
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
