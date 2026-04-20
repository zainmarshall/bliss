<script>
  import { onMount, tick } from "svelte";
  import { invoke } from "@tauri-apps/api/core";

  let { onComplete } = $props();

  let step = $state(-1); // -1 = welcome splash, 0+ = tour steps
  let bubbleStyle = $state("");
  let arrowClass = $state("arrow-bottom");
  let spotlightStyle = $state("");
  let showSpotlight = $state(false);

  const tourSteps = [
    {
      selector: '.sidebar-item[data-section="websites"]',
      sidebarClick: "websites",
      title: "Block Websites",
      text: "Add individual domains or use preset packs to block social media, entertainment, news, and more. You can also block specific URL paths like reddit.com/r/gaming.",
      position: "right",
    },
    {
      selector: '.sidebar-item[data-section="apps"]',
      sidebarClick: "apps",
      title: "Block Apps",
      text: "Select apps that distract you. They'll be force-quit when a focus session begins and stay closed until it ends.",
      position: "right",
    },
    {
      selector: '.sidebar-item[data-section="browsers"]',
      sidebarClick: "browsers",
      title: "Configure Browsers",
      text: "Add your browsers here. They get restarted when sessions start to flush DNS caches, preventing cached access to blocked sites.",
      position: "right",
    },
    {
      selector: '.sidebar-item[data-section="panic"]',
      sidebarClick: "panic",
      title: "Panic Challenge",
      text: "If you need to end a session early, you'll face a challenge first. Pick from typing tests, puzzles, competitive programming, and more.",
      position: "right",
    },
    {
      selector: '.sidebar-item[data-section="blockmode"]',
      sidebarClick: "blockmode",
      title: "Block Mode",
      text: "Switch between Blocklist (block specific sites) and Whitelist (block everything except allowed sites) for maximum control.",
      position: "right",
    },
    {
      selector: '.sidebar-item[data-section="configs"]',
      sidebarClick: "configs",
      title: "Save Configs",
      text: "Save your current setup as a named config. Great for switching between work and study profiles, or for scheduling.",
      position: "right",
    },
    {
      selector: '.tab[data-tab="schedule"]',
      title: "Schedule Sessions",
      text: "Set up recurring focus sessions on specific days and times. Link them to your saved configs for automatic activation.",
      position: "bottom",
    },
    {
      selector: '.tab[data-tab="session"]',
      title: "Start a Session",
      text: "Type a duration and hit Enter. The timer input accepts hours, minutes, and seconds. Default is 25 minutes.",
      position: "bottom",
    },
  ];

  function positionBubble(el) {
    if (!el) {
      showSpotlight = false;
      return;
    }
    let rect = el.getBoundingClientRect();
    let s = tourSteps[step];
    showSpotlight = true;

    // Spotlight around the element
    let pad = 6;
    spotlightStyle = `top:${rect.top - pad}px;left:${rect.left - pad}px;width:${rect.width + pad * 2}px;height:${rect.height + pad * 2}px`;

    // Position bubble
    let bw = 280;
    let bh = 120;
    if (s.position === "right") {
      let top = rect.top + rect.height / 2 - bh / 2;
      let left = rect.right + 16;
      if (left + bw > window.innerWidth - 16) {
        left = rect.left - bw - 16;
        arrowClass = "arrow-right";
      } else {
        arrowClass = "arrow-left";
      }
      bubbleStyle = `top:${Math.max(8, top)}px;left:${left}px`;
    } else if (s.position === "bottom") {
      let top = rect.bottom + 12;
      let left = rect.left + rect.width / 2 - bw / 2;
      left = Math.max(8, Math.min(left, window.innerWidth - bw - 8));
      arrowClass = "arrow-top";
      bubbleStyle = `top:${top}px;left:${left}px`;
    }
  }

  async function goToStep(idx) {
    step = idx;
    if (step >= tourSteps.length) {
      await invoke("setup_complete_mark");
      onComplete();
      return;
    }

    let s = tourSteps[step];

    // Click sidebar or tab to navigate
    if (s.sidebarClick) {
      let sidebarBtn = document.querySelector(`.sidebar-item[data-section="${s.sidebarClick}"]`);
      if (sidebarBtn) sidebarBtn.click();
    }
    if (s.selector?.startsWith('.tab[data-tab=')) {
      let tabBtn = document.querySelector(s.selector);
      if (tabBtn) tabBtn.click();
    }

    await tick();
    await new Promise(r => setTimeout(r, 80));

    let el = document.querySelector(s.selector);
    positionBubble(el);
  }

  function startTour() {
    // Switch to settings tab to begin tour
    let settingsTab = document.querySelector('.tab[data-tab="settings"]');
    if (settingsTab) settingsTab.click();
    setTimeout(() => goToStep(0), 150);
  }

  function handleKeydown(e) {
    if (step === -1 && e.key === "Enter") {
      startTour();
    } else if (step >= 0 && (e.key === "Enter" || e.key === "ArrowRight")) {
      goToStep(step + 1);
    } else if (step > 0 && e.key === "ArrowLeft") {
      goToStep(step - 1);
    } else if (e.key === "Escape") {
      skipTour();
    }
  }

  async function skipTour() {
    await invoke("setup_complete_mark");
    onComplete();
  }

  onMount(() => {
    // Small delay to ensure DOM is ready
    setTimeout(() => { step = -1; }, 100);
  });
