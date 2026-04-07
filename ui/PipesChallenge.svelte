<script>
  import { onMount } from "svelte";

  let { onSuccess, onCancel } = $props();

  function getConfig() {
    try {
      let c = JSON.parse(localStorage.getItem("bliss_panic_configs") || "{}");
      let s = c.pipes_size || "medium";
      let sizes = { small: { grid: 5, flows: 4 }, medium: { grid: 7, flows: 6 }, large: { grid: 9, flows: 8 } };
      return sizes[s] || sizes.medium;
    } catch { return { grid: 7, flows: 6 }; }
  }

  let cfg = getConfig();
  let gridSize = cfg.grid;
  let flowCount = cfg.flows;

  const flowColors = [
    "#e53835", "#2196f3", "#4caf50", "#ff9800",
    "#9c27b0", "#ffeb3b", "#795548", "#00bcd4",
  ];

  let grid = $state([]);
  let endpoints = $state([]);
  let paths = $state([]);
  let activeFlow = $state(null);
  let won = $state(false);
  let submitting = $state(false);
  let lastDragCell = $state(null);
  let gridEl;

  function initGame() {
    grid = Array.from({ length: gridSize }, () =>
      Array.from({ length: gridSize }, () => ({ flowIndex: null, isEndpoint: false }))
    );
    paths = Array.from({ length: flowCount }, () => []);
    endpoints = [];
    activeFlow = null;
    won = false;
    generatePuzzle();
  }

  // Simple puzzle gen: snake paths through the grid
  function generatePuzzle() {
    let n = gridSize;
    // Try proper generation first, fall back to snake
    if (!tryGenerate()) {
      generateFallback();
    }
  }

  function tryGenerate() {
    let n = gridSize;
    let owner = Array.from({ length: n }, () => Array(n).fill(-1));
    let dirs = [[-1,0],[1,0],[0,-1],[0,1]];

    // Place seeds
    let seeds = [];
    let taken = new Set();
    for (let fi = 0; fi < flowCount; fi++) {
      let placed = false;
      for (let attempt = 0; attempt < 500; attempt++) {
        let r = Math.floor(Math.random() * n);
        let c = Math.floor(Math.random() * n);
        let key = r * n + c;
        if (!taken.has(key)) {
          taken.add(key);
          seeds.push([r, c]);
          owner[r][c] = fi;
          placed = true;
          break;
        }
      }
      if (!placed) return false;
    }

    // Grow regions
    let frontiers = seeds.map(s => [[s[0], s[1]]]);
    let assigned = flowCount;
    let total = n * n;

    while (assigned < total) {
      let grew = false;
      for (let fi = 0; fi < flowCount; fi++) {
        shuffle(frontiers[fi]);
        let next = [];
        for (let [cr, cc] of frontiers[fi]) {
          let neighbors = [];
          for (let [dr, dc] of dirs) {
            let nr = cr + dr, nc = cc + dc;
            if (nr >= 0 && nr < n && nc >= 0 && nc < n && owner[nr][nc] === -1) {
              neighbors.push([nr, nc]);
            }
          }
          shuffle(neighbors);
          for (let [nr, nc] of neighbors) {
            if (owner[nr][nc] === -1) {
              owner[nr][nc] = fi;
              assigned++;
              next.push([nr, nc]);
              grew = true;
            }
          }
          let stillActive = dirs.some(([dr, dc]) => {
            let nr = cr + dr, nc = cc + dc;
            return nr >= 0 && nr < n && nc >= 0 && nc < n && owner[nr][nc] === -1;
          });
          if (stillActive) next.push([cr, cc]);
        }
        frontiers[fi] = next;
      }
      if (!grew) return false;
    }

    // Collect regions
    let regionCells = Array.from({ length: flowCount }, () => []);
    for (let r = 0; r < n; r++)
      for (let c = 0; c < n; c++)
        if (owner[r][c] >= 0) regionCells[owner[r][c]].push([r, c]);

    for (let fi = 0; fi < flowCount; fi++)
      if (regionCells[fi].length < 2) return false;

    // Find Hamiltonian path in each region
    let genEndpoints = [];
    for (let fi = 0; fi < flowCount; fi++) {
      let cells = regionCells[fi];
      let cellSet = new Set(cells.map(([r, c]) => r * n + c));
      let found = null;

      let candidates = [...cells];
      shuffle(candidates);
      candidates = candidates.slice(0, 6);

      for (let start of candidates) {
        let path = hamiltonianPath(start, cellSet, cells.length, n);
        if (path) { found = path; break; }
      }
      if (!found) return false;
      genEndpoints.push([found[0], found[found.length - 1]]);
    }

    // Success - set up grid
    grid = Array.from({ length: n }, () =>
      Array.from({ length: n }, () => ({ flowIndex: null, isEndpoint: false }))
    );
    endpoints = genEndpoints;
    paths = Array.from({ length: flowCount }, () => []);
    for (let fi = 0; fi < flowCount; fi++) {
      for (let ep of endpoints[fi]) {
        grid[ep[0]][ep[1]] = { flowIndex: fi, isEndpoint: true };
      }
    }
    activeFlow = null;
    won = false;
    return true;
  }

  function hamiltonianPath(start, cellSet, count, n) {
    let dirs = [[-1,0],[1,0],[0,-1],[0,1]];
    let path = [start];
    let visited = new Set([start[0] * n + start[1]]);
    let budget = count * count * 4;

    function dfs() {
      if (path.length === count) return true;
      if (budget <= 0) return false;
      let [cr, cc] = path[path.length - 1];

      let neighbors = [];
      for (let [dr, dc] of dirs) {
        let nr = cr + dr, nc = cc + dc;
        let key = nr * n + nc;
        if (nr >= 0 && nr < n && nc >= 0 && nc < n && cellSet.has(key) && !visited.has(key)) {
          let deg = 0;
          for (let [d2r, d2c] of dirs) {
            let nnr = nr + d2r, nnc = nc + d2c;
            let nkey = nnr * n + nnc;
            if (nnr >= 0 && nnr < n && nnc >= 0 && nnc < n && cellSet.has(nkey) && !visited.has(nkey)) deg++;
          }
          neighbors.push([nr, nc, deg]);
        }
      }
      neighbors.sort((a, b) => a[2] - b[2]); // Warnsdorff

      for (let [nr, nc] of neighbors) {
        let key = nr * n + nc;
        path.push([nr, nc]);
        visited.add(key);
        if (dfs()) return true;
        path.pop();
        visited.delete(key);
        budget--;
        if (budget <= 0) return false;
      }
      return false;
    }

    return dfs() ? path : null;
  }

  function generateFallback() {
    let n = gridSize;
    grid = Array.from({ length: n }, () =>
      Array.from({ length: n }, () => ({ flowIndex: null, isEndpoint: false }))
    );
    endpoints = [];
    paths = [];

    let row = 0, col = 0, fi = 0;
    let cellsPerFlow = Math.floor((n * n) / flowCount);
    let currentPath = [];
    let goingRight = true;

    for (let i = 0; i < n * n; i++) {
      currentPath.push([row, col]);
      grid[row][col] = { flowIndex: fi, isEndpoint: false };

      if (currentPath.length >= cellsPerFlow && fi < flowCount - 1) {
        let start = currentPath[0], end = currentPath[currentPath.length - 1];
        grid[start[0]][start[1]] = { flowIndex: fi, isEndpoint: true };
        grid[end[0]][end[1]] = { flowIndex: fi, isEndpoint: true };
        endpoints.push([start, end]);
        paths.push([]);
        fi++;
        currentPath = [];
      }

      if (goingRight) {
        if (col + 1 < n) col++;
        else { row++; goingRight = false; }
      } else {
        if (col - 1 >= 0) col--;
        else { row++; goingRight = true; }
      }
    }

    if (currentPath.length > 0) {
      let start = currentPath[0], end = currentPath[currentPath.length - 1];
      grid[start[0]][start[1]] = { flowIndex: fi, isEndpoint: true };
      grid[end[0]][end[1]] = { flowIndex: fi, isEndpoint: true };
      endpoints.push([start, end]);
      paths.push([]);
    }

    while (endpoints.length < flowCount) {
      endpoints.push([[0,0],[0,0]]);
      paths.push([]);
    }
    activeFlow = null;
    won = false;
  }

  function shuffle(arr) {
    for (let i = arr.length - 1; i > 0; i--) {
      let j = Math.floor(Math.random() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
  }

  function getCellFromEvent(e) {
    if (!gridEl) return null;
    let rect = gridEl.getBoundingClientRect();
    let cellW = rect.width / gridSize;
    let cellH = rect.height / gridSize;
    let clientX = e.touches ? e.touches[0].clientX : e.clientX;
    let clientY = e.touches ? e.touches[0].clientY : e.clientY;
    let col = Math.floor((clientX - rect.left) / cellW);
    let row = Math.floor((clientY - rect.top) / cellH);
    if (row < 0 || row >= gridSize || col < 0 || col >= gridSize) return null;
    return [row, col];
  }

  function handlePointerDown(e) {
    if (won) return;
    let pos = getCellFromEvent(e);
    if (!pos) return;
    let [r, c] = pos;
    lastDragCell = `${r},${c}`;
    let cell = grid[r][c];

    if (cell.isEndpoint && cell.flowIndex !== null) {
      clearPath(cell.flowIndex);
      activeFlow = cell.flowIndex;
      paths[cell.flowIndex] = [[r, c]];
    } else if (cell.flowIndex !== null && !cell.isEndpoint) {
      breakPathAt(cell.flowIndex, r, c);
      activeFlow = cell.flowIndex;
    }
  }

  function handlePointerMove(e) {
    if (activeFlow === null || won) return;
    let pos = getCellFromEvent(e);
    if (!pos) return;
    let [r, c] = pos;
    let key = `${r},${c}`;
    if (lastDragCell === key) return;
    lastDragCell = key;
    extendPath(activeFlow, r, c);
  }

  function handlePointerUp() {
    if (activeFlow !== null) {
      if (!isPathComplete(activeFlow)) {
        clearPath(activeFlow);
      }
      activeFlow = null;
      lastDragCell = null;
    }
  }

  function extendPath(fi, row, col) {
    let path = paths[fi];
    if (path.length === 0) return;
    let last = path[path.length - 1];
    let dr = Math.abs(row - last[0]), dc = Math.abs(col - last[1]);
    if (!((dr === 1 && dc === 0) || (dr === 0 && dc === 1))) return;

    // Backtracking
    if (path.length >= 2) {
      let prev = path[path.length - 2];
      if (prev[0] === row && prev[1] === col) {
        let removed = path.pop();
        paths[fi] = [...path];
        if (!grid[removed[0]][removed[1]].isEndpoint) {
          grid[removed[0]][removed[1]].flowIndex = null;
        }
        return;
      }
    }

    let target = grid[row][col];
    if (target.isEndpoint && target.flowIndex !== fi) return;

    if (target.isEndpoint && target.flowIndex === fi) {
      let ep0 = endpoints[fi][0], ep1 = endpoints[fi][1];
      let pathStart = path[0];
      let otherEnd = (pathStart[0] === ep0[0] && pathStart[1] === ep0[1]) ? ep1 : ep0;
      if (row === otherEnd[0] && col === otherEnd[1]) {
        paths[fi] = [...path, [row, col]];
        activeFlow = null;
        checkWin();
      }
      return;
    }

    if (target.flowIndex !== null && target.flowIndex !== fi && !target.isEndpoint) {
      clearPath(target.flowIndex);
    }

    if (target.flowIndex === fi) return;

    path.push([row, col]);
    paths[fi] = [...path];
    grid[row][col].flowIndex = fi;
  }

  function clearPath(fi) {
    for (let [r, c] of paths[fi]) {
      if (!grid[r][c].isEndpoint) {
        grid[r][c].flowIndex = null;
      }
    }
    paths[fi] = [];
  }

  function breakPathAt(fi, row, col) {
    let idx = paths[fi].findIndex(([r, c]) => r === row && c === col);
    if (idx === -1) return;
    let removed = paths[fi].splice(idx + 1);
    for (let [r, c] of removed) {
      if (!grid[r][c].isEndpoint) {
        grid[r][c].flowIndex = null;
      }
    }
    paths[fi] = [...paths[fi]];
  }

  function isPathComplete(fi) {
    let path = paths[fi];
    if (path.length < 2) return false;
    let first = path[0], last = path[path.length - 1];
    let ep0 = endpoints[fi][0], ep1 = endpoints[fi][1];
    let startsAt = (first[0] === ep0[0] && first[1] === ep0[1]) || (first[0] === ep1[0] && first[1] === ep1[1]);
    let endsAt = (last[0] === ep0[0] && last[1] === ep0[1]) || (last[0] === ep1[0] && last[1] === ep1[1]);
    let different = !(first[0] === last[0] && first[1] === last[1]);
    return startsAt && endsAt && different;
  }

  function checkWin() {
    for (let fi = 0; fi < flowCount; fi++) {
      if (!isPathComplete(fi)) return;
    }
    for (let r = 0; r < gridSize; r++)
      for (let c = 0; c < gridSize; c++)
        if (grid[r][c].flowIndex === null) return;
    won = true;
    handleWin();
  }

  let completedFlows = $derived(
    paths.filter((path, fi) => fi < endpoints.length && isPathComplete(fi)).length
  );

  async function handleWin() {
    submitting = true;
    await onSuccess();
    submitting = false;
  }

  // SVG path data for drawn pipes
  function pathSVG(fi) {
    let path = paths[fi];
    if (path.length < 2) return "";
    let cellW = 100 / gridSize;
    let half = cellW / 2;
    let d = `M ${path[0][1] * cellW + half} ${path[0][0] * cellW + half}`;
    for (let i = 1; i < path.length; i++) {
      d += ` L ${path[i][1] * cellW + half} ${path[i][0] * cellW + half}`;
    }
    return d;
  }

  onMount(initGame);
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="panic-view">
  <div class="panic-card">
    <div class="panic-header">
      <h2>Pipes</h2>
      <p class="subtitle">Draw paths connecting matching colored dots. Fill every cell.</p>
    </div>

    <div class="info-row">
      <span>Drag from dot to dot</span>
      <span class="flow-count">Flows: {completedFlows}/{flowCount}</span>
    </div>

    <div
      class="grid-wrapper"
      bind:this={gridEl}
      onpointerdown={handlePointerDown}
      onpointermove={handlePointerMove}
      onpointerup={handlePointerUp}
      onpointerleave={handlePointerUp}
    >
      <div class="grid" style="grid-template-columns: repeat({gridSize}, 1fr)">
        {#each grid as row, r}
          {#each row as cell, c}
            <div class="cell" class:dark={(r + c) % 2 === 0}>
              {#if cell.isEndpoint && cell.flowIndex !== null}
                <div class="dot" style="background: {flowColors[cell.flowIndex % flowColors.length]}"></div>
              {/if}
            </div>
          {/each}
        {/each}
      </div>
      <svg class="pipe-overlay" viewBox="0 0 100 100" preserveAspectRatio="none">
        {#each paths as _, fi}
          {#if paths[fi].length >= 2}
            <path
              d={pathSVG(fi)}
              stroke={flowColors[fi % flowColors.length]}
              stroke-width={100 / gridSize * 0.35}
              stroke-linecap="round"
              stroke-linejoin="round"
              fill="none"
              opacity="0.85"
            />
          {/if}
        {/each}
      </svg>
    </div>

    <div class="actions">
      {#if won}
        <span class="result-text success">All flows connected!</span>
        {#if submitting}<span class="spinner"></span>{/if}
      {:else}
        <button class="cancel-btn" onclick={onCancel}>Cancel</button>
        <button class="retry-btn" onclick={initGame}>New Puzzle</button>
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
    max-width: 480px;
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
  }

  .flow-count {
    font-variant-numeric: tabular-nums;
  }

  .grid-wrapper {
    position: relative;
    aspect-ratio: 1;
    border-radius: 8px;
    overflow: hidden;
    touch-action: none;
    cursor: crosshair;
  }

  .grid {
    display: grid;
    gap: 0;
    width: 100%;
    height: 100%;
  }

  .cell {
    display: flex;
    align-items: center;
    justify-content: center;
    background: #1e1e22;
    border: 0.5px solid rgba(255, 255, 255, 0.06);
  }

  .cell.dark {
    background: #1a1a1e;
  }

  .dot {
    width: 60%;
    height: 60%;
    border-radius: 50%;
    z-index: 2;
    pointer-events: none;
  }

  .pipe-overlay {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
    z-index: 1;
  }

  .actions {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 32px;
  }

  .result-text.success { color: #4ade80; font-size: 14px; font-weight: 500; }

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

  .cancel-btn:hover, .retry-btn:hover { border-color: #555; }

  .spinner {
    display: inline-block;
    width: 14px;
    height: 14px;
    border: 2px solid #444;
    border-top-color: #e0e0e0;
    border-radius: 50%;
    animation: spin 0.6s linear infinite;
  }

  @keyframes spin { to { transform: rotate(360deg); } }
</style>
