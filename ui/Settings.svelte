<script>
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { open } from "@tauri-apps/plugin-dialog";
  import { Shield, ShieldAlert, Wrench } from "lucide-svelte";

  let { sessionActive } = $props();

  let section = $state("blocking");
  let websites = $state([]);
  let browsers = $state([]);
  let apps = $state([]);
  let websiteInput = $state("");
  let whitelist = $state([]);
  let whitelistInput = $state("");
  let allowedApps = $state([]);
  let blockEverything = $state(false);
  let quoteLength = $state("medium");
  let panicMode = $state("typing");
  let repairing = $state(false);

  const sections = [
    { id: "blocking", label: "Blocking", icon: Shield },
    { id: "panic", label: "Panic", icon: ShieldAlert },
    { id: "general", label: "General", icon: Wrench },
  ];

  const websitePresets = [
    { name: "Social Media", sites: ["youtube.com", "twitter.com", "x.com", "reddit.com", "instagram.com", "tiktok.com", "facebook.com", "snapchat.com", "linkedin.com", "threads.net", "discord.com"] },
    { name: "Entertainment", sites: ["netflix.com", "hulu.com", "twitch.tv", "crunchyroll.com", "spotify.com"] },
    { name: "News", sites: ["cnn.com", "bbc.com", "nytimes.com", "news.google.com"] },
    { name: "Gaming", sites: ["store.steampowered.com", "epicgames.com", "chess.com"] },
    { name: "Shopping", sites: ["amazon.com", "ebay.com", "etsy.com"] },
  ];

  let displayWebsites = $derived.by(() => {
    let set = new Set(websites);
    return websites.filter(s => s.startsWith("www.") ? !set.has(s.slice(4)) : true);
  });

  // Combined blocked list for display
  let blockedItems = $derived.by(() => {
    let items = [];
    for (let s of displayWebsites) items.push({ type: "site", name: s, key: s });
    for (let a of apps) items.push({ type: "app", name: a.name, key: a.raw, icon: a.icon, path: a.path, bundle: a.bundle });
    return items;
  });

  let allowedItems = $derived.by(() => {
    let items = [];
    for (let s of whitelist) items.push({ type: "site", name: s, key: s });
    for (let a of allowedApps) items.push({ type: "app", name: a, key: a });
    return items;
  });

  async function loadAll() {
    websites = await invoke("config_website_list");
    browsers = await invoke("config_browser_list");
    apps = await invoke("config_app_list");
    quoteLength = await invoke("config_quote_length_get");
    panicMode = await invoke("config_panic_mode_get");
    let mode = await invoke("config_block_mode_get");
    blockEverything = mode === "whitelist";
    whitelist = await invoke("config_whitelist_list");
    allowedApps = await invoke("config_allowed_apps_list");
    loadPanicConfigs();
  }

  async function toggleBlockEverything() {
    if (sessionActive) return;
    blockEverything = !blockEverything;
    let mode = blockEverything ? "whitelist" : "blocklist";
    await invoke("config_block_mode_set", { mode });
    await invoke("config_app_block_mode_set", { mode });
  }

  // Blocked list actions
  async function addBlockedSite() {
    let domain = websiteInput.trim();
    if (!domain || sessionActive) return;
    await invoke("config_website_add", { domain });
    websiteInput = "";
    websites = await invoke("config_website_list");
  }

  async function removeBlocked(item) {
    if (sessionActive) return;
    if (item.type === "site") {
      await invoke("config_website_remove", { domain: item.key });
      let counterpart = item.key.startsWith("www.") ? item.key.slice(4) : "www." + item.key;
      if (websites.includes(counterpart)) await invoke("config_website_remove", { domain: counterpart });
      websites = await invoke("config_website_list");
    } else {
      await invoke("config_app_remove", { entry: item.key });
      apps = await invoke("config_app_list");
    }
  }

  async function addBlockedApp() {
    if (sessionActive) return;
    const path = await open({ title: "Select App", directory: false, multiple: false, defaultPath: "/Applications", filters: [{ name: "Applications", extensions: ["app"] }] });
    if (path) { await invoke("config_app_add", { path }); apps = await invoke("config_app_list"); }
  }

  async function togglePreset(preset) {
    if (sessionActive) return;
    let allAdded = preset.sites.every(s => websites.includes(s));
    for (let site of preset.sites) {
      if (allAdded) await invoke("config_website_remove", { domain: site });
      else if (!websites.includes(site)) await invoke("config_website_add", { domain: site });
    }
    websites = await invoke("config_website_list");
  }

  function presetActive(preset) { return preset.sites.every(s => websites.includes(s)); }

  // Allowed list actions
  async function addAllowedSite() {
    let domain = whitelistInput.trim();
    if (!domain || sessionActive) return;
    await invoke("config_whitelist_add", { domain });
    whitelistInput = "";
    whitelist = await invoke("config_whitelist_list");
  }

  async function removeAllowed(item) {
    if (sessionActive) return;
    if (item.type === "site") {
      await invoke("config_whitelist_remove", { domain: item.key });
      whitelist = await invoke("config_whitelist_list");
    } else {
      await invoke("config_allowed_apps_remove", { appName: item.key });
      allowedApps = await invoke("config_allowed_apps_list");
    }
  }

  async function addAllowedApp() {
    if (sessionActive) return;
    const path = await open({ title: "Select App", directory: false, multiple: false, defaultPath: "/Applications", filters: [{ name: "Applications", extensions: ["app"] }] });
    if (path) {
      let name = path.split("/").pop()?.replace(".app", "") || "";
      if (name) { await invoke("config_allowed_apps_add", { appName: name }); allowedApps = await invoke("config_allowed_apps_list"); }
    }
  }

  // Browsers
  async function addBrowserPicker() {
    if (sessionActive) return;
    const path = await open({ title: "Select Browser", directory: false, multiple: false, defaultPath: "/Applications", filters: [{ name: "Applications", extensions: ["app"] }] });
    if (path) { await invoke("config_browser_add_from_path", { path }); browsers = await invoke("config_browser_list"); }
  }
  async function removeBrowser(name) { if (sessionActive) return; await invoke("config_browser_remove", { name }); browsers = await invoke("config_browser_list"); }

  // Panic
  async function setQuoteLength(len) { if (sessionActive) return; await invoke("config_quotes_set", { length: len }); quoteLength = len; }
  async function setPanicMode(mode) { if (sessionActive) return; await invoke("config_panic_mode_set", { mode }); panicMode = mode; }

  // General
  async function runRepair() { repairing = true; await invoke("run_repair"); repairing = false; }
  async function runUninstall() { if (sessionActive) return; let result = await invoke("run_uninstall"); if (result.success) window.close(); }

  // Panic configs (file-backed, synced with SwiftUI)
  let panicConfigs = $state({});
  const challengeFileKeys = { minesweeper_size: "minesweeper_size", wordle_difficulty: "wordle_difficulty", "2048_difficulty": "game2048_difficulty", sudoku_difficulty: "sudoku_difficulty", simon_difficulty: "simon_difficulty", pipes_size: "pipes_size", cp_difficulty: "panic_difficulty" };
  const challengeDefaults = { minesweeper_size: "medium", wordle_difficulty: "easy", "2048_difficulty": "medium", sudoku_difficulty: "medium", simon_difficulty: "medium", pipes_size: "medium", cp_difficulty: "easy" };

  async function loadPanicConfigs() {
    let configs = {};
    for (let [key, fileKey] of Object.entries(challengeFileKeys)) {
      try { let val = await invoke("config_challenge_get", { key: fileKey }); if (val) configs[key] = val; } catch {}
    }
    panicConfigs = configs;
    localStorage.setItem("bliss_panic_configs", JSON.stringify({ ...challengeDefaults, ...configs }));
  }

  function getPanicConfig(key) { return panicConfigs[key] || challengeDefaults[key]; }

  async function setPanicConfig(key, value) {
    if (sessionActive) return;
    panicConfigs[key] = value;
    panicConfigs = { ...panicConfigs };
    await invoke("config_challenge_set", { key: challengeFileKeys[key] || key, value });
    localStorage.setItem("bliss_panic_configs", JSON.stringify({ ...challengeDefaults, ...panicConfigs }));
  }

  onMount(loadAll);
