<script>
  import { onMount, onDestroy } from "svelte";
  import { invoke } from "@tauri-apps/api/core";
  import { EditorView, keymap } from "@codemirror/view";
  import { EditorState, Compartment } from "@codemirror/state";
  import { basicSetup } from "codemirror";
  import { cpp } from "@codemirror/lang-cpp";
  import { python } from "@codemirror/lang-python";
  import { java } from "@codemirror/lang-java";
  import { oneDark } from "@codemirror/theme-one-dark";
  import { indentWithTab } from "@codemirror/commands";

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
  let editorView;
  let langCompartment = new Compartment();
  let updatingFromEditor = false;

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

  function getLangExtension(langId) {
    if (langId === "python3") return python();
    if (langId === "java17") return java();
    return cpp();
  }

  function createEditor(el) {
    let updateListener = EditorView.updateListener.of((update) => {
      if (update.docChanged) {
        updatingFromEditor = true;
        code = update.state.doc.toString();
        updatingFromEditor = false;
      }
    });

    let editorTheme = EditorView.theme({
      "&": { height: "100%", fontSize: "12px" },
      ".cm-scroller": { overflow: "auto", fontFamily: '"SF Mono", "Menlo", "Consolas", monospace' },
      ".cm-content": { caretColor: "#ec4899" },
      "&.cm-focused .cm-cursor": { borderLeftColor: "#ec4899" },
      ".cm-gutters": { background: "rgba(0, 0, 0, 0.2)", border: "none" },
      ".cm-activeLineGutter": { background: "rgba(255, 255, 255, 0.05)" },
    });

    editorView = new EditorView({
      state: EditorState.create({
        doc: code,
        extensions: [
          basicSetup,
          keymap.of([indentWithTab]),
          langCompartment.of(getLangExtension(language)),
          oneDark,
          editorTheme,
          updateListener,
          EditorState.tabSize.of(4),
        ],
      }),
      parent: el,
    });
  }

  function switchLanguage(langId) {
    if (editorView) {
      editorView.dispatch({
        effects: langCompartment.reconfigure(getLangExtension(langId)),
      });
    }
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
    if (editorView) {
      editorView.dispatch({
        changes: { from: 0, to: editorView.state.doc.length, insert: "" },
      });
    }
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

  onMount(() => {
    loadProblems();
    if (editorEl) createEditor(editorEl);
  });

  onDestroy(() => {
    if (editorView) editorView.destroy();
  });
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
        <select class="lang-select" bind:value={language} onchange={(e) => {
          switchLanguage(language);
          if (editorView) {
            editorView.dispatch({
              changes: { from: 0, to: editorView.state.doc.length, insert: "" },
            });
          }
          code = "";
          testsPassed = false;
        }}>
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

      <div class="editor-wrap" bind:this={editorEl}></div>

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
    overflow: hidden;
  }

  .editor-wrap :global(.cm-editor) {
    height: 100%;
  }

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
