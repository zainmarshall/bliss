<script>
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";

  let { sessionActive } = $props();

  let schedules = $state([]);
  let profiles = $state([]);
  let showEditor = $state(false);
  let editingEntry = $state(null);

  // Editor form state
  let configName = $state("");
  let selectedDays = $state(new Set());
  let displayHour = $state(9);
  let displayMinute = $state(0);
  let isAM = $state(true);
  let durHours = $state(1);
  let durMins = $state(0);

  const dayButtons = [
    { label: "M", weekday: 2 },
    { label: "T", weekday: 3 },
    { label: "W", weekday: 4 },
    { label: "T", weekday: 5 },
    { label: "F", weekday: 6 },
    { label: "S", weekday: 7 },
    { label: "S", weekday: 1 },
  ];

  const colorMap = {
    blue: "#3b82f6", purple: "#a855f7", indigo: "#6366f1",
    pink: "#ec4899", red: "#ef4444", orange: "#f97316",
    yellow: "#eab308", green: "#22c55e", mint: "#2dd4bf",
    cyan: "#06b6d4", teal: "#14b8a6",
  };

  function profileColor(name) {
    let p = profiles.find(pr => pr.name === name);
    return colorMap[p?.colorName] || colorMap.pink;
  }

  let hour24 = $derived(() => {
    let h = displayHour;
    if (h === 12) h = 0;
    if (!isAM) h += 12;
    return h;
  });

  let totalDuration = $derived(durHours * 60 + durMins);

  async function load() {
    schedules = await invoke("schedule_list");
    profiles = await invoke("profile_list");
  }

  async function saveSchedules() {
    await invoke("schedule_save", { entries: schedules });
  }

  function openAdd(prefillDay, prefillHour) {
    editingEntry = null;
    configName = profiles[0]?.name || "";
    selectedDays = prefillDay != null ? new Set([prefillDay]) : new Set();
    if (prefillHour != null) {
      let h12 = prefillHour % 12 || 12;
      displayHour = h12;
      isAM = prefillHour < 12;
    } else {
      displayHour = 9;
      isAM = true;
    }
    displayMinute = 0;
    durHours = 1;
    durMins = 0;
    showEditor = true;
  }

  function openEdit(entry) {
    editingEntry = entry;
    configName = entry.configName;
    selectedDays = new Set(entry.days);
    let h12 = entry.hour % 12 || 12;
    displayHour = h12;
    isAM = entry.hour < 12;
    displayMinute = entry.minute;
    durHours = Math.floor(entry.durationMinutes / 60);
    durMins = entry.durationMinutes % 60;
    showEditor = true;
  }

  function saveEntry() {
    let h = displayHour;
    if (h === 12) h = 0;
    if (!isAM) h += 12;

    let entry = {
      id: editingEntry?.id || crypto.randomUUID(),
      configName,
      days: [...selectedDays],
      hour: h,
      minute: displayMinute,
      durationMinutes: Math.max(5, durHours * 60 + durMins),
      enabled: editingEntry?.enabled ?? true,
    };

    if (editingEntry) {
      schedules = schedules.map(s => s.id === entry.id ? entry : s);
    } else {
      schedules = [...schedules, entry];
    }
    saveSchedules();
    showEditor = false;
  }

  function deleteEntry(id) {
    schedules = schedules.filter(s => s.id !== id);
    saveSchedules();
  }

  function toggleEnabled(id) {
    schedules = schedules.map(s => s.id === id ? { ...s, enabled: !s.enabled } : s);
    saveSchedules();
  }

  function toggleDay(weekday) {
    let next = new Set(selectedDays);
    if (next.has(weekday)) next.delete(weekday);
    else next.add(weekday);
    selectedDays = next;
  }

  function formatTime(hour, minute) {
    let h = hour % 12 || 12;
    let ampm = hour < 12 ? "AM" : "PM";
    return `${h}:${String(minute).padStart(2, "0")} ${ampm}`;
  }

  function formatEndTime(hour, minute, duration) {
    let total = hour * 60 + minute + duration;
    let endH = Math.floor(total / 60) % 24;
    let endM = total % 60;
    return formatTime(endH, endM);
  }

  function daysText(days) {
    let names = ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
    let order = [2, 3, 4, 5, 6, 7, 1];
    let sorted = order.filter(d => days.includes(d));
    if (sorted.length === 7) return "Every day";
    if (sorted.length === 5 && [2,3,4,5,6].every(d => sorted.includes(d))) return "Weekdays";
    if (sorted.length === 2 && [1,7].every(d => sorted.includes(d))) return "Weekends";
    return sorted.map(d => names[d]).join(", ");
  }

  function formatHourLabel(hour) {
    let h = hour % 12 || 12;
    let ampm = hour < 12 ? "a" : "p";
    return `${h}${ampm}`;
  }

  function formatDur(mins) {
    if (mins < 60) return `${mins}m`;
    let h = Math.floor(mins / 60);
    let m = mins % 60;
    return m > 0 ? `${h}h ${m}m` : `${h}h`;
  }

  let dayLabels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  let colToWeekday = [2, 3, 4, 5, 6, 7, 1];

  function blocksForDay(weekday) {
    return schedules.filter(s => s.enabled && s.days.includes(weekday)).map(s => {
      let startMin = s.hour * 60 + s.minute;
      let top = (startMin / 60) * 22;
      let height = Math.max((s.durationMinutes / 60) * 22, 14);
      return { ...s, top, height, color: profileColor(s.configName) };
    });
  }

  onMount(load);