</script>

<div class="settings">
  {#if sessionActive}
    <div class="lock-overlay">Locked during session</div>
  {/if}

  <div class="settings-layout" class:locked={sessionActive}>
    <div class="sidebar">
      {#each sections as s}
        <button class="sidebar-item" class:active={section === s.id} data-section={s.id} onclick={() => section = s.id}>
          <span class="sidebar-icon"><svelte:component this={s.icon} size={16} /></span>
          {s.label}
        </button>
      {/each}
    </div>

    <div class="divider-v"></div>

    <div class="detail">
      {#if section === "blocking"}
        <!-- Block everything toggle -->
        <button class="block-toggle" class:toggle-on={blockEverything} onclick={toggleBlockEverything} disabled={sessionActive}>
          <div class="toggle-track"><div class="toggle-thumb"></div></div>
          <span>Block everything except allowed list</span>
        </button>

        <!-- Blocked section -->
        <div class="list-section" class:dimmed={blockEverything}>
          <div class="list-header">Blocked</div>
          <div class="form-group">
            <div class="input-row">
              <input type="text" placeholder="youtube.com or reddit.com/r/gaming" bind:value={websiteInput} onkeydown={(e) => e.key === "Enter" && addBlockedSite()} disabled={sessionActive || blockEverything} />
            </div>
            <div class="presets">
              {#each websitePresets as preset}
                <button class="preset-btn" class:preset-active={presetActive(preset)} onclick={() => togglePreset(preset)} disabled={sessionActive || blockEverything}>
                  {#if presetActive(preset)}<span class="ck">&#10003;</span>{/if}
                  {preset.name}
                </button>
              {/each}
            </div>
          </div>
          <div class="item-list">
            {#each blockedItems as item}
              <div class="item-row" class:app-row={item.type === "app"}>
                {#if item.type === "app" && item.icon}
                  <img class="app-icon" src="data:image/png;base64,{item.icon}" alt="" />
                {/if}
                <span class="item-label">{item.name}</span>
                <span class="item-type">{item.type === "app" ? "app" : ""}</span>
                <button class="remove-btn" onclick={() => removeBlocked(item)} disabled={sessionActive || blockEverything} title="Remove">&times;</button>
              </div>
            {/each}
            {#if blockedItems.length === 0}
              <div class="empty">No blocked sites or apps</div>
            {/if}
          </div>
          <button class="text-action" onclick={addBlockedApp} disabled={sessionActive || blockEverything}>Add App...</button>
        </div>

        <!-- Always allowed section -->
        <div class="list-section" style="margin-top: 20px">
          <div class="list-header">Always Allowed</div>
          <div class="form-group">
            <div class="input-row">
              <input type="text" placeholder="docs.google.com" bind:value={whitelistInput} onkeydown={(e) => e.key === "Enter" && addAllowedSite()} disabled={sessionActive} />
            </div>
          </div>
          <div class="item-list">
            {#each allowedItems as item}
              <div class="item-row">
                <span class="item-label">{item.name}</span>
                <span class="item-type">{item.type === "app" ? "app" : ""}</span>
                <button class="remove-btn" onclick={() => removeAllowed(item)} disabled={sessionActive} title="Remove">&times;</button>
              </div>
            {/each}
            {#if allowedItems.length === 0}
              <div class="empty">{blockEverything ? "Add sites/apps to keep accessible" : "Exceptions to your blocklist"}</div>
            {/if}
          </div>
          <button class="text-action" onclick={addAllowedApp} disabled={sessionActive}>Add Allowed App...</button>
        </div>

      {:else if section === "panic"}
        <div class="form-group">
          <div class="field-row">
            <div class="field-label"><span>Challenge</span><span class="field-desc">What you solve to end a session early</span></div>
            <select bind:value={panicMode} onchange={(e) => setPanicMode(e.target.value)} disabled={sessionActive}>
              <option value="typing">Typing</option>
              <option value="minesweeper">Minesweeper</option>
              <option value="wordle">Wordle</option>
              <option value="2048">2048</option>
              <option value="sudoku">Sudoku</option>
              <option value="simon">Simon Says</option>
              <option value="pipes">Pipes</option>
              <option value="competitive">Competitive Programming</option>
            </select>
          </div>
        </div>

        {#if panicMode === "typing"}
          <div class="form-group"><div class="field-row"><div class="field-label"><span>Quote length</span></div></div>
            <div class="seg">{#each ["short", "medium", "long", "huge"] as len}<button class:seg-active={quoteLength === len} onclick={() => setQuoteLength(len)} disabled={sessionActive}>{len[0].toUpperCase() + len.slice(1)}</button>{/each}</div>
          </div>
        {:else if panicMode === "minesweeper"}
          <div class="form-group"><div class="field-row"><div class="field-label"><span>Grid size</span></div></div>
            <div class="seg">{#each [["small","8x8"],["medium","10x10"],["large","14x14"]] as [v,l]}<button class:seg-active={getPanicConfig("minesweeper_size")===v} onclick={()=>setPanicConfig("minesweeper_size",v)} disabled={sessionActive}>{l}</button>{/each}</div>
          </div>
        {:else if panicMode === "wordle"}
          <div class="form-group"><div class="field-row"><div class="field-label"><span>Guesses</span></div></div>
            <div class="seg">{#each [["easy","6"],["medium","5"],["hard","4"]] as [v,l]}<button class:seg-active={getPanicConfig("wordle_difficulty")===v} onclick={()=>setPanicConfig("wordle_difficulty",v)} disabled={sessionActive}>{l}</button>{/each}</div>
          </div>
        {:else if panicMode === "2048"}
          <div class="form-group"><div class="field-row"><div class="field-label"><span>Target tile</span></div></div>
            <div class="seg">{#each [["easy","128"],["medium","512"],["hard","2048"]] as [v,l]}<button class:seg-active={getPanicConfig("2048_difficulty")===v} onclick={()=>setPanicConfig("2048_difficulty",v)} disabled={sessionActive}>{l}</button>{/each}</div>
          </div>
        {:else if panicMode === "sudoku"}
          <div class="form-group"><div class="field-row"><div class="field-label"><span>Clues</span></div></div>
            <div class="seg">{#each [["easy","30"],["medium","25"],["hard","20"]] as [v,l]}<button class:seg-active={getPanicConfig("sudoku_difficulty")===v} onclick={()=>setPanicConfig("sudoku_difficulty",v)} disabled={sessionActive}>{l}</button>{/each}</div>
          </div>
        {:else if panicMode === "simon"}
          <div class="form-group"><div class="field-row"><div class="field-label"><span>Difficulty</span></div></div>
            <div class="seg">{#each [["easy","3x3"],["medium","4x4"],["hard","5x5"]] as [v,l]}<button class:seg-active={getPanicConfig("simon_difficulty")===v} onclick={()=>setPanicConfig("simon_difficulty",v)} disabled={sessionActive}>{l}</button>{/each}</div>
          </div>
        {:else if panicMode === "pipes"}
          <div class="form-group"><div class="field-row"><div class="field-label"><span>Grid size</span></div></div>
            <div class="seg">{#each [["small","5x5"],["medium","7x7"],["large","9x9"]] as [v,l]}<button class:seg-active={getPanicConfig("pipes_size")===v} onclick={()=>setPanicConfig("pipes_size",v)} disabled={sessionActive}>{l}</button>{/each}</div>
          </div>
        {:else if panicMode === "competitive"}
          <div class="form-group"><div class="field-row"><div class="field-label"><span>Difficulty</span></div></div>
            <div class="seg">{#each [["easy","Easy"],["medium","Medium"],["hard","Hard"]] as [v,l]}<button class:seg-active={getPanicConfig("cp_difficulty")===v} onclick={()=>setPanicConfig("cp_difficulty",v)} disabled={sessionActive}>{l}</button>{/each}</div>
          </div>
        {/if}

      {:else if section === "general"}
        <div class="list-header" style="margin-bottom: 8px">Browsers</div>
        <div class="item-list">
          {#each browsers as browser}
            <div class="item-row app-row">
              {#if browser.icon}<img class="app-icon" src="data:image/png;base64,{browser.icon}" alt="" />{/if}
              <span class="item-label">{browser.name}</span>
              <button class="remove-btn" onclick={() => removeBrowser(browser.name)} disabled={sessionActive} title="Remove">&times;</button>
            </div>
          {/each}
          {#if browsers.length === 0}<div class="empty">No browsers added</div>{/if}
        </div>
        <button class="text-action" onclick={addBrowserPicker} disabled={sessionActive}>Add Browser...</button>
        <p class="footer-note">Browsers restart when sessions start to flush DNS caches.</p>

        <div class="form-group" style="margin-top: 24px">
          <div class="field-row">
            <div class="field-label"><span>Repair</span><span class="field-desc">Fix stuck blocks or a broken root helper</span></div>
            <button class="action-btn" onclick={runRepair} disabled={repairing}>{repairing ? "Repairing..." : "Repair"}</button>
          </div>
        </div>

        <div style="margin-top: 32px; text-align: center">
          <button class="uninstall-btn" disabled={sessionActive} onclick={runUninstall}>Uninstall Bliss</button>
        </div>
      {/if}
    </div>
  </div>
</div>

<style>
  .settings { flex: 1; overflow: hidden; position: relative; }
  .lock-overlay { position: absolute; inset: 0; display: flex; align-items: center; justify-content: center; background: rgba(26,26,26,0.75); backdrop-filter: blur(6px); font-size: 14px; font-weight: 500; color: #999; z-index: 10; }
  .settings-layout { display: flex; height: 100%; }
  .settings-layout.locked { opacity: 0.5; pointer-events: none; }

  .sidebar { width: 140px; padding: 12px 8px; display: flex; flex-direction: column; gap: 1px; flex-shrink: 0; }
  .sidebar-item { display: flex; align-items: center; gap: 8px; padding: 7px 10px; font-size: 13px; color: #999; background: none; border: none; border-radius: 6px; cursor: pointer; text-align: left; transition: all 0.1s; }
  .sidebar-item.active { color: #f0f0f0; background: rgba(255,255,255,0.06); }
  .sidebar-item:hover:not(.active) { color: #bbb; background: rgba(255,255,255,0.03); }
  .sidebar-icon { display: flex; align-items: center; width: 16px; height: 16px; color: inherit; opacity: 0.7; }
  .divider-v { width: 1px; background: #2a2a2a; }
  .detail { flex: 1; padding: 16px 20px; overflow-y: auto; }

  /* Block everything toggle */
  .block-toggle { display: flex; align-items: center; gap: 10px; background: none; border: none; cursor: pointer; padding: 0; margin-bottom: 16px; font-size: 13px; color: #bbb; }
  .block-toggle:disabled { opacity: 0.4; cursor: not-allowed; }
  .toggle-track { width: 36px; height: 20px; border-radius: 10px; background: #444; position: relative; transition: background 0.15s; flex-shrink: 0; }
  .toggle-on .toggle-track { background: #ec4899; }
  .toggle-thumb { width: 16px; height: 16px; border-radius: 50%; background: white; position: absolute; top: 2px; left: 2px; transition: transform 0.15s; }
  .toggle-on .toggle-thumb { transform: translateX(16px); }

  .list-section { }
  .list-section.dimmed { opacity: 0.3; pointer-events: none; }
  .list-header { font-size: 11px; font-weight: 600; color: #999; text-transform: uppercase; letter-spacing: 0.5px; padding: 0 0 6px; }

  .form-group { background: rgba(255,255,255,0.04); border-radius: 8px; padding: 10px; margin-bottom: 6px; }
  .input-row { display: flex; gap: 8px; margin-bottom: 8px; }
  .input-row input { flex: 1; padding: 6px 10px; font-size: 13px; background: rgba(255,255,255,0.06); border: 1px solid #333; border-radius: 6px; color: #f0f0f0; outline: none; }
  .input-row input:focus { border-color: #ec4899; }
  .input-row input::placeholder { color: #555; }

  .presets { display: flex; flex-wrap: wrap; gap: 5px; }
  .preset-btn { display: flex; align-items: center; gap: 3px; padding: 3px 9px; font-size: 11px; color: #aaa; background: rgba(255,255,255,0.05); border: 1px solid #333; border-radius: 5px; cursor: pointer; }
  .preset-btn:hover { border-color: #555; }
  .preset-btn.preset-active { color: #4ade80; border-color: rgba(74,222,128,0.3); background: rgba(74,222,128,0.08); }
  .preset-btn:disabled { opacity: 0.4; cursor: not-allowed; }
  .ck { font-size: 10px; }

  .item-list { background: rgba(255,255,255,0.03); border-radius: 8px; overflow: hidden; max-height: 200px; overflow-y: auto; }
  .item-row { display: flex; align-items: center; padding: 6px 10px; gap: 8px; border-bottom: 1px solid rgba(255,255,255,0.03); }
  .item-row:last-child { border-bottom: none; }
  .item-row.app-row { padding: 5px 10px; }
  .item-label { flex: 1; font-size: 13px; color: #f0f0f0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .item-type { font-size: 10px; color: #666; flex-shrink: 0; }
  .app-icon { width: 22px; height: 22px; border-radius: 5px; flex-shrink: 0; }
  .remove-btn { background: none; border: none; color: #666; font-size: 16px; cursor: pointer; padding: 0 2px; line-height: 1; flex-shrink: 0; }
  .remove-btn:hover { color: #ef4444; }
  .remove-btn:disabled { opacity: 0.2; cursor: not-allowed; }
  .empty { padding: 12px 10px; font-size: 12px; color: #666; }

  .text-action { display: inline-block; margin-top: 6px; padding: 2px 0; font-size: 12px; color: #ec4899; background: none; border: none; cursor: pointer; }
  .text-action:hover { opacity: 0.8; }
  .text-action:disabled { opacity: 0.3; cursor: not-allowed; }
  .footer-note { font-size: 11px; color: #666; margin: 6px 0 0; line-height: 1.4; }

  .field-row { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
  .field-label { display: flex; flex-direction: column; gap: 2px; }
  .field-label > span:first-child { font-size: 13px; color: #f0f0f0; }
  .field-desc { font-size: 11px; color: #888; }
  select { padding: 5px 8px; font-size: 13px; background: rgba(255,255,255,0.06); border: 1px solid #333; border-radius: 6px; color: #f0f0f0; outline: none; min-width: 120px; }

  .seg { display: flex; border: 1px solid #333; border-radius: 6px; overflow: hidden; width: fit-content; margin-top: 8px; }
  .seg button { padding: 5px 14px; font-size: 12px; color: #999; background: rgba(255,255,255,0.02); border: none; border-right: 1px solid #333; cursor: pointer; }
  .seg button:last-child { border-right: none; }
  .seg button.seg-active { color: #f0f0f0; background: rgba(236,72,153,0.15); }
  .seg button:disabled { opacity: 0.4; cursor: not-allowed; }

  .action-btn { padding: 5px 14px; font-size: 13px; color: #f0f0f0; background: rgba(255,255,255,0.06); border: 1px solid #333; border-radius: 6px; cursor: pointer; white-space: nowrap; }
  .action-btn:hover { background: rgba(255,255,255,0.1); }
  .action-btn:disabled { opacity: 0.5; cursor: not-allowed; }
  .uninstall-btn { padding: 6px 20px; font-size: 13px; color: #ef4444; background: none; border: none; cursor: pointer; }
  .uninstall-btn:hover { opacity: 0.7; }
  .uninstall-btn:disabled { opacity: 0.3; cursor: not-allowed; }
</style>
