<script>
  import { onMount } from "svelte";

  let { onSuccess, onCancel } = $props();

  function getConfig() {
    try {
      let c = JSON.parse(localStorage.getItem("bliss_panic_configs") || "{}");
      let d = c.sudoku_difficulty || "medium";
      return { easy: 30, medium: 25, hard: 20 }[d] || 25;
    } catch { return 25; }
  }

  const CLUES = getConfig();
  let board = $state([]);
  let solution = $state([]);
  let fixed = $state([]);
  let selected = $state(null); // { r, c }
  let won = $state(false);
  let submitting = $state(false);

  function initGame() {
    let grid = Array.from({ length: 9 }, () => Array(9).fill(0));
    fillBoard(grid, 0);
    solution = grid.map(r => [...r]);
    board = grid.map(r => [...r]);

    let positions = [];
    for (let i = 0; i < 81; i++) positions.push([Math.floor(i / 9), i % 9]);
    shuffle(positions);

    let toRemove = 81 - CLUES;
    for (let i = 0; i < toRemove; i++) {
      let [r, c] = positions[i];
      board[r][c] = 0;
    }

    fixed = board.map(r => r.map(v => v !== 0));
    selected = null;
    won = false;
  }

  function shuffle(arr) {
    for (let i = arr.length - 1; i > 0; i--) {
      let j = Math.floor(Math.random() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
  }

  function fillBoard(grid, pos) {
    if (pos === 81) return true;
    let row = Math.floor(pos / 9);
    let col = pos % 9;
    let nums = [1,2,3,4,5,6,7,8,9];
    shuffle(nums);
    for (let num of nums) {
      if (isValid(grid, row, col, num)) {
        grid[row][col] = num;
        if (fillBoard(grid, pos + 1)) return true;
        grid[row][col] = 0;
      }
    }
    return false;
  }

  function isValid(grid, row, col, num) {
    for (let c = 0; c < 9; c++) if (grid[row][c] === num) return false;
    for (let r = 0; r < 9; r++) if (grid[r][col] === num) return false;
    let boxR = Math.floor(row / 3) * 3;
    let boxC = Math.floor(col / 3) * 3;
    for (let r = boxR; r < boxR + 3; r++)
      for (let c = boxC; c < boxC + 3; c++)
        if (grid[r][c] === num) return false;
    return true;
  }

  function hasConflict(row, col) {
    let val = board[row][col];
    if (val === 0) return false;
    for (let c = 0; c < 9; c++) if (c !== col && board[row][c] === val) return true;
    for (let r = 0; r < 9; r++) if (r !== row && board[r][col] === val) return true;
    let boxR = Math.floor(row / 3) * 3;
    let boxC = Math.floor(col / 3) * 3;
    for (let r = boxR; r < boxR + 3; r++)
      for (let c = boxC; c < boxC + 3; c++)
        if ((r !== row || c !== col) && board[r][c] === val) return true;
    return false;
  }

  function selectCell(r, c) {
    if (won) return;
    selected = { r, c };
  }

  function placeNumber(num) {
    if (!selected || fixed[selected.r][selected.c] || won) return;
    board[selected.r][selected.c] = num;
    checkWin();
  }

  function clearCell() {
    if (!selected || fixed[selected.r][selected.c] || won) return;
    board[selected.r][selected.c] = 0;
  }

  function checkWin() {
    for (let r = 0; r < 9; r++)
      for (let c = 0; c < 9; c++)
        if (board[r][c] !== solution[r][c]) return;
    won = true;
    handleWin();
  }

  function handleKeydown(e) {
    if (!selected || won) return;
    let num = parseInt(e.key);
    if (num >= 1 && num <= 9) {
      e.preventDefault();
      placeNumber(num);
    } else if (e.key === "Backspace" || e.key === "Delete") {
      e.preventDefault();
      clearCell();
    } else if (e.key === "ArrowUp" && selected.r > 0) { selected = { r: selected.r - 1, c: selected.c }; }
    else if (e.key === "ArrowDown" && selected.r < 8) { selected = { r: selected.r + 1, c: selected.c }; }
    else if (e.key === "ArrowLeft" && selected.c > 0) { selected = { r: selected.r, c: selected.c - 1 }; }
    else if (e.key === "ArrowRight" && selected.c < 8) { selected = { r: selected.r, c: selected.c + 1 }; }
  }

  async function handleWin() {
    submitting = true;
    await onSuccess();
    submitting = false;
  }

  function isInSameBox(r1, c1, r2, c2) {
    return Math.floor(r1 / 3) === Math.floor(r2 / 3) && Math.floor(c1 / 3) === Math.floor(c2 / 3);
  }

  function cellHighlight(r, c) {
    if (!selected) return "";
    if (selected.r === r && selected.c === c) return "selected";
    if (selected.r === r || selected.c === c || isInSameBox(selected.r, selected.c, r, c)) return "related";
    return "";
  }

  onMount(initGame);
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="panic-view">
  <div class="panic-card">
    <div class="panic-header">
      <h2>Sudoku</h2>
      <p class="subtitle">Fill the grid so each row, column, and 3x3 box contains 1-9.</p>
    </div>

    <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions a11y_no_noninteractive_element_interactions -->
    <div class="board">
      {#each board as row, r}
        {#each row as val, c}
          <div
            class="cell {cellHighlight(r, c)}"
            class:fixed={fixed[r]?.[c]}
            class:conflict={val > 0 && hasConflict(r, c)}
            class:right-border={c === 2 || c === 5}
            class:bottom-border={r === 2 || r === 5}
            onclick={() => selectCell(r, c)}
          >
            {#if val > 0}
              <span class="cell-num">{val}</span>
            {/if}
          </div>
        {/each}
      {/each}
    </div>

    <div class="numpad">
      {#each [1,2,3,4,5,6,7,8,9] as num}
        <button class="num-btn" onclick={() => placeNumber(num)}>{num}</button>
      {/each}
      <button class="num-btn erase" onclick={clearCell}>X</button>
    </div>

    <div class="actions">
      {#if won}
        <span class="result-text success">Solved!</span>
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
    max-width: 420px;
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

  .board {
    display: grid;
    grid-template-columns: repeat(9, 1fr);
    gap: 0;
    border: 2px solid #555;
    border-radius: 6px;
    overflow: hidden;
    width: 100%;
    max-width: 380px;
  }

  .cell {
    aspect-ratio: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    border: 1px solid #333;
    cursor: pointer;
    transition: background 0.1s;
    background: #222;
  }

  .cell:hover {
    background: #2a2a2a;
  }

  .cell.selected {
    background: rgba(236, 72, 153, 0.25);
  }

  .cell.related {
    background: rgba(236, 72, 153, 0.08);
  }

  .cell.right-border {
    border-right: 2px solid #555;
  }

  .cell.bottom-border {
    border-bottom: 2px solid #555;
  }

  .cell-num {
    font-size: 16px;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    color: #e0e0e0;
  }

  .cell.fixed .cell-num {
    color: #aaa;
  }

  .cell:not(.fixed) .cell-num {
    color: #ec4899;
  }

  .cell.conflict .cell-num {
    color: #ef4444;
  }

  .numpad {
    display: flex;
    gap: 6px;
    flex-wrap: wrap;
    justify-content: center;
  }

  .num-btn {
    width: 36px;
    height: 36px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 16px;
    font-weight: 600;
    border: 1px solid #444;
    border-radius: 6px;
    background: rgba(255, 255, 255, 0.06);
    color: #e0e0e0;
    cursor: pointer;
    transition: background 0.1s;
  }

  .num-btn:hover {
    background: rgba(255, 255, 255, 0.12);
  }

  .num-btn.erase {
    color: #ef4444;
  }

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

  .result-text.success { color: #4ade80; }

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
