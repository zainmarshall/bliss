<script>
  import { onMount } from "svelte";
  import { invoke } from "@tauri-apps/api/core";

  let { onSuccess, onCancel } = $props();

  let problems = $state([]);
  let problem = $state(null);
  let language = $state("cpp17");
  let code = $state("");
  let resultText = $state("");
  let testsPassed = $state(false);
  let running = $state(false);
  let submitting = $state(false);
  let editorEl;
  let lineCount = $derived(Math.max(code.split("\n").length, 1));

  function getConfig() {
    try {
      let c = JSON.parse(localStorage.getItem("bliss_panic_configs") || "{}");
      return c.cp_difficulty || "easy";
    } catch { return "easy"; }
  }

  const languages = [
    { id: "cpp17", name: "C++17", ext: "cpp" },
    { id: "python3", name: "Python 3", ext: "py" },
    { id: "java17", name: "Java 17", ext: "java" },
  ];

  // Token-based syntax highlighting - avoids nested HTML replacement issues
  function highlightCode(text) {
    let keywords;
    let commentPattern;
    let preprocessorPattern = null;

    if (language === "python3") {
      keywords = new Set(["def","class","if","elif","else","for","while","return","import","from","as","try","except","finally","with","in","not","and","or","is","pass","break","continue","yield","lambda","raise","True","False","None","print","range","len","int","str","list","dict","set","input","map","sorted","enumerate"]);
      commentPattern = /#.*/g;
    } else if (language === "java17") {
      keywords = new Set(["public","private","protected","static","void","int","long","double","float","char","boolean","String","class","import","package","new","return","if","else","for","while","do","switch","case","break","continue","try","catch","finally","throws","throw","extends","implements","this","super","final","abstract","null","true","false","System","Scanner","Arrays","Math","ArrayList","HashMap","Collections","Integer","Long"]);
      commentPattern = /\/\/.*/g;
    } else {
      keywords = new Set(["using","namespace","int","long","double","float","char","bool","void","string","auto","const","static","return","if","else","for","while","do","switch","case","break","continue","struct","class","public","private","template","typename","typedef","sizeof","new","delete","true","false","nullptr","cout","cin","endl","vector","map","set","pair","sort","push_back","begin","end","size","main","scanf","printf","puts","gets","std"]);
      commentPattern = /\/\/.*/g;
      preprocessorPattern = /^[ \t]*#\w+/gm;
    }

    // Tokenize: split into chunks that are either special (comment, string, preprocessor) or plain code
    let tokens = [];
    let remaining = text;
    let masterPattern = language === "python3"
      ? /(#.*|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/gm
      : /(\/\/.*|"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/gm;

    let lastIndex = 0;
    let match;
    masterPattern.lastIndex = 0;
    while ((match = masterPattern.exec(text)) !== null) {
      if (match.index > lastIndex) {
        tokens.push({ type: "code", text: text.slice(lastIndex, match.index) });
      }
      let m = match[0];
      if (m.startsWith("//") || m.startsWith("#")) {
        tokens.push({ type: "comment", text: m });
      } else {
        tokens.push({ type: "string", text: m });
      }
      lastIndex = masterPattern.lastIndex;
    }
    if (lastIndex < text.length) {
      tokens.push({ type: "code", text: text.slice(lastIndex) });
    }

    // Render each token
    let out = "";
    for (let tok of tokens) {
      let escaped = tok.text.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
      if (tok.type === "comment") {
        out += `<span class="hl-comment">${escaped}</span>`;
      } else if (tok.type === "string") {
        out += `<span class="hl-string">${escaped}</span>`;
      } else {
        // Highlight keywords, preprocessor directives, numbers, and angle-bracket includes
        escaped = escaped.replace(/\b(\d+)\b/g, '<span class="hl-number">$1</span>');
        if (preprocessorPattern) {
          escaped = escaped.replace(/^([ \t]*#\w+)/gm, '<span class="hl-keyword">$1</span>');
          escaped = escaped.replace(/(&lt;[a-zA-Z_./]+&gt;)/g, '<span class="hl-string">$1</span>');
        }
        escaped = escaped.replace(/\b([a-zA-Z_]\w*)\b/g, (m) => {
          return keywords.has(m) ? `<span class="hl-keyword">${m}</span>` : m;
        });
        out += escaped;
      }
    }
    return out;
  }

  // Render math-like LaTeX in problem text
  function renderMath(text) {
    if (!text) return "";
    let r = text;
    r = r.replace(/\\le\b/g, "\u2264");
    r = r.replace(/\\leq\b/g, "\u2264");
    r = r.replace(/\\ge\b/g, "\u2265");
    r = r.replace(/\\geq\b/g, "\u2265");
    r = r.replace(/\\ne\b/g, "\u2260");
    r = r.replace(/\\neq\b/g, "\u2260");
    r = r.replace(/\\dots/g, "\u2026");
    r = r.replace(/\\ldots/g, "\u2026");
    r = r.replace(/\\cdot\b/g, "\u00b7");
    r = r.replace(/\\cdots/g, "\u22ef");
    r = r.replace(/\\times\b/g, "\u00d7");
    r = r.replace(/\\infty/g, "\u221e");
    r = r.replace(/\\rightarrow\b/g, "\u2192");
    r = r.replace(/\\leftarrow\b/g, "\u2190");
    r = r.replace(/\\text\{([^}]*)\}/g, "$1");
    r = r.replace(/\\(?:mathrm|mathit|mathbf)\{([^}]*)\}/g, "$1");
    // Subscripts
    r = r.replace(/_\{([^}]+)\}/g, (_, s) => s.split("").map(c => {
      let m = { "0":"₀","1":"₁","2":"₂","3":"₃","4":"₄","5":"₅","6":"₆","7":"₇","8":"₈","9":"₉","i":"ᵢ","j":"ⱼ","n":"ₙ","k":"ₖ" };
      return m[c] || c;
    }).join(""));
    r = r.replace(/_([0-9a-z])/g, (_, c) => {
      let m = { "0":"₀","1":"₁","2":"₂","3":"₃","4":"₄","5":"₅","6":"₆","7":"₇","8":"₈","9":"₉","i":"ᵢ","j":"ⱼ","n":"ₙ","k":"ₖ" };
      return m[c] || `_${c}`;
    });
    // Superscripts
    r = r.replace(/\^\{([^}]+)\}/g, (_, s) => s.split("").map(c => {
      let m = { "0":"⁰","1":"¹","2":"²","3":"³","4":"⁴","5":"⁵","6":"⁶","7":"⁷","8":"⁸","9":"⁹","n":"ⁿ","i":"ⁱ" };
      return m[c] || c;
    }).join(""));
    r = r.replace(/\^([0-9a-z])/g, (_, c) => {
      let m = { "0":"⁰","1":"¹","2":"²","3":"³","4":"⁴","5":"⁵","6":"⁶","7":"⁷","8":"⁸","9":"⁹","n":"ⁿ","i":"ⁱ" };
      return m[c] || `^${c}`;
    });
    return r;
  }

  function handleTab(e) {
    if (e.key === "Tab") {
      e.preventDefault();
      let el = e.target;
      let start = el.selectionStart;
      let end = el.selectionEnd;
      code = code.substring(0, start) + "    " + code.substring(end);
      requestAnimationFrame(() => {
        el.selectionStart = el.selectionEnd = start + 4;
      });
    }
  }

  async function loadProblems() {
    try {
      problems = await invoke("cp_load_problems");
    } catch (e) {
      problems = [];
    }
    pickProblem();
  }

  function pickProblem() {
    let diff = getConfig();
    let filtered = problems.filter(p => p.difficulty.toLowerCase() === diff);
    if (filtered.length === 0) filtered = problems;
    problem = filtered[Math.floor(Math.random() * filtered.length)] || null;
    code = "";
    testsPassed = false;
    resultText = "";
  }

  async function runTests() {
    if (!problem || !code.trim()) return;
    running = true;
    testsPassed = false;
    resultText = "Running tests...";
    try {
      let result = await invoke("cp_run_judge", {
        problem,
        language,
        sourceCode: code,
      });
      testsPassed = result.passed;
      resultText = result.summary;
    } catch (e) {
      resultText = String(e);
    }
    running = false;
  }

  async function submitPanic() {
    if (!testsPassed) return;
    submitting = true;
    await onSuccess();
    submitting = false;
  }

  onMount(loadProblems);
