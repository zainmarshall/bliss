<script>
  import { onMount, tick } from "svelte";
  import { invoke } from "@tauri-apps/api/core";

  let { onComplete } = $props();

  let step = $state(-1);
  let bubbleStyle = $state("");
  let arrowClass = $state("arrow-bottom");
  let spotlightStyle = $state("");
  let showSpotlight = $state(false);
  let websites = $state([]);
  let apps = $state([]);
  let panicMode = $state("typing");

  async function refreshCounts() {
    try {
      websites = await invoke("config_website_list");
      apps = await invoke("config_app_list");
      panicMode = await invoke("config_panic_mode_get");
    } catch {}
  }

  const tourSteps = [
    {
      selector: '.sub-tabs button:first-child',
      sidebarClick: "blocking",
      title: "Block sites",
      text: "Add sites you waste time on. Use the presets or type your own. Add at least one to continue.",
      position: "bottom",
      canContinue: () => websites.length > 0,
      blockReason: "Add at least one site first",
    },
    {
      selector: '.sub-tabs button:nth-child(2)',
      clickTarget: '.sub-tabs button:nth-child(2)',
      title: "Block apps",
      text: "Pick apps that pull you out of focus. They get force-quit when you start a session.",
      position: "bottom",
      canContinue: () => true,
    },
    {
      selector: '.sidebar-item[data-section="panic"]',
      sidebarClick: "panic",
      title: "Pick your panic challenge",
      text: "If you need out early, you solve this first. Harder challenge = harder to quit.",
      position: "right",
      canContinue: () => true,
    },
    {
      selector: '.tab[data-tab="session"]',
      title: "Start a session",
      text: "Type a duration, hit enter. That's it.",
      position: "bottom",
      canContinue: () => true,
    },
  ];

  function positionBubble(el) {
    if (!el) { showSpotlight = false; return; }
    let rect = el.getBoundingClientRect();
    let s = tourSteps[step];
    showSpotlight = true;

    let pad = 6;
    spotlightStyle = `top:${rect.top - pad}px;left:${rect.left - pad}px;width:${rect.width + pad * 2}px;height:${rect.height + pad * 2}px`;

    let bw = 280;
    if (s.position === "right") {
      let top = rect.top + rect.height / 2 - 60;
      let left = rect.right + 16;
      arrowClass = "arrow-left";
      bubbleStyle = `top:${Math.max(8, top)}px;left:${left}px`;
    } else {
      let top = rect.bottom + 12;
      let left = rect.left + rect.width / 2 - bw / 2;
      left = Math.max(8, Math.min(left, window.innerWidth - bw - 8));
      arrowClass = "arrow-top";
      bubbleStyle = `top:${top}px;left:${left}px`;
    }
  }

  let blockMsg = $state("");

  async function goToStep(idx) {
    // Check if current step allows continuing
    if (step >= 0 && step < tourSteps.length) {
      await refreshCounts();
      let current = tourSteps[step];
      if (current.canContinue && !current.canContinue()) {
        blockMsg = current.blockReason || "Complete this step first";
        setTimeout(() => blockMsg = "", 2000);
        return;
      }
    }
    blockMsg = "";
    step = idx;
    if (step >= tourSteps.length) {
      await invoke("setup_complete_mark");
      onComplete();
      return;
    }

    let s = tourSteps[step];

    if (s.sidebarClick) {
      let btn = document.querySelector(`.sidebar-item[data-section="${s.sidebarClick}"]`);
      if (btn) btn.click();
    }
    if (s.clickTarget) {
      await tick();
      let btn = document.querySelector(s.clickTarget);
      if (btn) btn.click();
    }
    if (s.selector?.startsWith('.tab[data-tab=')) {
      let btn = document.querySelector(s.selector);
      if (btn) btn.click();
    }

    await tick();
    await new Promise(r => setTimeout(r, 120));

    let el = document.querySelector(s.selector);
    positionBubble(el);
  }

  function startTour() {
    let settingsTab = document.querySelector('.tab[data-tab="settings"]');
    if (settingsTab) settingsTab.click();
    setTimeout(() => goToStep(0), 200);
  }

  async function skipTour() {
    await invoke("setup_complete_mark");
    onComplete();
  }

  onMount(() => {
    refreshCounts();
    setTimeout(() => { step = -1; }, 100);
  });
</script>

<svelte:window onkeydown={(e) => {
  if (step === -1 && e.key === "Enter") startTour();
  else if (step >= 0 && e.key === "Enter") goToStep(step + 1);
  else if (e.key === "Escape") skipTour();
}} />

