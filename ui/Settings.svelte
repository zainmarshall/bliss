<script>
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { open } from "@tauri-apps/plugin-dialog";
  import { Shield, Folder, ShieldAlert, Wrench } from "lucide-svelte";

  let { sessionActive } = $props();

  let section = $state("blocking");
  let blockingTab = $state("sites"); // "sites" | "apps" | "browsers"
  let websites = $state([]);
  let browsers = $state([]);
  let apps = $state([]);
  let websiteInput = $state("");
  let quoteLength = $state("medium");
  let panicMode = $state("typing");
  let repairing = $state(false);
  let profiles = $state([]);
  let activeProfile = $state(null);
  let showNewConfig = $state(false);
  let newConfigName = $state("");
  let blockMode = $state("blocklist");
  let whitelist = $state([]);
  let whitelistInput = $state("");
  let appBlockMode = $state("blocklist");
  let allowedApps = $state([]);


  const sections = [
    { id: "blocking", label: "Blocking", icon: Shield },
    { id: "configs", label: "Configs", icon: Folder },
    { id: "panic", label: "Panic", icon: ShieldAlert },
    { id: "general", label: "General", icon: Wrench },
  ];

  const websitePresets = [
    { name: "Social Media", sites: ["youtube.com", "twitter.com", "x.com", "reddit.com", "instagram.com", "tiktok.com", "facebook.com", "snapchat.com", "linkedin.com", "threads.net", "tumblr.com", "pinterest.com", "discord.com"] },
    { name: "Entertainment", sites: ["netflix.com", "hulu.com", "disneyplus.com", "twitch.tv", "crunchyroll.com", "max.com", "primevideo.com", "spotify.com"] },
    { name: "News", sites: ["cnn.com", "foxnews.com", "bbc.com", "nytimes.com", "washingtonpost.com", "news.google.com", "apple.news"] },
    { name: "Gaming", sites: ["store.steampowered.com", "epicgames.com", "roblox.com", "chess.com", "lichess.org"] },
    { name: "Shopping", sites: ["amazon.com", "ebay.com", "etsy.com", "walmart.com", "target.com"] },
  ];

  let displayWebsites = $derived.by(() => {
    let set = new Set(websites);
    return websites.filter((site) => {
      if (site.startsWith("www.")) return !set.has(site.slice(4));
      return true;
    });
  });

  async function loadAll() {
    websites = await invoke("config_website_list");
    browsers = await invoke("config_browser_list");
    apps = await invoke("config_app_list");
    quoteLength = await invoke("config_quote_length_get");
    panicMode = await invoke("config_panic_mode_get");
    blockMode = await invoke("config_block_mode_get");
    whitelist = await invoke("config_whitelist_list");
    appBlockMode = await invoke("config_app_block_mode_get");
    allowedApps = await invoke("config_allowed_apps_list");
    loadPanicConfigs();
    await loadProfiles();
  }

  async function loadProfiles() {
    profiles = await invoke("profile_list");
    activeProfile = await invoke("profile_active");
  }

  async function saveCurrentConfig() {
    let name = newConfigName.trim();
    if (!name) return;
    let profile = { name, websites: [...websites], apps: apps.map((a) => a.raw || a), browsers: browsers.map((b) => b.name || b), panicMode, quoteLength, colorName: "pink" };
    await invoke("profile_save", { profile });
    await invoke("profile_set_active", { name });
    newConfigName = "";
    showNewConfig = false;
    await loadProfiles();
  }

  async function applyConfig(profile) { if (sessionActive) return; await invoke("profile_apply", { profile }); await loadAll(); }
  async function deleteConfig(name) { if (sessionActive) return; await invoke("profile_delete", { name }); await loadProfiles(); }

  async function addWebsite() {
    let domain = websiteInput.trim();
    if (!domain || sessionActive) return;
    await invoke("config_website_add", { domain });
    websiteInput = "";
    websites = await invoke("config_website_list");
  }

  async function removeWebsite(domain) {
    if (sessionActive) return;
    await invoke("config_website_remove", { domain });
    let counterpart = domain.startsWith("www.") ? domain.slice(4) : "www." + domain;
    if (websites.includes(counterpart)) await invoke("config_website_remove", { domain: counterpart });
    websites = await invoke("config_website_list");
  }

  async function togglePreset(preset) {
    if (sessionActive) return;
    let allAdded = preset.sites.every((s) => websites.includes(s));
    for (let site of preset.sites) {
      if (allAdded) await invoke("config_website_remove", { domain: site });
      else if (!websites.includes(site)) await invoke("config_website_add", { domain: site });
    }
    websites = await invoke("config_website_list");
  }

  function presetActive(preset) { return preset.sites.every((s) => websites.includes(s)); }

  async function addAppPicker() {
    if (sessionActive) return;
    const path = await open({ title: "Select App", directory: false, multiple: false, defaultPath: "/Applications", filters: [{ name: "Applications", extensions: ["app"] }] });
    if (path) { await invoke("config_app_add", { path }); apps = await invoke("config_app_list"); }
  }

  async function removeApp(raw) { if (sessionActive) return; await invoke("config_app_remove", { entry: raw }); apps = await invoke("config_app_list"); }

  async function addBrowserPicker() {
    if (sessionActive) return;
    const path = await open({ title: "Select Browser", directory: false, multiple: false, defaultPath: "/Applications", filters: [{ name: "Applications", extensions: ["app"] }] });
    if (path) { await invoke("config_browser_add_from_path", { path }); browsers = await invoke("config_browser_list"); }
  }

  async function removeBrowser(name) { if (sessionActive) return; await invoke("config_browser_remove", { name }); browsers = await invoke("config_browser_list"); }
  async function setQuoteLength(len) { if (sessionActive) return; await invoke("config_quotes_set", { length: len }); quoteLength = len; }
  async function setPanicMode(mode) { if (sessionActive) return; await invoke("config_panic_mode_set", { mode }); panicMode = mode; }
  async function runRepair() { repairing = true; await invoke("run_repair"); repairing = false; }
  async function setBlockMode(mode) { if (sessionActive) return; await invoke("config_block_mode_set", { mode }); blockMode = mode; }

  async function addWhitelist() {
    let domain = whitelistInput.trim();
    if (!domain || sessionActive) return;
    await invoke("config_whitelist_add", { domain });
    whitelistInput = "";
    whitelist = await invoke("config_whitelist_list");
  }

  async function removeWhitelist(domain) { if (sessionActive) return; await invoke("config_whitelist_remove", { domain }); whitelist = await invoke("config_whitelist_list"); }
  async function setAppBlockMode(mode) { if (sessionActive) return; await invoke("config_app_block_mode_set", { mode }); appBlockMode = mode; }
  async function addAllowedApp() {
    if (sessionActive) return;
    const path = await open({ title: "Select App", directory: false, multiple: false, defaultPath: "/Applications", filters: [{ name: "Applications", extensions: ["app"] }] });
    if (path) {
      let name = path.split("/").pop()?.replace(".app", "") || "";
      if (name) { await invoke("config_allowed_apps_add", { appName: name }); allowedApps = await invoke("config_allowed_apps_list"); }
    }
  }
  async function removeAllowedApp(name) { if (sessionActive) return; await invoke("config_allowed_apps_remove", { appName: name }); allowedApps = await invoke("config_allowed_apps_list"); }
  async function runUninstall() { if (sessionActive) return; let result = await invoke("run_uninstall"); if (result.success) window.close(); }

  const colorMap = { blue: "#3b82f6", purple: "#a855f7", indigo: "#6366f1", pink: "#ec4899", red: "#ef4444", orange: "#f97316", yellow: "#eab308", green: "#22c55e", mint: "#2dd4bf", cyan: "#06b6d4", teal: "#14b8a6" };
  function profileColor(name) { return colorMap[name] || colorMap.pink; }

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
        <button class="sidebar-item" class:active={section === s.id} data-section={s.id} onclick={() => (section = s.id)}>
          <span class="sidebar-icon"><svelte:component this={s.icon} size={16} /></span>
          {s.label}
        </button>
      {/each}
    </div>

    <div class="divider-v"></div>

    <div class="detail">
      {#if section === "blocking"}
        <!-- Sub-tabs: Sites | Apps | Browsers -->
        <div class="sub-tabs">
          <button class:sub-active={blockingTab === "sites"} onclick={() => blockingTab = "sites"}>Sites</button>
          <button class:sub-active={blockingTab === "apps"} onclick={() => blockingTab = "apps"}>Apps</button>
          <button class:sub-active={blockingTab === "browsers"} onclick={() => blockingTab = "browsers"}>Browsers</button>
        </div>

        {#if blockingTab === "sites"}
          <!-- Blocklist / Whitelist toggle -->
          <div class="mode-toggle">
            <button class:seg-active={blockMode === "blocklist"} onclick={() => setBlockMode("blocklist")} disabled={sessionActive}>Blocklist</button>
            <button class:seg-active={blockMode === "whitelist"} onclick={() => setBlockMode("whitelist")} disabled={sessionActive}>Whitelist</button>
          </div>

          {#if blockMode === "blocklist"}
            <div class="form-group">
              <div class="input-row">
                <input type="text" placeholder="youtube.com or reddit.com/r/gaming" bind:value={websiteInput} onkeydown={(e) => e.key === "Enter" && addWebsite()} disabled={sessionActive} />
              </div>
              <div class="presets">
                {#each websitePresets as preset}
                  <button class="preset-btn" class:preset-active={presetActive(preset)} onclick={() => togglePreset(preset)} disabled={sessionActive}>
                    {#if presetActive(preset)}<span class="check">&#10003;</span>{/if}
                    {preset.name}
                  </button>
                {/each}
              </div>
            </div>

            <div class="item-list">
              {#each displayWebsites as site}
                <div class="item-row">
                  <span class="item-label">{site}</span>
                  <button class="remove-circle" onclick={() => removeWebsite(site)} disabled={sessionActive} title="Remove">
                    <svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="8" fill="#ef4444"/><line x1="5.5" y1="9" x2="12.5" y2="9" stroke="white" stroke-width="2" stroke-linecap="round"/></svg>
                  </button>
                </div>
              {/each}
              {#if websites.length === 0}
                <div class="empty-state">No blocked sites yet</div>
              {/if}
            </div>
          {:else}
            <div class="form-group">
              <p class="mode-hint">Everything is blocked except sites you add here.</p>
              <div class="input-row">
                <input type="text" placeholder="docs.google.com" bind:value={whitelistInput} onkeydown={(e) => e.key === "Enter" && addWhitelist()} disabled={sessionActive} />
              </div>
            </div>

            <div class="item-list">
              {#each whitelist as site}
                <div class="item-row">
                  <span class="item-label">{site}</span>
                  <button class="remove-circle" onclick={() => removeWhitelist(site)} disabled={sessionActive} title="Remove">
                    <svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="8" fill="#ef4444"/><line x1="5.5" y1="9" x2="12.5" y2="9" stroke="white" stroke-width="2" stroke-linecap="round"/></svg>
                  </button>
                </div>
              {/each}
              {#if whitelist.length === 0}
                <div class="empty-state">No allowed sites - everything gets blocked</div>
              {/if}
            </div>
          {/if}

        {:else if blockingTab === "apps"}
          <div class="mode-toggle">
            <button class:seg-active={appBlockMode === "blocklist"} onclick={() => setAppBlockMode("blocklist")} disabled={sessionActive}>Blocklist</button>
            <button class:seg-active={appBlockMode === "whitelist"} onclick={() => setAppBlockMode("whitelist")} disabled={sessionActive}>Whitelist</button>
          </div>

          {#if appBlockMode === "blocklist"}
            <div class="item-list">
              {#each apps as app}
                <div class="item-row app-row">
                  {#if app.icon}
                    <img class="app-icon" src="data:image/png;base64,{app.icon}" alt="" />
                  {:else}
                    <div class="app-icon-placeholder"></div>
                  {/if}
                  <div class="app-info">
                    <span class="app-name">{app.name}</span>
                    {#if app.path}<span class="app-path">{app.path}</span>{:else if app.bundle}<span class="app-path">{app.bundle}</span>{/if}
                  </div>
                  <button class="remove-circle" onclick={() => removeApp(app.raw)} disabled={sessionActive} title="Remove">
                    <svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="8" fill="#ef4444"/><line x1="5.5" y1="9" x2="12.5" y2="9" stroke="white" stroke-width="2" stroke-linecap="round"/></svg>
                  </button>
                </div>
              {/each}
              {#if apps.length === 0}
                <div class="empty-state">No blocked apps</div>
              {/if}
            </div>
            <button class="text-action" onclick={addAppPicker} disabled={sessionActive}>Add App...</button>
            <p class="footer-note">These apps get force-quit when a session starts.</p>
          {:else}
            <p class="mode-hint">Only these apps can run during sessions. Everything else gets killed.</p>
            <div class="item-list">
              {#each allowedApps as name}
                <div class="item-row">
                  <span class="item-label">{name}</span>
                  <button class="remove-circle" onclick={() => removeAllowedApp(name)} disabled={sessionActive} title="Remove">
                    <svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="8" fill="#ef4444"/><line x1="5.5" y1="9" x2="12.5" y2="9" stroke="white" stroke-width="2" stroke-linecap="round"/></svg>
                  </button>
                </div>
              {/each}
              {#if allowedApps.length === 0}
                <div class="empty-state">No allowed apps - everything gets killed</div>
              {/if}
            </div>
            <button class="text-action" onclick={addAllowedApp} disabled={sessionActive}>Add Allowed App...</button>
          {/if}

        {:else if blockingTab === "browsers"}
          <div class="item-list">
            {#each browsers as browser}
              <div class="item-row app-row">
                {#if browser.icon}
                  <img class="app-icon" src="data:image/png;base64,{browser.icon}" alt="" />
                {:else}
                  <div class="app-icon-placeholder"></div>
                {/if}
                <span class="item-label">{browser.name}</span>
                <button class="remove-circle" onclick={() => removeBrowser(browser.name)} disabled={sessionActive} title="Remove">
                  <svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="8" fill="#ef4444"/><line x1="5.5" y1="9" x2="12.5" y2="9" stroke="white" stroke-width="2" stroke-linecap="round"/></svg>
                </button>
              </div>
            {/each}
            {#if browsers.length === 0}
              <div class="empty-state">No browsers added</div>
            {/if}
          </div>
          <button class="text-action" onclick={addBrowserPicker} disabled={sessionActive}>Add Browser...</button>
          <p class="footer-note">Browsers restart when sessions start to flush DNS caches.</p>
        {/if}

      {:else if section === "configs"}
        <div class="item-list">
          {#each profiles as profile}
            <div class="item-row config-row">
              <span class="config-dot" style="background: {profileColor(profile.colorName)}"></span>
              <div class="app-info">
                <span class="app-name">{profile.name}</span>
                <span class="app-path">{profile.websites?.length || 0} sites, {profile.apps?.length || 0} apps</span>
              </div>
              {#if activeProfile === profile.name}
                <span class="config-active">Active</span>
              {:else}
                <button class="config-apply-btn" onclick={() => applyConfig(profile)} disabled={sessionActive}>Apply</button>
              {/if}
              <button class="remove-circle" onclick={() => deleteConfig(profile.name)} disabled={sessionActive} title="Delete">
                <svg width="18" height="18" viewBox="0 0 18 18"><circle cx="9" cy="9" r="8" fill="#ef4444"/><line x1="5.5" y1="9" x2="12.5" y2="9" stroke="white" stroke-width="2" stroke-linecap="round"/></svg>
              </button>
            </div>
          {/each}
          {#if profiles.length === 0 && !showNewConfig}
            <div class="empty-state">No saved configs yet</div>
          {/if}
        </div>

        {#if showNewConfig}
          <div class="save-config-row">
            <input type="text" placeholder="Config name" bind:value={newConfigName} onkeydown={(e) => e.key === "Enter" && saveCurrentConfig()} />
            <button class="config-apply-btn" onclick={saveCurrentConfig} disabled={!newConfigName.trim()}>Save</button>
            <button class="cancel-link" onclick={() => { showNewConfig = false; newConfigName = ""; }}>Cancel</button>
          </div>
        {:else}
          <button class="text-action" onclick={() => (showNewConfig = true)} disabled={sessionActive}>Save Current Config</button>
        {/if}

      {:else if section === "panic"}
        <div class="form-group">
          <div class="field-row">
            <div class="field-label">
              <span>Challenge</span>
              <span class="field-desc">What you solve to end a session early</span>
            </div>
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
          <div class="form-group">
            <div class="field-row"><div class="field-label"><span>Quote length</span></div></div>
            <div class="segmented">
              {#each ["short", "medium", "long", "huge"] as len}
                <button class:seg-active={quoteLength === len} onclick={() => setQuoteLength(len)} disabled={sessionActive}>{len[0].toUpperCase() + len.slice(1)}</button>
              {/each}
            </div>
          </div>
        {:else if panicMode === "minesweeper"}
          <div class="form-group">
            <div class="field-row"><div class="field-label"><span>Grid size</span></div></div>
            <div class="segmented">
              {#each [["small", "8x8"], ["medium", "10x10"], ["large", "14x14"]] as [val, label]}
                <button class:seg-active={getPanicConfig("minesweeper_size") === val} onclick={() => setPanicConfig("minesweeper_size", val)} disabled={sessionActive}>{label}</button>
              {/each}
            </div>
          </div>
        {:else if panicMode === "wordle"}
          <div class="form-group">
            <div class="field-row"><div class="field-label"><span>Guesses</span></div></div>
            <div class="segmented">
              {#each [["easy", "6"], ["medium", "5"], ["hard", "4"]] as [val, label]}
                <button class:seg-active={getPanicConfig("wordle_difficulty") === val} onclick={() => setPanicConfig("wordle_difficulty", val)} disabled={sessionActive}>{label}</button>
              {/each}
            </div>
          </div>
        {:else if panicMode === "2048"}
          <div class="form-group">
            <div class="field-row"><div class="field-label"><span>Target tile</span></div></div>
            <div class="segmented">
              {#each [["easy", "128"], ["medium", "512"], ["hard", "2048"]] as [val, label]}
                <button class:seg-active={getPanicConfig("2048_difficulty") === val} onclick={() => setPanicConfig("2048_difficulty", val)} disabled={sessionActive}>{label}</button>
              {/each}
            </div>
          </div>
        {:else if panicMode === "sudoku"}
          <div class="form-group">
            <div class="field-row"><div class="field-label"><span>Clues</span></div></div>
            <div class="segmented">
              {#each [["easy", "30"], ["medium", "25"], ["hard", "20"]] as [val, label]}
                <button class:seg-active={getPanicConfig("sudoku_difficulty") === val} onclick={() => setPanicConfig("sudoku_difficulty", val)} disabled={sessionActive}>{label}</button>
              {/each}
            </div>
          </div>
        {:else if panicMode === "simon"}
          <div class="form-group">
            <div class="field-row"><div class="field-label"><span>Difficulty</span></div></div>
            <div class="segmented">
              {#each [["easy", "3x3"], ["medium", "4x4"], ["hard", "5x5"]] as [val, label]}
                <button class:seg-active={getPanicConfig("simon_difficulty") === val} onclick={() => setPanicConfig("simon_difficulty", val)} disabled={sessionActive}>{label}</button>
              {/each}
            </div>
          </div>
        {:else if panicMode === "pipes"}
          <div class="form-group">
            <div class="field-row"><div class="field-label"><span>Grid size</span></div></div>
            <div class="segmented">
              {#each [["small", "5x5"], ["medium", "7x7"], ["large", "9x9"]] as [val, label]}
                <button class:seg-active={getPanicConfig("pipes_size") === val} onclick={() => setPanicConfig("pipes_size", val)} disabled={sessionActive}>{label}</button>
              {/each}
            </div>
          </div>
        {:else if panicMode === "competitive"}
          <div class="form-group">
            <div class="field-row"><div class="field-label"><span>Difficulty</span></div></div>
            <div class="segmented">
              {#each [["easy", "Easy"], ["medium", "Medium"], ["hard", "Hard"]] as [val, label]}
                <button class:seg-active={getPanicConfig("cp_difficulty") === val} onclick={() => setPanicConfig("cp_difficulty", val)} disabled={sessionActive}>{label}</button>
              {/each}
            </div>
          </div>
        {/if}

      {:else if section === "general"}
        <div class="form-group">
          <div class="field-row">
            <div class="field-label">
              <span>Repair</span>
              <span class="field-desc">Fix stuck blocks or a broken root helper</span>
            </div>
            <button class="action-btn" onclick={runRepair} disabled={repairing}>{repairing ? "Repairing..." : "Repair"}</button>
          </div>
        </div>

        <div class="form-group" style="margin-top: 32px">
          <div class="field-row" style="justify-content: center">
            <button class="uninstall-btn" disabled={sessionActive} onclick={runUninstall}>Uninstall Bliss</button>
          </div>
        </div>
      {/if}
    </div>
  </div>
</div>

<style>
  .settings { flex: 1; overflow: hidden; position: relative; }

  .lock-overlay {
    position: absolute; inset: 0; display: flex; align-items: center; justify-content: center;
    background: rgba(26,26,26,0.75); backdrop-filter: blur(6px);
    font-size: 14px; font-weight: 500; color: #999; z-index: 10;
  }

  .settings-layout { display: flex; height: 100%; }
  .settings-layout.locked { opacity: 0.5; pointer-events: none; }

  .sidebar { width: 160px; padding: 12px 8px; display: flex; flex-direction: column; gap: 1px; flex-shrink: 0; }

  .sidebar-item {
    display: flex; align-items: center; gap: 8px; padding: 7px 10px; font-size: 13px;
    color: #999; background: none; border: none; border-radius: 6px; cursor: pointer; text-align: left; transition: all 0.1s;
  }
  .sidebar-item.active { color: #f0f0f0; background: rgba(255,255,255,0.06); }
  .sidebar-item:hover:not(.active) { color: #bbb; background: rgba(255,255,255,0.03); }
  .sidebar-icon { display: flex; align-items: center; width: 16px; height: 16px; color: inherit; opacity: 0.7; }

  .divider-v { width: 1px; background: #2a2a2a; }

  .detail { flex: 1; padding: 16px 20px; overflow-y: auto; }

  /* Sub-tabs for Blocking section */
  .sub-tabs { display: flex; gap: 0; margin-bottom: 16px; border: 1px solid #333; border-radius: 8px; overflow: hidden; width: fit-content; }
  .sub-tabs button {
    padding: 6px 20px; font-size: 13px; color: #999; background: rgba(255,255,255,0.02);
    border: none; border-right: 1px solid #333; cursor: pointer; transition: all 0.1s;
  }
  .sub-tabs button:last-child { border-right: none; }
  .sub-tabs button.sub-active { color: #f0f0f0; background: rgba(236,72,153,0.12); }

  /* Blocklist/Whitelist toggle */
  .mode-toggle { display: flex; gap: 0; margin-bottom: 12px; border: 1px solid #333; border-radius: 6px; overflow: hidden; width: fit-content; }
  .mode-toggle button {
    padding: 4px 14px; font-size: 12px; color: #999; background: rgba(255,255,255,0.02);
    border: none; border-right: 1px solid #333; cursor: pointer; transition: all 0.1s;
  }
  .mode-toggle button:last-child { border-right: none; }
  .mode-toggle button.seg-active { color: #f0f0f0; background: rgba(236,72,153,0.15); }
  .mode-toggle button:disabled { opacity: 0.4; cursor: not-allowed; }

  .mode-hint { font-size: 12px; color: #999; margin: 0 0 10px; }

  .form-group { background: rgba(255,255,255,0.04); border-radius: 8px; padding: 12px; margin-bottom: 8px; }

  .input-row { display: flex; align-items: center; gap: 8px; margin-bottom: 10px; }
  .input-row input {
    flex: 1; padding: 6px 10px; font-size: 13px; background: rgba(255,255,255,0.06);
    border: 1px solid #333; border-radius: 6px; color: #f0f0f0; outline: none; transition: border-color 0.15s;
  }
  .input-row input:focus { border-color: #ec4899; }
  .input-row input::placeholder { color: #666; }

  .presets { display: flex; flex-wrap: wrap; gap: 6px; }
  .preset-btn {
    display: flex; align-items: center; gap: 4px; padding: 4px 10px; font-size: 12px;
    color: #aaa; background: rgba(255,255,255,0.06); border: 1px solid #333; border-radius: 6px; cursor: pointer; transition: all 0.15s;
  }
  .preset-btn:hover { border-color: #555; }
  .preset-btn.preset-active { color: #4ade80; border-color: rgba(74,222,128,0.3); background: rgba(74,222,128,0.08); }
  .preset-btn:disabled { opacity: 0.4; cursor: not-allowed; }
  .check { font-size: 11px; }

  .item-list { background: rgba(255,255,255,0.04); border-radius: 8px; overflow: hidden; }
  .item-row { display: flex; align-items: center; padding: 8px 12px; gap: 10px; border-bottom: 1px solid rgba(255,255,255,0.04); }
  .item-row:last-child { border-bottom: none; }
  .item-label { flex: 1; font-size: 13px; color: #f0f0f0; }
  .app-row { padding: 6px 12px; }
  .app-icon { width: 28px; height: 28px; border-radius: 6px; flex-shrink: 0; }
  .app-icon-placeholder { width: 28px; height: 28px; border-radius: 6px; background: #333; flex-shrink: 0; }
  .app-info { flex: 1; display: flex; flex-direction: column; gap: 1px; min-width: 0; }
  .app-name { font-size: 13px; color: #f0f0f0; }
  .app-path { font-size: 11px; color: #888; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  .remove-circle { background: none; border: none; cursor: pointer; padding: 0; display: flex; opacity: 0.7; transition: opacity 0.1s; flex-shrink: 0; }
  .remove-circle:hover { opacity: 1; }
  .remove-circle:disabled { opacity: 0.2; cursor: not-allowed; }

  .empty-state { padding: 16px 12px; font-size: 13px; color: #777; }

  .text-action { display: inline-block; margin-top: 8px; padding: 4px 12px; font-size: 13px; color: #ec4899; background: none; border: none; cursor: pointer; }
  .text-action:hover { opacity: 0.8; }
  .text-action:disabled { opacity: 0.3; cursor: not-allowed; }

  .footer-note { font-size: 11px; color: #777; margin: 8px 0 0; padding-left: 12px; line-height: 1.4; }

  .field-row { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
  .field-label { display: flex; flex-direction: column; gap: 2px; }
  .field-label > span:first-child { font-size: 13px; color: #f0f0f0; }
  .field-desc { font-size: 11px; color: #888; }

  select { padding: 5px 8px; font-size: 13px; background: rgba(255,255,255,0.06); border: 1px solid #333; border-radius: 6px; color: #f0f0f0; outline: none; min-width: 120px; }

  .segmented { display: flex; border: 1px solid #333; border-radius: 6px; overflow: hidden; width: fit-content; margin-top: 8px; }
  .segmented button { padding: 5px 16px; font-size: 12px; color: #999; background: rgba(255,255,255,0.02); border: none; border-right: 1px solid #333; cursor: pointer; transition: all 0.1s; }
  .segmented button:last-child { border-right: none; }
  .segmented button.seg-active { color: #f0f0f0; background: rgba(236,72,153,0.15); }
  .segmented button:disabled { opacity: 0.4; cursor: not-allowed; }

  .action-btn { padding: 5px 14px; font-size: 13px; color: #f0f0f0; background: rgba(255,255,255,0.06); border: 1px solid #333; border-radius: 6px; cursor: pointer; transition: background 0.15s; white-space: nowrap; }
  .action-btn:hover { background: rgba(255,255,255,0.1); }
  .action-btn:disabled { opacity: 0.5; cursor: not-allowed; }

  .config-row { gap: 10px; }
  .config-dot { width: 10px; height: 10px; border-radius: 50%; flex-shrink: 0; }
  .config-active { font-size: 12px; color: #ec4899; font-weight: 500; flex-shrink: 0; }
  .config-apply-btn { padding: 3px 10px; font-size: 12px; color: #f0f0f0; background: rgba(255,255,255,0.08); border: 1px solid #444; border-radius: 5px; cursor: pointer; flex-shrink: 0; transition: background 0.1s; }
  .config-apply-btn:hover { background: rgba(255,255,255,0.12); }
  .config-apply-btn:disabled { opacity: 0.3; cursor: not-allowed; }

  .save-config-row { display: flex; align-items: center; gap: 8px; padding: 8px 12px; }
  .save-config-row input { flex: 1; padding: 5px 10px; font-size: 13px; background: rgba(255,255,255,0.06); border: 1px solid #333; border-radius: 6px; color: #f0f0f0; outline: none; }
  .save-config-row input:focus { border-color: #ec4899; }
  .cancel-link { font-size: 12px; color: #999; background: none; border: none; cursor: pointer; }
  .cancel-link:hover { color: #ccc; }

  .uninstall-btn { padding: 6px 20px; font-size: 13px; color: #ef4444; background: none; border: none; cursor: pointer; }
  .uninstall-btn:hover { opacity: 0.7; }
  .uninstall-btn:disabled { opacity: 0.3; cursor: not-allowed; }
</style>