</script>

<div class="panic-view">
  <div class="ide-layout">
    <!-- Left: Problem statement -->
    <div class="problem-panel">
      <div class="panel-header">
        <span class="panel-title">Problem</span>
        {#if problem}
          <span class="problem-id">{problem.id}</span>
        {/if}
      </div>

      {#if problems.length === 0}
        <div class="no-problems">
          <p>Problem bank not found.</p>
          <p class="hint">Place problems.json in:</p>
          <p class="path">~/.config/bliss/problems/</p>
          <p class="path">/usr/local/share/bliss/problems/</p>
        </div>
      {:else if problem}
        <div class="problem-content">
          <h3 class="problem-title">{problem.title}</h3>

          <div class="section">
            <div class="section-label">Description</div>
            <div class="section-body mono">{renderMath(problem.statement)}</div>
          </div>

          {#if problem.input}
            <div class="section">
              <div class="section-label">Input</div>
              <div class="section-body mono">{renderMath(problem.input)}</div>
            </div>
          {/if}

          {#if problem.output}
            <div class="section">
              <div class="section-label">Output</div>
              <div class="section-body mono">{renderMath(problem.output)}</div>
            </div>
          {/if}

          {#if problem.constraints}
            <div class="section">
              <div class="section-label">Constraints</div>
              <div class="section-body mono">{renderMath(problem.constraints)}</div>
            </div>
          {/if}

          {#if problem.tests?.length > 0}
            <div class="section">
              <div class="section-label">Examples</div>
              {#each problem.tests as test, i}
                <div class="test-case">
                  <div class="test-half">
                    <div class="test-label">Input {i + 1}</div>
                    <pre class="test-data">{test.input.trim()}</pre>
                  </div>
                  <div class="test-half">
                    <div class="test-label">Output {i + 1}</div>
                    <pre class="test-data">{test.output.trim()}</pre>
                  </div>
                </div>
              {/each}
            </div>
          {/if}
        </div>
      {/if}
    </div>

    <!-- Right: Code editor -->
    <div class="editor-panel">
      <div class="panel-header">
        <select class="lang-select" bind:value={language} onchange={() => { code = ""; testsPassed = false; }}>
          {#each languages as lang}
            <option value={lang.id}>{lang.name}</option>
          {/each}
        </select>
        <div class="editor-actions">
          <button class="run-btn" onclick={runTests} disabled={running || !code.trim()}>
            {#if running}
              <span class="spinner-sm"></span>
            {:else}
              Run Tests
            {/if}
          </button>
          <button class="submit-btn" onclick={submitPanic} disabled={!testsPassed || submitting}>
            {#if submitting}
              <span class="spinner-sm"></span>
            {:else}
              Submit
            {/if}
          </button>
        </div>
      </div>

      <div class="editor-wrap">
        <div class="line-numbers">
          {#each Array(lineCount) as _, i}
            <span>{i + 1}</span>
          {/each}
        </div>
        <div class="editor-container">
          <!-- svelte-ignore a11y_positive_tabindex -->
          <textarea
            class="code-input"
            bind:value={code}
            onkeydown={handleTab}
            spellcheck="false"
            autocomplete="off"
            autocorrect="off"
            autocapitalize="off"
            placeholder="Write your solution here..."
          ></textarea>
          <pre class="code-highlight" aria-hidden="true">{@html highlightCode(code + "\n")}</pre>
        </div>
      </div>

      <!-- Output panel -->
      <div class="output-panel" class:passed={testsPassed} class:has-output={resultText}>
        {#if resultText}
          <pre class="output-text">{resultText}</pre>
        {:else}
          <span class="output-placeholder">Run tests to see output</span>
        {/if}
      </div>
    </div>
  </div>

  <button class="float-cancel" onclick={onCancel}>Cancel</button>
</div>

<style>
  .panic-view {
    height: 100vh;
    display: flex;
    flex-direction: column;
    position: relative;
  }

  .ide-layout {
    display: flex;
    flex: 1;
    overflow: hidden;
  }

  /* Problem panel */
  .problem-panel {
    width: 45%;
    display: flex;
    flex-direction: column;
    border-right: 1px solid #2a2a2a;
    overflow: hidden;
  }

  .panel-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 8px 14px;
    border-bottom: 1px solid #2a2a2a;
    min-height: 38px;
    flex-shrink: 0;
  }

  .panel-title {
    font-size: 13px;
    font-weight: 600;
    color: #e0e0e0;
  }

  .problem-id {
    font-size: 11px;
    color: #888;
    font-family: "SF Mono", "Menlo", monospace;
  }

  .problem-content {
    flex: 1;
    overflow-y: auto;
    padding: 14px;
  }

  .problem-title {
    font-size: 16px;
    font-weight: 600;
    color: #e0e0e0;
    margin: 0 0 14px;
  }

  .section {
    margin-bottom: 14px;
  }

  .section-label {
    font-size: 11px;
    font-weight: 600;
    color: #ec4899;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-bottom: 4px;
  }

  .section-body {
    font-size: 13px;
    color: #ccc;
    line-height: 1.6;
    white-space: pre-wrap;
    word-break: break-word;
  }

  .section-body.mono {
    font-family: "SF Mono", "Menlo", "Consolas", monospace;
    font-size: 12px;
  }

  .test-case {
    display: flex;
    gap: 8px;
    margin-top: 6px;
  }

  .test-half {
    flex: 1;
    min-width: 0;
  }

  .test-label {
    font-size: 10px;
    font-weight: 600;
    color: #777;
    text-transform: uppercase;
    letter-spacing: 0.3px;
    margin-bottom: 2px;
  }

  .test-data {
    font-family: "SF Mono", "Menlo", monospace;
    font-size: 12px;
    color: #ccc;
    background: rgba(255, 255, 255, 0.04);
    padding: 6px 8px;
    border-radius: 4px;
    margin: 0;
    white-space: pre-wrap;
    word-break: break-all;
  }

  .no-problems {
    padding: 20px;
    color: #888;
    font-size: 13px;
  }

  .no-problems .hint { color: #666; font-size: 12px; margin-top: 8px; }
  .no-problems .path { color: #555; font-size: 11px; font-family: monospace; margin: 2px 0; }

  /* Editor panel */
  .editor-panel {
    flex: 1;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .lang-select {
    padding: 4px 8px;
    font-size: 12px;
    background: rgba(255, 255, 255, 0.06);
    border: 1px solid #333;
    border-radius: 4px;
    color: #e0e0e0;
    outline: none;
  }

  .editor-actions {
    display: flex;
    gap: 6px;
  }

  .run-btn, .submit-btn {
    padding: 4px 12px;
    font-size: 12px;
    font-weight: 500;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    display: flex;
    align-items: center;
    gap: 4px;
    transition: background 0.15s;
  }

  .run-btn {
    background: rgba(255, 255, 255, 0.08);
    color: #e0e0e0;
  }

  .run-btn:hover { background: rgba(255, 255, 255, 0.12); }
  .run-btn:disabled { opacity: 0.4; cursor: not-allowed; }

  .submit-btn {
    background: #ec4899;
    color: white;
  }

  .submit-btn:hover { background: #db2777; }
  .submit-btn:disabled { opacity: 0.3; cursor: not-allowed; }

  .editor-wrap {
    flex: 1;
    display: flex;
    overflow: hidden;
    position: relative;
  }

  .line-numbers {
    width: 40px;
    padding: 10px 0;
    display: flex;
    flex-direction: column;
    align-items: flex-end;
    padding-right: 8px;
    font-family: "SF Mono", "Menlo", monospace;
    font-size: 12px;
    line-height: 1.5;
    color: #444;
    background: rgba(0, 0, 0, 0.2);
    overflow: hidden;
    user-select: none;
    flex-shrink: 0;
  }

  .editor-container {
    flex: 1;
    position: relative;
    overflow: auto;
  }

  .code-input, .code-highlight {
    font-family: "SF Mono", "Menlo", "Consolas", monospace;
    font-size: 12px;
    line-height: 1.5;
    padding: 10px;
    margin: 0;
    white-space: pre;
    word-wrap: normal;
    tab-size: 4;
  }

  .code-input {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    background: transparent;
    color: transparent;
    caret-color: #ec4899;
    border: none;
    outline: none;
    resize: none;
    z-index: 2;
    overflow: auto;
  }

  .code-input::placeholder {
    color: #444;
  }

  .code-highlight {
    pointer-events: none;
    color: #ccc;
    min-height: 100%;
    z-index: 1;
  }

  :global(.hl-keyword) { color: #c792ea; }
  :global(.hl-string) { color: #c3e88d; }
  :global(.hl-comment) { color: #546e7a; font-style: italic; }
  :global(.hl-number) { color: #f78c6c; }

  /* Output panel */
  .output-panel {
    border-top: 1px solid #2a2a2a;
    padding: 8px 14px;
    min-height: 60px;
    max-height: 120px;
    overflow-y: auto;
    flex-shrink: 0;
    background: rgba(0, 0, 0, 0.15);
  }

  .output-panel.passed {
    border-top-color: rgba(74, 222, 128, 0.3);
  }

  .output-text {
    font-family: "SF Mono", "Menlo", monospace;
    font-size: 11px;
    line-height: 1.5;
    color: #aaa;
    margin: 0;
    white-space: pre-wrap;
    word-break: break-word;
  }

  .output-panel.passed .output-text {
    color: #4ade80;
  }

  .output-placeholder {
    font-size: 12px;
    color: #444;
  }

  .float-cancel {
    position: absolute;
    bottom: 12px;
    left: 12px;
    padding: 4px 14px;
    font-size: 12px;
    background: rgba(30, 30, 30, 0.9);
    color: #888;
    border: 1px solid #333;
    border-radius: 6px;
    cursor: pointer;
    z-index: 10;
    transition: border-color 0.15s;
  }

  .float-cancel:hover {
    border-color: #555;
  }

  .spinner-sm {
    display: inline-block;
    width: 10px;
    height: 10px;
    border: 1.5px solid #666;
    border-top-color: #e0e0e0;
    border-radius: 50%;
    animation: spin 0.6s linear infinite;
  }

  @keyframes spin { to { transform: rotate(360deg); } }
</style>