{#if step === -1}
  <div class="welcome-overlay">
    <div class="welcome-card">
      <div class="welcome-logo">Bliss</div>
      <p class="welcome-sub">Block distractions. Stay focused.</p>
      <div class="welcome-actions">
        <button class="welcome-start" onclick={startTour}>Set up</button>
        <button class="welcome-skip" onclick={skipTour}>I'll figure it out</button>
      </div>
    </div>
  </div>
{:else if step >= 0 && step < tourSteps.length}
  <div class="tour-overlay" onclick={() => goToStep(step + 1)}>
    {#if showSpotlight}
      <div class="spotlight" style={spotlightStyle}></div>
    {/if}
  </div>
  <!-- svelte-ignore a11y_no_static_element_interactions a11y_click_events_have_key_events -->
  <div class="tour-bubble {arrowClass}" style={bubbleStyle} onclick={(e) => e.stopPropagation()}>
    <div class="bubble-step">{step + 1} / {tourSteps.length}</div>
    <div class="bubble-title">{tourSteps[step].title}</div>
    <div class="bubble-text">{tourSteps[step].text}</div>
    {#if blockMsg}
      <div class="bubble-block">{blockMsg}</div>
    {/if}
    <div class="bubble-nav">
      {#if step > 0}
        <button class="bubble-back" onclick={() => { step--; goToStep(step); }}>Back</button>
      {:else}
        <div></div>
      {/if}
      <div class="bubble-right">
        <button class="bubble-skip" onclick={skipTour}>Skip</button>
        <button class="bubble-next" onclick={() => goToStep(step + 1)}>
          {step === tourSteps.length - 1 ? "Done" : "Next"}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .welcome-overlay {
    position: fixed; inset: 0; background: rgba(0,0,0,0.7); display: flex;
    align-items: center; justify-content: center; z-index: 1000; backdrop-filter: blur(8px);
  }
  .welcome-card { display: flex; flex-direction: column; align-items: center; gap: 6px; max-width: 300px; text-align: center; }
  .welcome-logo { font-size: 42px; font-weight: 700; color: #f0f0f0; letter-spacing: -1px; }
  .welcome-sub { font-size: 15px; color: #999; margin: 0; }
  .welcome-actions { display: flex; flex-direction: column; gap: 8px; margin-top: 20px; align-items: center; }
  .welcome-start { padding: 10px 32px; font-size: 15px; font-weight: 500; background: #ec4899; color: white; border: none; border-radius: 8px; cursor: pointer; }
  .welcome-start:hover { background: #db2777; }
  .welcome-skip { font-size: 13px; color: #666; background: none; border: none; cursor: pointer; }
  .welcome-skip:hover { color: #999; }

  .tour-overlay { position: fixed; inset: 0; z-index: 900; background: rgba(0,0,0,0.55); }
  .spotlight { position: fixed; border-radius: 8px; box-shadow: 0 0 0 9999px rgba(0,0,0,0.55); z-index: 901; pointer-events: none; transition: all 0.3s ease; }

  .tour-bubble {
    position: fixed; z-index: 950; width: 280px; background: #282828; border: 1px solid #3a3a3a;
    border-radius: 10px; padding: 14px; box-shadow: 0 8px 32px rgba(0,0,0,0.4); transition: all 0.3s ease;
  }
  .tour-bubble::before { content: ""; position: absolute; width: 10px; height: 10px; background: #282828; border: 1px solid #3a3a3a; transform: rotate(45deg); }
  .arrow-left::before { left: -6px; top: 50%; margin-top: -5px; border-right: none; border-top: none; }
  .arrow-top::before { top: -6px; left: 50%; margin-left: -5px; border-bottom: none; border-right: none; }

  .bubble-step { font-size: 10px; font-weight: 500; color: #ec4899; letter-spacing: 0.5px; margin-bottom: 4px; }
  .bubble-title { font-size: 14px; font-weight: 600; color: #f0f0f0; margin-bottom: 4px; }
  .bubble-text { font-size: 12px; color: #999; line-height: 1.5; margin-bottom: 12px; }
  .bubble-block { font-size: 11px; color: #ef4444; margin-bottom: 8px; }

  .bubble-nav { display: flex; align-items: center; justify-content: space-between; }
  .bubble-back { font-size: 12px; color: #999; background: none; border: none; cursor: pointer; }
  .bubble-back:hover { color: #ccc; }
  .bubble-right { display: flex; gap: 8px; align-items: center; }
  .bubble-skip { font-size: 12px; color: #666; background: none; border: none; cursor: pointer; }
  .bubble-skip:hover { color: #999; }
  .bubble-next { padding: 5px 16px; font-size: 12px; font-weight: 500; background: #ec4899; color: white; border: none; border-radius: 6px; cursor: pointer; }
  .bubble-next:hover { background: #db2777; }
</style>
