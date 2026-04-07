<script>
  import { onMount, onDestroy } from "svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { Timer, Settings as SettingsIcon } from "lucide-svelte";
  import TypingChallenge from "./TypingChallenge.svelte";
  import MinesweeperChallenge from "./MinesweeperChallenge.svelte";
  import WordleChallenge from "./WordleChallenge.svelte";
  import Game2048Challenge from "./Game2048Challenge.svelte";
  import SudokuChallenge from "./SudokuChallenge.svelte";
  import SimonSaysChallenge from "./SimonSaysChallenge.svelte";
  import PipesChallenge from "./PipesChallenge.svelte";
  import CompetitiveChallenge from "./CompetitiveChallenge.svelte";
  import Settings from "./Settings.svelte";

  let view = $state("session"); // "session" | "panic"
  let tab = $state("session"); // "session" | "settings"
  let panicMode = $state("typing");
  let sessionActive = $state(false);
  let remaining = $state("00:00:00");
  let remainingSecs = $state(0);
  let lastMinute = $state(false);
  let timerDigits = $state([]);
  let errorMsg = $state("");
  let statusLabel = $state("Inactive");
  let pollInterval;

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
      sessionActive = status.active;
      remaining = status.remaining;
      remainingSecs = status.remaining_secs;
      statusLabel = status.active ? "Active" : "Inactive";
      lastMinute = status.active && status.remaining_secs > 0 && status.remaining_secs <= 60;
    } catch (e) {
      console.error("poll error:", e);
    }
  }

  function handleKeydown(e) {
    if (sessionActive || view !== "session" || tab !== "session") return;
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
      view = "session";
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

  onMount(() => {
    pollStatus();
    pollInterval = setInterval(pollStatus, 1000);
  });

  onDestroy(() => {
    if (pollInterval) clearInterval(pollInterval);
  });
</script>

<svelte:window onkeydown={handleKeydown} />

<div class="app">
  {#if view === "panic"}
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
      <button class="tab" class:active={tab === "session"} onclick={() => (tab = "session")}>
        <Timer size={16} />
        Session
      </button>
      <button class="tab" class:active={tab === "settings"} onclick={() => (tab = "settings")}>
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
    color: #e0e0e0;
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
    padding: 8px 20px;
    font-size: 14px;
    font-weight: 400;
    color: #888;
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
    color: #e0e0e0;
    margin: 0;
    letter-spacing: -0.3px;
  }

  .status {
    font-size: 14px;
    color: #888;
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
    color: #e0e0e0;
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
    color: #e0e0e0;
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
