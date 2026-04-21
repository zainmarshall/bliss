<script>
  import { onMount, onDestroy } from "svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { Timer, Settings as SettingsIcon, Calendar, BarChart3 } from "lucide-svelte";
  import TypingChallenge from "./TypingChallenge.svelte";
  import MinesweeperChallenge from "./MinesweeperChallenge.svelte";
  import WordleChallenge from "./WordleChallenge.svelte";
  import Game2048Challenge from "./Game2048Challenge.svelte";
  import SudokuChallenge from "./SudokuChallenge.svelte";
  import SimonSaysChallenge from "./SimonSaysChallenge.svelte";
  import PipesChallenge from "./PipesChallenge.svelte";
  import CompetitiveChallenge from "./CompetitiveChallenge.svelte";
  import Settings from "./Settings.svelte";
  import Schedule from "./Schedule.svelte";
  import Stats from "./Stats.svelte";
  import GuidedSetup from "./GuidedSetup.svelte";

  let view = $state("loading"); // "loading" | "main" | "panic"
  let showSetup = $state(false);
  let tab = $state("session"); // "session" | "schedule" | "stats" | "settings"
  let panicMode = $state("typing");
  let sessionActive = $state(false);
  let remaining = $state("00:00");
  let remainingSecs = $state(0);
  let lastMinute = $state(false);
  let timerDigits = $state([]);
  let errorMsg = $state("");
  let statusLabel = $state("Inactive");
  let pollInterval;
  let wasActive = false;
  let notifiedStart = false;
  let notified5min = false;
  let sessionStartSecs = 0; // total duration when session started
  let lastScheduleCheck = "";

  let timerDisplay = $derived.by(() => {
    if (sessionActive) return remaining;
    let slots = [null, null, null, null, null, null];
    let count = timerDigits.length;
    for (let i = 0; i < count; i++) {
      let slotIndex = 6 - count + i;
      if (slotIndex >= 0 && slotIndex < 6) slots[slotIndex] = timerDigits[i];
    }
    return slots;
  });

  let totalSeconds = $derived.by(() => {
    let slots = [0, 0, 0, 0, 0, 0];
    let count = timerDigits.length;
    for (let i = 0; i < count; i++) {
      let slotIndex = 6 - count + i;
      if (slotIndex >= 0 && slotIndex < 6) slots[slotIndex] = timerDigits[i];
    }
    return (slots[0] * 10 + slots[1]) * 3600 + (slots[2] * 10 + slots[3]) * 60 + (slots[4] * 10 + slots[5]);
  });

  async function pollStatus() {
    try {
      let status = await invoke("get_session_status");
      let prevActive = sessionActive;
      sessionActive = status.active;
      remaining = status.remaining;
      remainingSecs = status.remaining_secs;
      statusLabel = status.active ? "Active" : "Inactive";
      lastMinute = status.active && status.remaining_secs > 0 && status.remaining_secs <= 60;

      // Notifications + stats
      if (status.active && !prevActive && !notifiedStart) {
        notifiedStart = true;
        notified5min = false;
        sessionStartSecs = status.remaining_secs;
        let mins = Math.ceil(status.remaining_secs / 60);
        invoke("send_notification", { title: "Bliss", body: `${mins} min session started` });
      }
      if (status.active && status.remaining_secs <= 300 && status.remaining_secs > 0 && !notified5min && sessionStartSecs > 300) {
        notified5min = true;
        invoke("send_notification", { title: "Bliss", body: "5 minutes left" });
      }
      if (!status.active && prevActive && wasActive) {
        // Session ended - record actual elapsed time, not planned
        let elapsedSecs = sessionStartSecs - status.remaining_secs;
        let elapsedMins = Math.max(1, Math.round(elapsedSecs / 60));
        invoke("stats_record_session", { minutes: elapsedMins });
        invoke("send_notification", { title: "Bliss", body: "Session done" });
        notifiedStart = false;
        notified5min = false;
      }
      wasActive = status.active;

      // Schedule check (every minute)
      if (!status.active) {
        checkSchedules();
      }
    } catch (e) {
      console.error("poll error:", e);
    }
  }

  async function checkSchedules() {
    let now = new Date();
    let key = `${now.getHours()}:${now.getMinutes()}`;
    if (key === lastScheduleCheck) return;
    lastScheduleCheck = key;

    try {
      let schedules = await invoke("schedule_list");
      let dayOfWeek = now.getDay(); // 0=Sun
      let weekday = dayOfWeek === 0 ? 1 : dayOfWeek + 1; // 1=Sun, 2=Mon, ...
      let hour = now.getHours();
      let minute = now.getMinutes();

      for (let s of schedules) {
        if (!s.enabled) continue;
        if (!s.days.includes(weekday)) continue;
        if (s.hour !== hour || s.minute !== minute) continue;

        // Fire this schedule - apply its config then start session
        let profiles = await invoke("profile_list");
        let profile = profiles.find(p => p.name === s.configName);
        if (profile) {
          await invoke("profile_apply", { profile });
        }
        await invoke("start_session", { seconds: s.durationMinutes * 60 });
        await pollStatus();
        break;
      }
    } catch (e) {
      console.error("schedule check error:", e);
    }
  }

  function handleKeydown(e) {
    if (sessionActive || view !== "main" || tab !== "session") return;
    if (e.key >= "0" && e.key <= "9" && timerDigits.length < 6) {
      timerDigits = [...timerDigits, parseInt(e.key)];
    } else if (e.key === "Backspace") {
      timerDigits = timerDigits.slice(0, -1);
    } else if (e.key === "Enter") {
      startSession();
    }
  }

  async function startSession() {
    errorMsg = "";
    let secs = totalSeconds;
    if (secs <= 0) secs = 25 * 60;
    try {
      let result = await invoke("start_session", { seconds: secs });
      if (result.error) {
        errorMsg = result.error;
      } else {
        timerDigits = [];
        await pollStatus();
      }
    } catch (e) {
      errorMsg = String(e);
    }
  }

  async function handlePanicSuccess() {
    try {
      let result = await invoke("run_panic");
      if (result.error) return false;
      invoke("play_sound", { name: "success" });
      view = "main";
      await pollStatus();
      return true;
    } catch (e) {
      return false;
    }
  }

  async function openPanic() {
    try {
      panicMode = await invoke("config_panic_mode_get");
    } catch (e) {}
    view = "panic";
  }

  function cancelPanic() {
    view = "session";
  }

  function handleSetupComplete() {
    showSetup = false;
  }

  onMount(async () => {
    try {
      let boot = await invoke("app_boot");
      showSetup = !boot.setup_complete;
      if (!boot.setup_complete) tab = "settings";

      // Sync challenge configs to localStorage in one shot
      const fileToKey = {
        minesweeper_size: "minesweeper_size",
        wordle_difficulty: "wordle_difficulty",
        game2048_difficulty: "2048_difficulty",
        sudoku_difficulty: "sudoku_difficulty",
        simon_difficulty: "simon_difficulty",
        pipes_size: "pipes_size",
        panic_difficulty: "cp_difficulty",
      };
      const defaults = {
        minesweeper_size: "medium", wordle_difficulty: "easy", "2048_difficulty": "medium",
        sudoku_difficulty: "medium", simon_difficulty: "medium", pipes_size: "medium", cp_difficulty: "easy",
      };
      let configs = { ...defaults };
      for (let [fileKey, uiKey] of Object.entries(fileToKey)) {
        if (boot.challenge_configs[fileKey]) {
          configs[uiKey] = boot.challenge_configs[fileKey];
        }
      }
      localStorage.setItem("bliss_panic_configs", JSON.stringify(configs));
    } catch {}
    view = "main";
    pollStatus();
    pollInterval = setInterval(pollStatus, 1000);
  });

  onDestroy(() => {
    if (pollInterval) clearInterval(pollInterval);
  });
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="app">
  {#if showSetup}
    <GuidedSetup onComplete={handleSetupComplete} />
  {/if}

  {#if view === "loading"}
    <div class="loading"></div>
  {:else if view === "panic"}
    {#if panicMode === "minesweeper"}
      <MinesweeperChallenge onSuccess={handlePanicSuccess} onCancel={cancelPanic} />
    {:else if panicMode === "wordle"}
      <WordleChallenge onSuccess={handlePanicSuccess} onCancel={cancelPanic} />
    {:else if panicMode === "2048"}
      <Game2048Challenge onSuccess={handlePanicSuccess} onCancel={cancelPanic} />
    {:else if panicMode === "sudoku"}
      <SudokuChallenge onSuccess={handlePanicSuccess} onCancel={cancelPanic} />
    {:else if panicMode === "simon"}
      <SimonSaysChallenge onSuccess={handlePanicSuccess} onCancel={cancelPanic} />
    {:else if panicMode === "pipes"}
      <PipesChallenge onSuccess={handlePanicSuccess} onCancel={cancelPanic} />
    {:else if panicMode === "competitive"}
      <CompetitiveChallenge onSuccess={handlePanicSuccess} onCancel={cancelPanic} />
    {:else}
      <TypingChallenge onSuccess={handlePanicSuccess} onCancel={cancelPanic} />
    {/if}
  {:else}
    <div class="tab-bar">
      <button class="tab" class:active={tab === "session"} data-tab="session" onclick={() => (tab = "session")}>
        <Timer size={16} />
        Session
      </button>
      <button class="tab" class:active={tab === "schedule"} data-tab="schedule" onclick={() => (tab = "schedule")}>
        <Calendar size={16} />
        Schedule
      </button>
      <button class="tab" class:active={tab === "stats"} data-tab="stats" onclick={() => (tab = "stats")}>
        <BarChart3 size={16} />
        Stats
      </button>
      <button class="tab" class:active={tab === "settings"} data-tab="settings" onclick={() => (tab = "settings")}>
        <SettingsIcon size={16} />
        Settings
      </button>
    </div>
    <div class="tab-divider"></div>

    {#if tab === "session"}
      <div class="session-view">
        {#if errorMsg}
          <div class="error-banner">
            <span>{errorMsg}</span>
            <button class="dismiss-btn" onclick={() => (errorMsg = "")}>Dismiss</button>
          </div>
        {/if}

        <div class="center-content">
          <h1 class="title">Bliss</h1>
          <p class="status" class:active={sessionActive}>{statusLabel}</p>

          {#if sessionActive}
            <div class="timer">{remaining}</div>
            <button class="panic-btn" onclick={openPanic}>Panic</button>
          {:else}
            <div class="timer-input">
              {#each [0, 1] as i}
                <span class="digit" class:filled={timerDisplay[i] !== null}>{timerDisplay[i] !== null ? timerDisplay[i] : "-"}</span>
              {/each}
              <span class="colon" class:has-input={timerDigits.length > 0}>:</span>
              {#each [2, 3] as i}
                <span class="digit" class:filled={timerDisplay[i] !== null}>{timerDisplay[i] !== null ? timerDisplay[i] : "-"}</span>
              {/each}
              <span class="colon" class:has-input={timerDigits.length > 0}>:</span>
              {#each [4, 5] as i}
                {#if i === 5}
                  <span class="digit" class:filled={timerDisplay[i] !== null}>
                    {timerDisplay[i] !== null ? timerDisplay[i] : "-"}
                    {#if timerDigits.length < 6}
                      <span class="blink-cursor"></span>
                    {/if}
                  </span>
                {:else}
                  <span class="digit" class:filled={timerDisplay[i] !== null}>{timerDisplay[i] !== null ? timerDisplay[i] : "-"}</span>
                {/if}
              {/each}
            </div>
            <button class="start-btn" onclick={startSession}>Start</button>
          {/if}
        </div>
      </div>
    {:else if tab === "schedule"}
      <Schedule {sessionActive} />
    {:else if tab === "stats"}
      <Stats />
    {:else}
      <Settings {sessionActive} />
    {/if}
  {/if}
</div>

<style>
  :global(body) {
    margin: 0;
    padding: 0;
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
    background: #1a1a1a;
    color: #f0f0f0;
    user-select: none;
    -webkit-user-select: none;
    overflow: hidden;
    height: 100vh;
  }

  :global(#app) {
    height: 100vh;
  }

  .app {
    height: 100vh;
    display: flex;
    flex-direction: column;
  }

  .loading {
    flex: 1;
  }

  .tab-bar {
    display: flex;
    justify-content: center;
    gap: 0;
    padding: 8px 12px 0;
  }

  .tab {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 8px 16px;
    font-size: 13px;
    font-weight: 400;
    color: #999;
    background: none;
    border: none;
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.15s;
  }

  .tab.active {
    font-weight: 600;
    color: #ec4899;
    background: rgba(236, 72, 153, 0.1);
  }

  .tab:hover:not(.active) {
    color: #aaa;
  }

  .tab-divider {
    height: 1px;
    background: #2a2a2a;
    margin-top: 4px;
  }

  .session-view {
    flex: 1;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    position: relative;
  }

  .error-banner {
    position: absolute;
    top: 16px;
    left: 20px;
    right: 20px;
    background: rgba(220, 50, 50, 0.85);
    color: white;
    padding: 10px 16px;
    border-radius: 8px;
    font-size: 13px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 12px;
  }

  .dismiss-btn {
    background: none;
    border: none;
    color: rgba(255, 255, 255, 0.7);
    cursor: pointer;
    font-size: 12px;
    padding: 2px 8px;
  }

  .center-content {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 8px;
  }

  .title {
    font-size: 22px;
    font-weight: 600;
    color: #f0f0f0;
    margin: 0;
    letter-spacing: -0.3px;
  }

  .status {
    font-size: 14px;
    color: #999;
    margin: 0;
  }

  .status.active {
    color: #4ade80;
  }

  .timer {
    font-size: 56px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    letter-spacing: 2px;
    color: #f0f0f0;
    margin: 12px 0;
    font-family: "SF Pro Rounded", -apple-system, BlinkMacSystemFont, sans-serif;
    transition: color 0.3s;
  }

  .timer-input {
    display: flex;
    align-items: center;
    font-size: 56px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    letter-spacing: 2px;
    font-family: "SF Pro Rounded", -apple-system, BlinkMacSystemFont, sans-serif;
    margin: 12px 0;
  }

  .digit {
    color: rgba(255, 255, 255, 0.15);
    padding: 0 1px;
    position: relative;
  }

  .digit.filled {
    color: #f0f0f0;
  }

  .colon {
    color: rgba(255, 255, 255, 0.15);
    padding: 0 2px;
  }

  .colon.has-input {
    color: rgba(255, 255, 255, 0.3);
  }

  .blink-cursor {
    position: absolute;
    inset: 2px -2px;
    background: rgba(255, 255, 255, 0.15);
    border-radius: 4px;
    animation: block-blink 1s ease-in-out infinite alternate;
    pointer-events: none;
  }

  @keyframes block-blink {
    from { opacity: 1; }
    to { opacity: 0; }
  }

  .start-btn {
    margin-top: 8px;
    padding: 8px 32px;
    font-size: 15px;
    font-weight: 500;
    background: #ec4899;
    color: white;
    border: none;
    border-radius: 8px;
    cursor: pointer;
    transition: background 0.15s;
  }

  .start-btn:hover {
    background: #db2777;
  }

  .start-btn:active {
    background: #be185d;
  }

  .panic-btn {
    margin-top: 8px;
    padding: 6px 20px;
    font-size: 14px;
    font-weight: 500;
    background: none;
    color: #ef4444;
    border: none;
    cursor: pointer;
    transition: opacity 0.15s;
  }

  .panic-btn:hover {
    opacity: 0.7;
  }
</style>
