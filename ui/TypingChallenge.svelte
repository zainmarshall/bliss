<script>
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";

  let { onSuccess, onCancel } = $props();

  let quote = $state("");
  let typed = $state("");
  let submitting = $state(false);
  let inputEl;

  let progress = $derived(quote.length > 0 ? typed.length / quote.length : 0);

  let accuracy = $derived.by(() => {
    if (!quote || typed.length < quote.length) return 0;
    let correct = 0;
    for (let i = 0; i < quote.length; i++) {
      if (typed[i] === quote[i]) correct++;
    }
    return (correct / quote.length) * 100;
  });

  let renderedChars = $derived.by(() => {
    let chars = [];
    for (let i = 0; i < quote.length; i++) {
      let state = "pending";
      if (i < typed.length) {
        state = typed[i] === quote[i] ? "correct" : "wrong";
      } else if (i === typed.length) {
        state = "cursor";
      }
      chars.push({ ch: quote[i], state });
    }
    for (let i = quote.length; i < typed.length; i++) {
      chars.push({ ch: typed[i], state: "extra" });
    }
    return chars;
  });

  async function loadQuote() {
    try {
      quote = await invoke("get_random_quote");
    } catch (e) {
      quote = "Focus is a practice, not a mood, and it grows with repetition.";
    }
  }

  function handleInput(e) {
    let val = e.target.value;
    let filtered = "";
    for (let ch of val) {
      if (ch === " " || (ch >= "!" && ch <= "~")) filtered += ch;
    }
    let maxLen = quote.length + 20;
    if (filtered.length > maxLen) filtered = filtered.slice(0, maxLen);
    typed = filtered;
  }

  async function handleSubmit() {
    if (accuracy < 100) return;
    submitting = true;
    let ok = await onSuccess();
    submitting = false;
  }

  function handleKeydown(e) {
    if (e.key === "Enter") {
      e.preventDefault();
      handleSubmit();
    }
  }

  onMount(() => {
    loadQuote();
    if (inputEl) inputEl.focus();
  });
</script>

<div class="panic-view">
  <div class="panic-card">
    <div class="panic-header">
      <h2>Typing Challenge</h2>
      <p class="subtitle">Type the quote below with 100% accuracy to unlock.</p>
    </div>

    <!-- svelte-ignore a11y_click_events_have_key_events a11y_no_static_element_interactions -->
    <div class="quote-display" onclick={() => inputEl?.focus()}>
      {#each renderedChars as { ch, state }}
        <span class="char {state}">{ch}</span>
      {/each}
    </div>

    <div class="progress-bar">
      <div class="progress-fill" class:complete={accuracy >= 100} style="width: {Math.min(progress * 100, 100)}%"></div>
    </div>
    <p class="char-count">{typed.length} / {quote.length}</p>

    <textarea
      bind:this={inputEl}
      value={typed}
      oninput={handleInput}
      onkeydown={handleKeydown}
      class="hidden-input"
      spellcheck="false"
      autocomplete="off"
      autocorrect="off"
    ></textarea>

    <div class="actions">
      <button class="cancel-btn" onclick={onCancel}>Cancel</button>
      <div class="right-actions">
        {#if submitting}
          <span class="spinner"></span>
        {/if}
        <button class="submit-btn" onclick={handleSubmit} disabled={submitting || accuracy < 100}>Submit</button>
      </div>
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
    max-width: 600px;
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

  .quote-display {
    font-family: "SF Mono", "Menlo", "Consolas", monospace;
    font-size: 17px;
    line-height: 1.7;
    padding: 12px 0;
    cursor: text;
  }

  .char {
    transition: color 0.05s;
  }

  .char.pending {
    color: #555;
  }

  .char.cursor {
    color: #555;
    border-bottom: 2px solid #ec4899;
  }

  .char.correct {
    color: #4ade80;
  }

  .char.wrong {
    color: #ef4444;
    text-decoration: underline;
    text-decoration-color: #ef4444;
  }

  .char.extra {
    color: #ef4444;
    background: rgba(239, 68, 68, 0.15);
  }

  .progress-bar {
    height: 3px;
    background: #333;
    border-radius: 2px;
    overflow: hidden;
  }

  .progress-fill {
    height: 100%;
    background: #ec4899;
    border-radius: 2px;
    transition: width 0.1s;
  }

  .progress-fill.complete {
    background: #4ade80;
  }

  .char-count {
    font-size: 12px;
    color: #666;
    font-variant-numeric: tabular-nums;
    margin: 0;
  }

  .hidden-input {
    position: absolute;
    opacity: 0.01;
    width: 1px;
    height: 1px;
    pointer-events: none;
  }

  .actions {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-top: 4px;
  }

  .right-actions {
    display: flex;
    align-items: center;
    gap: 8px;
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

  .submit-btn {
    padding: 6px 20px;
    font-size: 13px;
    font-weight: 500;
    background: #ec4899;
    color: white;
    border: none;
    border-radius: 6px;
    cursor: pointer;
    transition: background 0.15s;
  }

  .submit-btn:hover {
    background: #db2777;
  }

  .submit-btn:disabled {
    opacity: 0.3;
    cursor: not-allowed;
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
