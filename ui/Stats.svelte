<script>
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";

  let stats = $state({ total_sessions: 0, total_focus_minutes: 0, current_streak: 0, longest_streak: 0 });
  let log = $state([]);
  let dailyMinutes = $state({});

  async function load() {
    stats = await invoke("stats_load");
    log = await invoke("stats_log_load");
    let map = {};
    for (let entry of log) {
      map[entry.date] = (map[entry.date] || 0) + entry.minutes;
    }
    dailyMinutes = map;
  }

  function dateKey(daysAgo) {
    let d = new Date();
    d.setDate(d.getDate() - daysAgo);
    return d.toISOString().slice(0, 10);
  }

  function colorForMinutes(mins) {
    if (mins === 0) return "rgba(255,255,255,0.04)";
    if (mins < 30) return "rgba(74,222,128,0.25)";
    if (mins < 60) return "rgba(74,222,128,0.45)";
    if (mins < 120) return "rgba(74,222,128,0.65)";
    return "rgba(74,222,128,0.85)";
  }

  let heatmapWeeks = $derived.by(() => {
    let weeks = [];
    for (let col = 0; col < 52; col++) {
      let week = [];
      for (let row = 0; row < 7; row++) {
        let daysAgo = (51 - col) * 7 + (6 - row);
        let key = dateKey(daysAgo);
        let mins = dailyMinutes[key] || 0;
        week.push({ key, mins });
      }
      weeks.push(week);
    }
    return weeks;
  });

  let recentSessions = $derived(log.slice().reverse().slice(0, 20));

  function formatDuration(mins) {
    if (mins < 60) return `${mins}m`;
    let h = Math.floor(mins / 60);
    let m = mins % 60;
    return m > 0 ? `${h}h ${m}m` : `${h}h`;
  }

  function formatDate(dateStr) {
    let d = new Date(dateStr + "T00:00:00");
    return d.toLocaleDateString("en-US", { month: "short", day: "numeric", year: "numeric" });
  }

  function formatTimestamp(ts) {
    let secs = parseInt(ts);
    if (isNaN(secs)) return "";
    let d = new Date(secs * 1000);
    return d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
  }

  onMount(load);
</script>

<div class="stats-view">
  <div class="cards">
    <div class="stat-card">
      <span class="stat-value">{stats.total_sessions}</span>
      <span class="stat-label">Sessions</span>
    </div>
    <div class="stat-card">
      <span class="stat-value">{formatDuration(stats.total_focus_minutes)}</span>
      <span class="stat-label">Focused</span>
    </div>
    <div class="stat-card">
      <span class="stat-value">{stats.current_streak}</span>
      <span class="stat-label">Streak</span>
    </div>
    <div class="stat-card">
      <span class="stat-value">{stats.longest_streak}</span>
      <span class="stat-label">Best</span>
    </div>
  </div>

  <div class="section">
    <h3 class="section-title">Activity</h3>
    <div class="heatmap-container">
      <div class="heatmap-labels">
        {#each ["", "Mon", "", "Wed", "", "Fri", ""] as label}
          <span class="day-label">{label}</span>
        {/each}
      </div>
      <div class="heatmap-scroll">
        <div class="heatmap-grid">
          {#each heatmapWeeks as week}
            <div class="heatmap-col">
              {#each week as cell}
                <div
                  class="heatmap-cell"
                  style="background: {colorForMinutes(cell.mins)}"
                  title="{cell.key}: {formatDuration(cell.mins)}"
                ></div>
              {/each}
            </div>
          {/each}
        </div>
      </div>
    </div>
    <div class="heatmap-legend">
      <span class="legend-text">Less</span>
      {#each [0, 15, 45, 90, 150] as m}
        <div class="legend-cell" style="background: {colorForMinutes(m)}"></div>
      {/each}
      <span class="legend-text">More</span>
    </div>
  </div>

  <div class="section">
    <h3 class="section-title">Recent Sessions</h3>
    <div class="session-list">
      {#if recentSessions.length === 0}
        <div class="empty">No sessions recorded yet</div>
      {:else}
        {#each recentSessions as entry}
          <div class="session-row">
            <div class="session-info">
              <span class="session-date">{formatDate(entry.date)}</span>
              <span class="session-time">{formatTimestamp(entry.started_at)}</span>
            </div>
            <span class="session-duration">{formatDuration(entry.minutes)}</span>
          </div>
        {/each}
      {/if}
    </div>
  </div>
</div>

<style>
  .stats-view {
    flex: 1;
    overflow-y: auto;
    padding: 24px;
  }

  .cards {
    display: flex;
    gap: 12px;
    margin-bottom: 24px;
  }

  .stat-card {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 4px;
    padding: 14px 0;
    background: rgba(255,255,255,0.05);
    border-radius: 10px;
  }

  .stat-value {
    font-size: 22px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: #f0f0f0;
  }

  .stat-label {
    font-size: 11px;
    color: #999;
  }

  .section {
    margin-bottom: 24px;
  }

  .section-title {
    font-size: 14px;
    font-weight: 600;
    color: #f0f0f0;
    margin: 0 0 10px;
  }

  .heatmap-container {
    display: flex;
    gap: 0;
  }

  .heatmap-labels {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding-right: 4px;
    flex-shrink: 0;
  }

  .day-label {
    font-size: 9px;
    color: #888;
    height: 11px;
    display: flex;
    align-items: center;
    justify-content: flex-end;
    width: 24px;
  }

  .heatmap-scroll {
    overflow-x: auto;
    flex: 1;
  }

  .heatmap-grid {
    display: flex;
    gap: 2px;
  }

  .heatmap-col {
    display: flex;
    flex-direction: column;
    gap: 2px;
  }

  .heatmap-cell {
    width: 11px;
    height: 11px;
    border-radius: 2px;
  }

  .heatmap-legend {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: 3px;
    margin-top: 6px;
  }

  .legend-text {
    font-size: 9px;
    color: #888;
  }

  .legend-cell {
    width: 11px;
    height: 11px;
    border-radius: 2px;
  }

  .session-list {
    background: rgba(255,255,255,0.04);
    border-radius: 10px;
    overflow: hidden;
  }

  .session-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 8px 14px;
    border-bottom: 1px solid rgba(255,255,255,0.04);
  }

  .session-row:last-child {
    border-bottom: none;
  }

  .session-info {
    display: flex;
    flex-direction: column;
    gap: 1px;
  }

  .session-date {
    font-size: 13px;
    color: #f0f0f0;
  }

  .session-time {
    font-size: 11px;
    color: #888;
  }

  .session-duration {
    font-size: 13px;
    font-variant-numeric: tabular-nums;
    color: #999;
  }

  .empty {
    padding: 20px;
    text-align: center;
    font-size: 13px;
    color: #777;
  }
</style>