</script>

<svelte:window onkeydown={handleKeydown} />

{#if step === -1}
  <!-- Welcome splash -->
  <div class="welcome-overlay">
    <div class="welcome-card">
      <div class="welcome-logo">Bliss</div>
      <p class="welcome-sub">Deep focus starts here.</p>
      <p class="welcome-desc">Let's walk through the setup together. You'll configure your blocker while learning how everything works.</p>
      <div class="welcome-actions">
        <button class="welcome-start" onclick={startTour}>Set up Bliss</button>
        <button class="welcome-skip" onclick={skipTour}>Skip setup</button>
      </div>
    </div>
  </div>
{:else if step >= 0 && step < tourSteps.length}
  <!-- Tour overlay -->
  <div class="tour-overlay" onclick={() => goToStep(step + 1)}>
    {#if showSpotlight}
      <div class="spotlight" style={spotlightStyle}></div>
    {/if}
  </div>
  <!-- svelte-ignore a11y_no_static_element_interactions a11y_click_events_have_key_events -->
  <div class="tour-bubble {arrowClass}" style={bubbleStyle} onclick={(e) => e.stopPropagation()}>
    <div class="bubble-step">Step {step + 1} of {tourSteps.length}</div>
    <div class="bubble-title">{tourSteps[step].title}</div>
    <div class="bubble-text">{tourSteps[step].text}</div>
    <div class="bubble-nav">
      {#if step > 0}
        <button class="bubble-back" onclick={() => goToStep(step - 1)}>Back</button>
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
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.7);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1000;
    backdrop-filter: blur(8px);
  }

  .welcome-card {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 6px;
    max-width: 340px;
    text-align: center;
  }

  .welcome-logo {
    font-size: 42px;
    font-weight: 700;
    color: #e0e0e0;
    letter-spacing: -1px;
  }

  .welcome-sub {
    font-size: 16px;
    color: #888;
    margin: 0;
  }

  .welcome-desc {
    font-size: 13px;
    color: #777;
    line-height: 1.6;
    margin: 8px 0 0;
  }

  .welcome-actions {
    display: flex;
    flex-direction: column;
    gap: 8px;
    margin-top: 20px;
    align-items: center;
  }

  .welcome-start {
    padding: 10px 32px;
    font-size: 15px;
    font-weight: 500;
    background: #ec4899;
    color: white;
    border: none;
    border-radius: 8px;
    cursor: pointer;
    transition: background 0.15s;
  }

  .welcome-start:hover { background: #db2777; }

  .welcome-skip {
    font-size: 13px;
    color: #666;
    background: none;
    border: none;
    cursor: pointer;
  }

  .welcome-skip:hover { color: #999; }

  /* Tour overlay */
  .tour-overlay {
    position: fixed;
    inset: 0;
    z-index: 900;
    background: rgba(0, 0, 0, 0.55);
  }

  .spotlight {
    position: fixed;
    border-radius: 8px;
    box-shadow: 0 0 0 9999px rgba(0, 0, 0, 0.55);
    z-index: 901;
    pointer-events: none;
    transition: all 0.3s ease;
  }

  .tour-bubble {
    position: fixed;
    z-index: 950;
    width: 280px;
    background: #282828;
    border: 1px solid #3a3a3a;
    border-radius: 12px;
    padding: 16px;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.4);
    transition: all 0.3s ease;
  }

  .tour-bubble::before {
    content: "";
    position: absolute;
    width: 10px;
    height: 10px;
    background: #282828;
    border: 1px solid #3a3a3a;
    transform: rotate(45deg);
  }

  .arrow-left::before {
    left: -6px;
    top: 50%;
    margin-top: -5px;
    border-right: none;
    border-top: none;
  }

  .arrow-right::before {
    right: -6px;
    top: 50%;
    margin-top: -5px;
    border-left: none;
    border-bottom: none;
  }

  .arrow-top::before {
    top: -6px;
    left: 50%;
    margin-left: -5px;
    border-bottom: none;
    border-right: none;
  }

  .arrow-bottom::before {
    bottom: -6px;
    left: 50%;
    margin-left: -5px;
    border-top: none;
    border-left: none;
  }

  .bubble-step {
    font-size: 10px;
    font-weight: 500;
    color: #ec4899;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-bottom: 4px;
  }

  .bubble-title {
    font-size: 14px;
    font-weight: 600;
    color: #e0e0e0;
    margin-bottom: 6px;
  }

  .bubble-text {
    font-size: 12px;
    color: #999;
    line-height: 1.5;
    margin-bottom: 14px;
  }

  .bubble-nav {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .bubble-back {
    font-size: 12px;
    color: #888;
    background: none;
    border: none;
    cursor: pointer;
  }

  .bubble-back:hover { color: #ccc; }

  .bubble-right {
    display: flex;
    gap: 8px;
    align-items: center;
  }

  .bubble-skip {
    font-size: 12px;
    color: #666;
    background: none;
    border: none;
    cursor: pointer;
  }

  .bubble-skip:hover { color: #999; }

  .bubble-next {
    padding: 5px 16px;
    font-size: 12px;
    font-weight: 500;
    background: #ec4899;
    color: white;
    border: none;
    border-radius: 6px;
    cursor: pointer;
  }

  .bubble-next:hover { background: #db2777; }
</style>