</script>

<div class="schedule-view">
  {#if showEditor}
    <div class="editor-overlay" onclick={() => showEditor = false}>
      <div class="editor" onclick={(e) => e.stopPropagation()}>
        <div class="editor-header">
          <span class="editor-title">{editingEntry ? "Edit Schedule" : "Add Schedule"}</span>
          <button class="editor-close" onclick={() => showEditor = false}>Cancel</button>
        </div>

        <div class="editor-body">
          <div class="field">
            <label>Config</label>
            {#if profiles.length === 0}
              <span class="field-hint">Save a config first in Settings</span>
            {:else}
              <select bind:value={configName}>
                {#each profiles as p}
                  <option value={p.name}>{p.name}</option>
                {/each}
              </select>
            {/if}
          </div>

          <div class="field">
            <label>Days</label>
            <div class="day-picker">
              {#each dayButtons as d}
                <button
                  class="day-btn"
                  class:day-selected={selectedDays.has(d.weekday)}
                  onclick={() => toggleDay(d.weekday)}
                >{d.label}</button>
              {/each}
            </div>
          </div>

          <div class="field">
            <label>Start Time</label>
            <div class="time-row">
              <input type="number" class="time-input" min="1" max="12" bind:value={displayHour} />
              <span class="time-sep">:</span>
              <input type="number" class="time-input" min="0" max="59" step="5" bind:value={displayMinute} />
              <div class="ampm-toggle">
                <button class:ampm-active={isAM} onclick={() => isAM = true}>AM</button>
                <button class:ampm-active={!isAM} onclick={() => isAM = false}>PM</button>
              </div>
            </div>
          </div>

          <div class="field">
            <label>Duration</label>
            <div class="time-row">
              <input type="number" class="time-input" min="0" max="8" bind:value={durHours} />
              <span class="time-unit">h</span>
              <input type="number" class="time-input" min="0" max="55" step="5" bind:value={durMins} />
              <span class="time-unit">m</span>
            </div>
          </div>
        </div>

        <div class="editor-footer">
          {#if editingEntry}
            <button class="delete-btn" onclick={() => { deleteEntry(editingEntry.id); showEditor = false; }}>Delete</button>
          {:else}
            <div></div>
          {/if}
          <button
            class="save-btn"
            onclick={saveEntry}
            disabled={!configName || selectedDays.size === 0 || totalDuration < 5}
          >Save</button>
        </div>
      </div>
    </div>
  {/if}

  {#if schedules.length === 0}
    <div class="empty-state">
      <div class="empty-icon">
        <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/><path d="M8 14h.01"/><path d="M12 14h.01"/><path d="M16 14h.01"/><path d="M8 18h.01"/><path d="M12 18h.01"/></svg>
      </div>
      <span class="empty-title">No scheduled sessions</span>
      <span class="empty-desc">Automatically start focus sessions on a weekly schedule tied to your saved configs.</span>
      <button class="add-btn" onclick={() => openAdd(null, null)} disabled={sessionActive}>Add Schedule</button>
    </div>
  {:else}
    <div class="content">
      <div class="list-section">
        <div class="list-header">
          <span class="list-title">Schedules</span>
          <button class="add-small" onclick={() => openAdd(null, null)} disabled={sessionActive}>+ Add</button>
        </div>
        {#each schedules as entry}
          <div class="schedule-row">
            <div class="schedule-bar" style="background: {profileColor(entry.configName)}"></div>
            <div class="schedule-info">
              <div class="schedule-name-row">
                <span class="schedule-name">{entry.configName}</span>
                <span class="schedule-days">{daysText(entry.days)}</span>
              </div>
              <span class="schedule-time">
                {formatTime(entry.hour, entry.minute)} - {formatEndTime(entry.hour, entry.minute, entry.durationMinutes)} ({formatDur(entry.durationMinutes)})
              </span>
            </div>
            <button class="toggle-btn" class:toggle-on={entry.enabled} onclick={() => toggleEnabled(entry.id)}>
              <div class="toggle-thumb"></div>
            </button>
            <button class="icon-btn" onclick={() => openEdit(entry)}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
            </button>
            <button class="icon-btn delete" onclick={() => deleteEntry(entry.id)}>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 6h18"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>
            </button>
          </div>
        {/each}
      </div>

      <div class="grid-section">
        <span class="list-title">Weekly Overview</span>
        <div class="weekly-grid">
          <div class="grid-hours">
            <div class="grid-header-spacer"></div>
            {#each Array(24) as _, h}
              <div class="hour-label">{formatHourLabel(h)}</div>
            {/each}
          </div>
          {#each [0,1,2,3,4,5,6] as col}
            <div class="grid-day-col">
              <div class="grid-day-header">{dayLabels[col]}</div>
              <div class="grid-day-cells">
                {#each Array(24) as _, h}
                  <button
                    class="grid-cell"
                    class:grid-cell-even={h % 2 === 0}
                    onclick={() => openAdd(colToWeekday[col], h)}
                  ></button>
                {/each}
                {#each blocksForDay(colToWeekday[col]) as block}
                  <button
                    class="grid-block"
                    style="top: {block.top}px; height: {block.height}px; background: {block.color}"
                    onclick={() => openEdit(block)}
                  >
                    <span class="block-name">{block.configName}</span>
                    {#if block.height > 18}
                      <span class="block-time">{formatTime(block.hour, block.minute)}</span>
                    {/if}
                  </button>
                {/each}
              </div>
            </div>
          {/each}
        </div>
      </div>
    </div>
  {/if}
</div>

<style>
  .schedule-view {
    flex: 1;
    overflow-y: auto;
    padding: 20px;
  }

  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 10px;
    min-height: 400px;
    color: #999;
  }

  .empty-icon { color: #555; margin-bottom: 4px; }
  .empty-title { font-size: 16px; font-weight: 600; color: #ccc; }
  .empty-desc { font-size: 13px; color: #777; text-align: center; max-width: 320px; line-height: 1.5; }

  .add-btn {
    margin-top: 8px;
    padding: 8px 20px;
    font-size: 14px;
    font-weight: 500;
    background: #ec4899;
    color: white;
    border: none;
    border-radius: 8px;
    cursor: pointer;
  }

  .add-btn:hover { background: #db2777; }
  .add-btn:disabled { opacity: 0.4; cursor: not-allowed; }

  .content {
    display: flex;
    flex-direction: column;
    gap: 20px;
  }

  .list-section { }

  .list-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 8px;
  }

  .list-title {
    font-size: 14px;
    font-weight: 600;
    color: #f0f0f0;
  }

  .add-small {
    font-size: 12px;
    color: #ec4899;
    background: none;
    border: none;
    cursor: pointer;
  }

  .add-small:hover { opacity: 0.8; }
  .add-small:disabled { opacity: 0.3; cursor: not-allowed; }

  .schedule-row {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 12px;
    background: rgba(255,255,255,0.04);
    border-radius: 8px;
    margin-bottom: 4px;
  }

  .schedule-bar {
    width: 4px;
    height: 36px;
    border-radius: 2px;
    flex-shrink: 0;
  }

  .schedule-info {
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 2px;
    min-width: 0;
  }

  .schedule-name-row { display: flex; align-items: center; gap: 6px; }
  .schedule-name { font-size: 13px; font-weight: 500; color: #f0f0f0; }
  .schedule-days { font-size: 11px; color: #999; }
  .schedule-time { font-size: 11px; color: #888; }

  .toggle-btn {
    width: 34px;
    height: 20px;
    border-radius: 10px;
    background: #444;
    border: none;
    cursor: pointer;
    position: relative;
    transition: background 0.15s;
    flex-shrink: 0;
    padding: 0;
  }

  .toggle-btn.toggle-on { background: #4ade80; }

  .toggle-thumb {
    width: 16px;
    height: 16px;
    border-radius: 50%;
    background: white;
    position: absolute;
    top: 2px;
    left: 2px;
    transition: transform 0.15s;
  }

  .toggle-on .toggle-thumb { transform: translateX(14px); }

  .icon-btn {
    background: none;
    border: none;
    color: #999;
    cursor: pointer;
    padding: 4px;
    display: flex;
    flex-shrink: 0;
  }

  .icon-btn:hover { color: #ccc; }
  .icon-btn.delete:hover { color: #ef4444; }

  .grid-section { }

  .weekly-grid {
    display: flex;
    background: rgba(255,255,255,0.02);
    border-radius: 8px;
    overflow: hidden;
    margin-top: 8px;
  }

  .grid-hours {
    width: 30px;
    flex-shrink: 0;
  }

  .grid-header-spacer { height: 24px; }

  .hour-label {
    height: 22px;
    font-size: 9px;
    color: #888;
    display: flex;
    align-items: flex-start;
    justify-content: flex-end;
    padding-right: 3px;
  }

  .grid-day-col {
    flex: 1;
    min-width: 0;
  }

  .grid-day-header {
    height: 24px;
    font-size: 10px;
    font-weight: 500;
    color: #aaa;
    display: flex;
    align-items: center;
    justify-content: center;
  }

  .grid-day-cells {
    position: relative;
  }

  .grid-cell {
    display: block;
    width: 100%;
    height: 22px;
    background: none;
    border: none;
    border-top: 1px solid rgba(255,255,255,0.04);
    cursor: pointer;
    padding: 0;
  }

  .grid-cell.grid-cell-even { background: rgba(255,255,255,0.015); }
  .grid-cell:hover { background: rgba(255,255,255,0.06); }

  .grid-block {
    position: absolute;
    left: 1px;
    right: 1px;
    border-radius: 3px;
    padding: 1px 3px;
    display: flex;
    flex-direction: column;
    cursor: pointer;
    border: none;
    text-align: left;
    overflow: hidden;
  }

  .block-name {
    font-size: 8px;
    font-weight: 600;
    color: white;
    line-height: 1.2;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .block-time {
    font-size: 7px;
    color: rgba(255,255,255,0.8);
  }

  /* Editor overlay */
  .editor-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0,0,0,0.5);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 100;
  }

  .editor {
    background: #222;
    border-radius: 12px;
    width: 360px;
    box-shadow: 0 20px 60px rgba(0,0,0,0.5);
  }

  .editor-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 16px 20px;
    border-bottom: 1px solid #333;
  }

  .editor-title { font-size: 15px; font-weight: 600; color: #f0f0f0; }

  .editor-close {
    font-size: 13px;
    color: #999;
    background: none;
    border: none;
    cursor: pointer;
  }

  .editor-close:hover { color: #ccc; }

  .editor-body {
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 16px;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .field label {
    font-size: 12px;
    font-weight: 500;
    color: #aaa;
  }

  .field select {
    padding: 6px 8px;
    font-size: 13px;
    background: rgba(255,255,255,0.06);
    border: 1px solid #444;
    border-radius: 6px;
    color: #f0f0f0;
    outline: none;
  }

  .field-hint {
    font-size: 12px;
    color: #888;
  }

  .day-picker {
    display: flex;
    gap: 5px;
  }

  .day-btn {
    width: 34px;
    height: 34px;
    border-radius: 50%;
    font-size: 12px;
    font-weight: 500;
    background: rgba(255,255,255,0.06);
    border: none;
    color: #aaa;
    cursor: pointer;
    transition: all 0.1s;
  }

  .day-btn.day-selected {
    background: #ec4899;
    color: white;
  }

  .time-row {
    display: flex;
    align-items: center;
    gap: 4px;
  }

  .time-input {
    width: 48px;
    padding: 6px 4px;
    font-size: 20px;
    font-weight: 500;
    text-align: center;
    background: rgba(255,255,255,0.06);
    border: 1px solid #444;
    border-radius: 6px;
    color: #f0f0f0;
    outline: none;
    font-variant-numeric: tabular-nums;
  }

  .time-input:focus { border-color: #ec4899; }

  .time-sep {
    font-size: 20px;
    font-weight: 500;
    color: #999;
  }

  .time-unit {
    font-size: 14px;
    color: #999;
    margin-left: 2px;
  }

  .ampm-toggle {
    display: flex;
    flex-direction: column;
    gap: 2px;
    margin-left: 6px;
  }

  .ampm-toggle button {
    padding: 2px 10px;
    font-size: 11px;
    font-weight: 500;
    background: none;
    border: none;
    border-radius: 4px;
    color: #888;
    cursor: pointer;
  }

  .ampm-toggle button.ampm-active {
    color: #ec4899;
    background: rgba(236,72,153,0.15);
    font-weight: 600;
  }

  .editor-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 14px 20px;
    border-top: 1px solid #333;
  }

  .delete-btn {
    font-size: 13px;
    color: #ef4444;
    background: none;
    border: none;
    cursor: pointer;
  }

  .delete-btn:hover { opacity: 0.8; }

  .save-btn {
    padding: 6px 20px;
    font-size: 13px;
    font-weight: 500;
    background: #ec4899;
    color: white;
    border: none;
    border-radius: 6px;
    cursor: pointer;
  }

  .save-btn:hover { background: #db2777; }
  .save-btn:disabled { opacity: 0.4; cursor: not-allowed; }
</style>
