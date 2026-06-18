<script>
  import { onMount, tick } from "svelte";
  import { invoke } from "@tauri-apps/api/core";

  let { sessionActive } = $props();

  let blocks = $state([]);
  let gridEl;

  // Drag state
  let dragging = $state(false);
  let dragDay = $state(0);
  let dragStartY = $state(0);
  let dragCurrentY = $state(0);

  // Edit popover
  let editing = $state(null);
  let popX = $state(0);
  let popY = $state(0);
  let editStartDay = $state(0);
  let editStartHour = $state(0);
  let editStartMin = $state(0);
  let editEndDay = $state(0);
  let editEndHour = $state(0);
  let editEndMin = $state(0);

  const PX_PER_HOUR = 52;
  const dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
  const hours = Array.from({ length: 24 }, (_, i) => i);

  function timeFromY(y) {
    let totalMin = Math.round((y / PX_PER_HOUR) * 60 / 15) * 15;
    totalMin = Math.max(0, Math.min(totalMin, 24 * 60));
    return { hour: Math.floor(totalMin / 60), minute: totalMin % 60 };
  }

  function yFromTime(hour, minute) {
    return (hour + minute / 60) * PX_PER_HOUR;
  }

  function formatHour(h) {
    if (h === 0) return "12a";
    if (h < 12) return `${h}a`;
    if (h === 12) return "12p";
    return `${h - 12}p`;
  }

  function formatTime(h, m) {
    let hr = h % 12 || 12;
    let ampm = h < 12 ? "AM" : "PM";
    return m === 0 ? `${hr} ${ampm}` : `${hr}:${String(m).padStart(2, "0")} ${ampm}`;
  }

  // Get visual segments for a block (handles midnight spanning)
  function blockSegments(block) {
    let segs = [];
    let startY = yFromTime(block.startHour, block.startMinute);
    let endY = yFromTime(block.endHour, block.endMinute);

    if (block.startDay === block.endDay) {
      if (endY > startY) {
        segs.push({ day: block.startDay, top: startY, height: endY - startY, block });
      }
    } else {
      // Spans midnight: segment 1 on start day, segment 2 on end day
      let dayEndY = 24 * PX_PER_HOUR;
      if (dayEndY > startY) {
        segs.push({ day: block.startDay, top: startY, height: dayEndY - startY, block });
      }
      if (endY > 0) {
        segs.push({ day: block.endDay, top: 0, height: endY, block });
      }
    }
    return segs;
  }

  let allSegments = $derived.by(() => {
    let segs = [];
    for (let b of blocks) {
      if (b.enabled) segs.push(...blockSegments(b));
    }
    return segs;
  });

  function segmentsForDay(day) {
    return allSegments.filter(s => s.day === day);
  }

  // Drag preview
  let dragPreview = $derived.by(() => {
    if (!dragging) return null;
    let y1 = Math.min(dragStartY, dragCurrentY);
    let y2 = Math.max(dragStartY, dragCurrentY);
    let t1 = timeFromY(y1);
    let t2 = timeFromY(y2);
    return { day: dragDay, top: yFromTime(t1.hour, t1.minute), height: yFromTime(t2.hour, t2.minute) - yFromTime(t1.hour, t1.minute), t1, t2 };
  });

  function handleMouseDown(day, e) {
    if (sessionActive || editing) return;
    let rect = e.currentTarget.getBoundingClientRect();
    let y = e.clientY - rect.top;
    dragDay = day;
    dragStartY = y;
    dragCurrentY = y;
    dragging = true;
  }

  function handleMouseMove(e) {
    if (!dragging) return;
    let cols = gridEl?.querySelectorAll(".cal-col");
    if (!cols || !cols[dragDay]) return;
    let rect = cols[dragDay].getBoundingClientRect();
    dragCurrentY = Math.max(0, Math.min(e.clientY - rect.top, 24 * PX_PER_HOUR));
  }

  function handleMouseUp() {
    if (!dragging) return;
    dragging = false;
    let y1 = Math.min(dragStartY, dragCurrentY);
    let y2 = Math.max(dragStartY, dragCurrentY);
    let t1 = timeFromY(y1);
    let t2 = timeFromY(y2);
    // Need at least 15 min
    if (t1.hour === t2.hour && t1.minute === t2.minute) {
      t2.minute += 60;
      if (t2.minute >= 60) { t2.hour += 1; t2.minute -= 60; }
      if (t2.hour >= 24) { t2.hour = 23; t2.minute = 45; }
    }
    let block = {
      id: crypto.randomUUID(),
      startDay: dragDay, startHour: t1.hour, startMinute: t1.minute,
      endDay: dragDay, endHour: t2.hour, endMinute: t2.minute,
      enabled: true,
    };
    blocks = [...blocks, block];
    saveBlocks();
  }

  function openEdit(block, e) {
    if (sessionActive) return;
    e.stopPropagation();
    editing = block;
    editStartDay = block.startDay;
    editStartHour = block.startHour;
    editStartMin = block.startMinute;
    editEndDay = block.endDay;
    editEndHour = block.endHour;
    editEndMin = block.endMinute;

    let rect = e.currentTarget.getBoundingClientRect();
    popX = Math.min(rect.right + 8, window.innerWidth - 260);
    popY = Math.max(rect.top, 8);
    if (popY + 240 > window.innerHeight) popY = window.innerHeight - 250;
  }

  function saveEdit() {
    if (!editing) return;
    blocks = blocks.map(b => b.id === editing.id ? {
      ...b,
      startDay: editStartDay, startHour: editStartHour, startMinute: editStartMin,
      endDay: editEndDay, endHour: editEndHour, endMinute: editEndMin,
    } : b);
    editing = null;
    saveBlocks();
  }

  function deleteBlock() {
    if (!editing) return;
    blocks = blocks.filter(b => b.id !== editing.id);
    editing = null;
    saveBlocks();
  }

  function closePopover() { editing = null; }

  async function loadBlocks() {
    blocks = await invoke("schedule_list");
  }

  async function saveBlocks() {
    await invoke("schedule_save", { entries: blocks });
  }

  onMount(async () => {
    await loadBlocks();
    // Scroll to 7 AM
    await tick();
    if (gridEl) gridEl.scrollTop = 7 * PX_PER_HOUR;
  });
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="schedule" bind:this={gridEl} onmousemove={handleMouseMove} onmouseup={handleMouseUp}>
  <!-- Day headers -->
  <div class="cal-header">
    <div class="hour-gutter"></div>
    {#each dayNames as name, i}
      <div class="day-header">{name}</div>
    {/each}
  </div>

  <!-- Grid body -->
  <div class="cal-body">
    <!-- Hour labels -->
    <div class="hour-gutter">
      {#each hours as h}
        <div class="hour-label" style="height:{PX_PER_HOUR}px">{formatHour(h)}</div>
      {/each}
    </div>

    <!-- Day columns -->
    {#each dayNames as _, day}
      <!-- svelte-ignore a11y_no_static_element_interactions -->
      <div class="cal-col" onmousedown={(e) => handleMouseDown(day, e)}>
        {#each hours as h}
          <div class="hour-cell" class:even={h % 2 === 0} style="height:{PX_PER_HOUR}px"></div>
        {/each}

        <!-- Blocks -->
        {#each segmentsForDay(day) as seg}
          <!-- svelte-ignore a11y_no_static_element_interactions -->
          <div
            class="block"
            style="top:{seg.top}px;height:{Math.max(seg.height, 14)}px"
            onmousedown={(e) => { e.stopPropagation(); openEdit(seg.block, e); }}
          >
            <span class="block-time">{formatTime(seg.block.startHour, seg.block.startMinute)}</span>
          </div>
        {/each}

        <!-- Drag preview -->
        {#if dragging && dragPreview && dragDay === day}
          <div class="block preview" style="top:{dragPreview.top}px;height:{Math.max(dragPreview.height, 14)}px">
            <span class="block-time">{formatTime(dragPreview.t1.hour, dragPreview.t1.minute)} - {formatTime(dragPreview.t2.hour, dragPreview.t2.minute)}</span>
          </div>
        {/if}
      </div>
    {/each}
  </div>

  <!-- Edit popover -->
  {#if editing}
    <!-- svelte-ignore a11y_no_static_element_interactions a11y_click_events_have_key_events -->
    <div class="popover-backdrop" onclick={closePopover}></div>
    <!-- svelte-ignore a11y_no_static_element_interactions a11y_click_events_have_key_events -->
    <div class="popover" style="left:{popX}px;top:{popY}px" onclick={(e) => e.stopPropagation()}>
      <div class="pop-row">
        <label>Start</label>
        <select bind:value={editStartDay}>{#each dayNames as n, i}<option value={i}>{n}</option>{/each}</select>
        <input type="number" min="0" max="23" bind:value={editStartHour} class="time-in" />
        <span class="colon">:</span>
        <input type="number" min="0" max="59" step="15" bind:value={editStartMin} class="time-in" />
      </div>
      <div class="pop-row">
        <label>End</label>
        <select bind:value={editEndDay}>{#each dayNames as n, i}<option value={i}>{n}</option>{/each}</select>
        <input type="number" min="0" max="23" bind:value={editEndHour} class="time-in" />
        <span class="colon">:</span>
        <input type="number" min="0" max="59" step="15" bind:value={editEndMin} class="time-in" />
      </div>
      <div class="pop-actions">
        <button class="pop-delete" onclick={deleteBlock}>Delete</button>
        <button class="pop-save" onclick={saveEdit}>Save</button>
      </div>
    </div>
  {/if}
</div>

<style>
  .schedule { flex: 1; overflow-y: auto; overflow-x: hidden; position: relative; background: #1a1a1a; }

  .cal-header { display: flex; position: sticky; top: 0; z-index: 5; background: #1a1a1a; border-bottom: 1px solid #2a2a2a; }
  .cal-header .hour-gutter { width: 36px; flex-shrink: 0; }
  .day-header { flex: 1; text-align: center; font-size: 11px; font-weight: 500; color: #999; padding: 8px 0; }

  .cal-body { display: flex; position: relative; }

  .hour-gutter { width: 36px; flex-shrink: 0; }
  .hour-label { font-size: 10px; color: #666; display: flex; align-items: flex-start; justify-content: flex-end; padding: 0 4px 0 0; box-sizing: border-box; }

  .cal-col { flex: 1; position: relative; cursor: crosshair; min-width: 0; }
  .hour-cell { border-top: 1px solid rgba(255,255,255,0.04); box-sizing: border-box; }
  .hour-cell.even { background: rgba(255,255,255,0.01); }

  .block {
    position: absolute; left: 2px; right: 2px; border-radius: 4px; padding: 2px 4px;
    background: rgba(236,72,153,0.25); border-left: 3px solid #ec4899;
    cursor: pointer; overflow: hidden; z-index: 2; transition: background 0.1s;
  }
  .block:hover { background: rgba(236,72,153,0.35); }
  .block.preview { background: rgba(236,72,153,0.15); border-left-color: rgba(236,72,153,0.5); pointer-events: none; }
  .block-time { font-size: 9px; color: #ec4899; white-space: nowrap; }

  .popover-backdrop { position: fixed; inset: 0; z-index: 50; }
  .popover {
    position: fixed; z-index: 60; width: 240px; background: #252525; border: 1px solid #3a3a3a;
    border-radius: 10px; padding: 12px; box-shadow: 0 8px 24px rgba(0,0,0,0.5);
  }
  .pop-row { display: flex; align-items: center; gap: 6px; margin-bottom: 8px; }
  .pop-row label { font-size: 11px; color: #999; width: 32px; flex-shrink: 0; }
  .pop-row select { flex: 1; padding: 3px 4px; font-size: 12px; background: rgba(255,255,255,0.06); border: 1px solid #444; border-radius: 4px; color: #f0f0f0; outline: none; }
  .time-in { width: 32px; padding: 3px 4px; font-size: 12px; text-align: center; background: rgba(255,255,255,0.06); border: 1px solid #444; border-radius: 4px; color: #f0f0f0; outline: none; }
  .time-in:focus { border-color: #ec4899; }
  .colon { color: #666; font-size: 12px; }

  .pop-actions { display: flex; justify-content: space-between; margin-top: 4px; }
  .pop-delete { font-size: 12px; color: #ef4444; background: none; border: none; cursor: pointer; }
  .pop-delete:hover { opacity: 0.8; }
  .pop-save { padding: 4px 14px; font-size: 12px; font-weight: 500; background: #ec4899; color: white; border: none; border-radius: 5px; cursor: pointer; }
  .pop-save:hover { background: #db2777; }
</style>
