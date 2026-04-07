use serde::Serialize;
use std::fs;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

#[derive(Serialize)]
struct SessionStatus {
    active: bool,
    remaining: String,
    remaining_secs: i64,
}

#[derive(Serialize)]
struct CommandOutput {
    success: bool,
    stdout: String,
    error: Option<String>,
}

#[derive(Serialize)]
struct AppEntry {
    raw: String,
    name: String,
    bundle: String,
    path: String,
    icon: String, // base64 PNG or empty
}

fn bliss_path() -> String {
    if let Ok(p) = std::env::var("BLISS_BIN") {
        if std::path::Path::new(&p).exists() {
            return p;
        }
    }
    "/usr/local/bin/bliss".to_string()
}

fn run_bliss(args: &[&str]) -> CommandOutput {
    let result = Command::new(bliss_path()).args(args).output();
    match result {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
            if output.status.success() {
                CommandOutput {
                    success: true,
                    stdout,
                    error: None,
                }
            } else {
                let err = if stderr.is_empty() {
                    stdout.clone()
                } else {
                    stderr
                };
                CommandOutput {
                    success: false,
                    stdout,
                    error: Some(err),
                }
            }
        }
        Err(e) => CommandOutput {
            success: false,
            stdout: String::new(),
            error: Some(format!("Failed to run bliss: {}", e)),
        },
    }
}

fn read_end_time() -> Option<i64> {
    let data = fs::read_to_string("/var/db/bliss_end_time").ok()?;
    data.trim().parse::<i64>().ok()
}

/// Extract a macOS .app icon as base64 PNG using sips
fn get_app_icon_base64(app_path: &str) -> String {
    if app_path.is_empty() || !std::path::Path::new(app_path).exists() {
        return String::new();
    }

    // Try to find icon in the .app bundle
    let icns_path = find_app_icns(app_path);
    if icns_path.is_empty() {
        return String::new();
    }

    // Convert icns to png using sips (macOS built-in)
    let tmp = format!("/tmp/bliss_icon_{}.png", std::process::id());
    let result = Command::new("sips")
        .args(["-s", "format", "png", "-z", "64", "64", &icns_path, "--out", &tmp])
        .output();

    if let Ok(output) = result {
        if output.status.success() {
            if let Ok(data) = fs::read(&tmp) {
                let _ = fs::remove_file(&tmp);
                use std::io::Write;
                let mut buf = Vec::new();
                {
                    let mut encoder = Base64Encoder::new(&mut buf);
                    encoder.write_all(&data).ok();
                }
                return String::from_utf8(buf).unwrap_or_default();
            }
        }
    }
    let _ = fs::remove_file(&tmp);
    String::new()
}

// Simple base64 encoder (no external dep needed)
struct Base64Encoder<'a> {
    out: &'a mut Vec<u8>,
    buf: [u8; 3],
    buf_len: usize,
}

const B64: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

impl<'a> Base64Encoder<'a> {
    fn new(out: &'a mut Vec<u8>) -> Self {
        Self {
            out,
            buf: [0; 3],
            buf_len: 0,
        }
    }

    fn flush_buf(&mut self) {
        if self.buf_len == 0 {
            return;
        }
        let b = self.buf;
        self.out.push(B64[(b[0] >> 2) as usize]);
        match self.buf_len {
            1 => {
                self.out.push(B64[((b[0] & 0x03) << 4) as usize]);
                self.out.push(b'=');
                self.out.push(b'=');
            }
            2 => {
                self.out
                    .push(B64[((b[0] & 0x03) << 4 | b[1] >> 4) as usize]);
                self.out.push(B64[((b[1] & 0x0f) << 2) as usize]);
                self.out.push(b'=');
            }
            _ => {
                self.out
                    .push(B64[((b[0] & 0x03) << 4 | b[1] >> 4) as usize]);
                self.out
                    .push(B64[((b[1] & 0x0f) << 2 | b[2] >> 6) as usize]);
                self.out.push(B64[(b[2] & 0x3f) as usize]);
            }
        }
        self.buf_len = 0;
        self.buf = [0; 3];
    }
}

impl std::io::Write for Base64Encoder<'_> {
    fn write(&mut self, data: &[u8]) -> std::io::Result<usize> {
        for &byte in data {
            self.buf[self.buf_len] = byte;
            self.buf_len += 1;
            if self.buf_len == 3 {
                self.flush_buf();
            }
        }
        Ok(data.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        self.flush_buf();
        Ok(())
    }
}

impl Drop for Base64Encoder<'_> {
    fn drop(&mut self) {
        self.flush_buf();
    }
}

fn find_app_icns(app_path: &str) -> String {
    // Read Info.plist for CFBundleIconFile
    let plist_path = format!("{}/Contents/Info.plist", app_path);
    if let Ok(content) = fs::read_to_string(&plist_path) {
        // Quick XML parse for CFBundleIconFile
        if let Some(pos) = content.find("CFBundleIconFile") {
            let after = &content[pos..];
            if let Some(s) = after.find("<string>") {
                if let Some(e) = after[s..].find("</string>") {
                    let icon_name = &after[s + 8..s + e];
                    let icon_name = icon_name.trim();
                    let with_ext = if icon_name.ends_with(".icns") {
                        icon_name.to_string()
                    } else {
                        format!("{}.icns", icon_name)
                    };
                    let full = format!("{}/Contents/Resources/{}", app_path, with_ext);
                    if std::path::Path::new(&full).exists() {
                        return full;
                    }
                }
            }
        }
    }
    // Fallback: look for any .icns in Resources
    let resources = format!("{}/Contents/Resources", app_path);
    if let Ok(entries) = fs::read_dir(&resources) {
        for entry in entries.flatten() {
            if entry.path().extension().map(|e| e == "icns").unwrap_or(false) {
                return entry.path().to_string_lossy().to_string();
            }
        }
    }
    String::new()
}

fn parse_app_entry(line: &str) -> AppEntry {
    if let Some(bar) = line.find('|') {
        let name = line[..bar].to_string();
        let rest = &line[bar + 1..];
        let mut bundle = String::new();
        let mut path = String::new();
        for chunk in rest.split('|') {
            if let Some(v) = chunk.strip_prefix("bundle=") {
                bundle = v.to_string();
            } else if let Some(v) = chunk.strip_prefix("path=") {
                path = v.to_string();
            }
        }
        let icon = get_app_icon_base64(&path);
        AppEntry {
            raw: line.to_string(),
            name,
            bundle,
            path,
            icon,
        }
    } else {
        AppEntry {
            raw: line.to_string(),
            name: line.to_string(),
            bundle: String::new(),
            path: String::new(),
            icon: String::new(),
        }
    }
}

fn browser_app_path(name: &str) -> String {
    let bundle_id = match name.to_lowercase().as_str() {
        "safari" => "com.apple.Safari",
        "chrome" | "google chrome" => "com.google.Chrome",
        "firefox" => "org.mozilla.firefox",
        "brave browser" | "brave" => "com.brave.Browser",
        "arc" => "company.thebrowser.Browser",
        "edge" | "microsoft edge" => "com.microsoft.edgemac",
        "opera" => "com.operasoftware.Opera",
        "vivaldi" => "com.vivaldi.Vivaldi",
        _ => "",
    };

    if !bundle_id.is_empty() {
        // Use mdfind to resolve bundle ID to path
        if let Ok(output) = Command::new("mdfind")
            .args([&format!("kMDItemCFBundleIdentifier == '{}'", bundle_id)])
            .output()
        {
            let stdout = String::from_utf8_lossy(&output.stdout);
            if let Some(first_line) = stdout.lines().next() {
                let p = first_line.trim();
                if !p.is_empty() && std::path::Path::new(p).exists() {
                    return p.to_string();
                }
            }
        }
    }

    // Fallback: /Applications/<name>.app
    let fallback = format!("/Applications/{}.app", name);
    if std::path::Path::new(&fallback).exists() {
        return fallback;
    }
    String::new()
}

#[derive(Serialize)]
struct BrowserEntry {
    name: String,
    icon: String, // base64 PNG
}

// ── Tauri commands ──

#[tauri::command]
fn get_session_status() -> SessionStatus {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs() as i64;

    match read_end_time() {
        Some(end) => {
            let rem = (end - now).max(0);
            if rem > 0 {
                let h = rem / 3600;
                let m = (rem % 3600) / 60;
                let s = rem % 60;
                SessionStatus {
                    active: true,
                    remaining: format!("{:02}:{:02}:{:02}", h, m, s),
                    remaining_secs: rem,
                }
            } else {
                SessionStatus {
                    active: false,
                    remaining: "00:00:00".to_string(),
                    remaining_secs: 0,
                }
            }
        }
        None => SessionStatus {
            active: false,
            remaining: "00:00:00".to_string(),
            remaining_secs: 0,
        },
    }
}

#[tauri::command]
fn start_session(seconds: u32) -> CommandOutput {
    run_bliss(&["start", &seconds.to_string(), "--seconds"])
}

#[tauri::command]
fn run_panic() -> CommandOutput {
    run_bliss(&["panic", "--skip-challenge"])
}

#[tauri::command]
fn run_repair() -> CommandOutput {
    run_bliss(&["repair"])
}

#[tauri::command]
fn get_random_quote() -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    let length = read_quote_length(&home);

    let exe_dir = std::env::current_exe()
        .ok()
        .and_then(|p| p.parent().map(|p| p.to_path_buf()))
        .unwrap_or_default();

    let candidates = vec![
        format!("{}/quotes/{}.txt", home, length),
        format!("{}/quotes/{}.txt", exe_dir.display(), length),
        format!("quotes/{}.txt", length),
    ];

    let mut lines: Vec<String> = Vec::new();
    for path in &candidates {
        if let Ok(content) = fs::read_to_string(path) {
            lines = content
                .lines()
                .map(|l| l.trim().to_string())
                .filter(|l| !l.is_empty())
                .collect();
            if !lines.is_empty() {
                break;
            }
        }
    }

    if lines.is_empty() {
        return "Focus is a practice, not a mood, and it grows with repetition.".to_string();
    }

    let seed = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .subsec_nanos() as usize;
    lines[seed % lines.len()].clone()
}

fn read_quote_length(home: &str) -> String {
    let result = Command::new(bliss_path())
        .args(["config", "quotes", "get"])
        .output();
    if let Ok(output) = result {
        let stdout = String::from_utf8_lossy(&output.stdout);
        for line in stdout.lines() {
            if line.starts_with("quotes:") {
                let val = line.trim_start_matches("quotes:").trim().to_lowercase();
                match val.as_str() {
                    "short" | "medium" | "long" | "huge" => return val,
                    _ => {}
                }
            }
        }
    }
    "medium".to_string()
}

// Config commands

#[tauri::command]
fn config_website_list() -> Vec<String> {
    let result = Command::new(bliss_path())
        .args(["config", "website", "list"])
        .output();
    match result {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            stdout
                .lines()
                .map(|l| l.trim().to_string())
                .filter(|l| !l.is_empty())
                .collect()
        }
        Err(_) => vec![],
    }
}

#[tauri::command]
fn config_website_add(domain: String) -> CommandOutput {
    run_bliss(&["config", "website", "add", &domain])
}

#[tauri::command]
fn config_website_remove(domain: String) -> CommandOutput {
    run_bliss(&["config", "website", "remove", &domain])
}

#[tauri::command]
fn config_browser_list() -> Vec<BrowserEntry> {
    let result = Command::new(bliss_path())
        .args(["config", "browser", "list"])
        .output();
    match result {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            stdout
                .lines()
                .map(|l| l.trim().to_string())
                .filter(|l| !l.is_empty() && l != "no entries")
                .map(|name| {
                    let app_path = browser_app_path(&name);
                    let icon = get_app_icon_base64(&app_path);
                    BrowserEntry { name, icon }
                })
                .collect()
        }
        Err(_) => vec![],
    }
}

#[tauri::command]
fn config_browser_add(name: String) -> CommandOutput {
    run_bliss(&["config", "browser", "add", &name])
}

#[tauri::command]
fn config_browser_remove(name: String) -> CommandOutput {
    run_bliss(&["config", "browser", "remove", &name])
}

#[tauri::command]
fn config_app_list() -> Vec<AppEntry> {
    let result = Command::new(bliss_path())
        .args(["config", "app", "list", "--raw"])
        .output();
    match result {
        Ok(output) => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            stdout
                .lines()
                .map(|l| l.trim().to_string())
                .filter(|l| !l.is_empty() && l != "no entries")
                .map(|l| parse_app_entry(&l))
                .collect()
        }
        Err(_) => vec![],
    }
}

#[tauri::command]
fn config_app_add(path: String) -> CommandOutput {
    run_bliss(&["config", "app", "add", &path])
}

#[tauri::command]
fn config_app_remove(entry: String) -> CommandOutput {
    run_bliss(&["config", "app", "remove", &entry])
}

/// Add a browser by extracting its name from an .app path
#[tauri::command]
fn config_browser_add_from_path(path: String) -> CommandOutput {
    let name = std::path::Path::new(&path)
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_default();
    if name.is_empty() {
        return CommandOutput {
            success: false,
            stdout: String::new(),
            error: Some("Invalid app path".to_string()),
        };
    }
    run_bliss(&["config", "browser", "add", &name])
}

#[tauri::command]
fn config_quotes_set(length: String) -> CommandOutput {
    run_bliss(&["config", "quotes", &length])
}

#[tauri::command]
fn config_panic_mode_get() -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    let path = format!("{}/.config/bliss/panic_mode.txt", home);
    fs::read_to_string(&path)
        .map(|s| s.trim().to_string())
        .unwrap_or_else(|_| "typing".to_string())
}

#[tauri::command]
fn config_panic_mode_set(mode: String) -> CommandOutput {
    let home = std::env::var("HOME").unwrap_or_default();
    let dir = format!("{}/.config/bliss", home);
    let _ = fs::create_dir_all(&dir);
    let path = format!("{}/panic_mode.txt", dir);
    match fs::write(&path, format!("{}\n", mode)) {
        Ok(_) => CommandOutput {
            success: true,
            stdout: String::new(),
            error: None,
        },
        Err(e) => CommandOutput {
            success: false,
            stdout: String::new(),
            error: Some(e.to_string()),
        },
    }
}

#[tauri::command]
fn config_quote_length_get() -> String {
    read_quote_length(&std::env::var("HOME").unwrap_or_default())
}

// Competitive Programming commands

#[derive(Serialize, serde::Deserialize, Clone)]
struct CPTestCase {
    input: String,
    output: String,
}

#[derive(Serialize, serde::Deserialize, Clone)]
struct CPProblem {
    id: String,
    title: String,
    statement: String,
    url: String,
    difficulty: String,
    input: Option<String>,
    output: Option<String>,
    constraints: Option<String>,
    tests: Vec<CPTestCase>,
}

#[derive(Serialize)]
struct CPJudgeResult {
    passed: bool,
    summary: String,
}

#[tauri::command]
fn cp_load_problems() -> Vec<CPProblem> {
    let home = std::env::var("HOME").unwrap_or_default();
    let paths = vec![
        format!("{home}/.config/bliss/problems/problems.json"),
        "/usr/local/share/bliss/problems/problems.json".to_string(),
        "problems/problems.json".to_string(),
    ];
    for p in paths {
        if let Ok(data) = fs::read_to_string(&p) {
            if let Ok(problems) = serde_json::from_str::<Vec<CPProblem>>(&data) {
                if !problems.is_empty() {
                    return problems;
                }
            }
        }
    }
    Vec::new()
}

#[tauri::command]
fn cp_run_judge(problem: CPProblem, language: String, source_code: String) -> CPJudgeResult {
    let temp_dir = std::env::temp_dir().join(format!("bliss_cp_{}", std::process::id()));
    let _ = fs::create_dir_all(&temp_dir);

    let (source_file, compile_cmd, run_cmd) = match language.as_str() {
        "python3" => ("solution.py", None, vec!["python3", "solution.py"]),
        "java17" => ("Main.java", Some(vec!["javac", "Main.java"]), vec!["java", "-cp", ".", "Main"]),
        _ => ("main.cpp", Some(vec!["clang++", "-std=c++17", "-O2", "main.cpp", "-o", "solution_bin"]), vec!["./solution_bin"]),
    };

    let source_path = temp_dir.join(source_file);
    if fs::write(&source_path, &source_code).is_err() {
        let _ = fs::remove_dir_all(&temp_dir);
        return CPJudgeResult { passed: false, summary: "Failed to write source file.".into() };
    }

    if let Some(compile) = compile_cmd {
        let result = Command::new(compile[0])
            .args(&compile[1..])
            .current_dir(&temp_dir)
            .output();
        match result {
            Ok(output) if !output.status.success() => {
                let stderr = String::from_utf8_lossy(&output.stderr);
                let stdout = String::from_utf8_lossy(&output.stdout);
                let msg = if stderr.is_empty() { stdout } else { stderr };
                let _ = fs::remove_dir_all(&temp_dir);
                return CPJudgeResult {
                    passed: false,
                    summary: format!("Compile failed:\n{}", &msg[..msg.len().min(1000)]),
                };
            }
            Err(e) => {
                let _ = fs::remove_dir_all(&temp_dir);
                return CPJudgeResult { passed: false, summary: format!("Compiler not found: {e}") };
            }
            _ => {}
        }
    }

    for (idx, test) in problem.tests.iter().enumerate() {
        use std::io::Write;
        let mut child = match Command::new(run_cmd[0])
            .args(&run_cmd[1..])
            .current_dir(&temp_dir)
            .stdin(std::process::Stdio::piped())
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn()
        {
            Ok(c) => c,
            Err(e) => {
                let _ = fs::remove_dir_all(&temp_dir);
                return CPJudgeResult { passed: false, summary: format!("Failed to run: {e}") };
            }
        };

        if let Some(stdin) = child.stdin.as_mut() {
            let _ = stdin.write_all(test.input.as_bytes());
        }

        let output = match child.wait_with_output() {
            Ok(o) => o,
            Err(e) => {
                let _ = fs::remove_dir_all(&temp_dir);
                return CPJudgeResult { passed: false, summary: format!("Runtime error: {e}") };
            }
        };

        if !output.status.success() {
            let stderr = String::from_utf8_lossy(&output.stderr);
            let _ = fs::remove_dir_all(&temp_dir);
            return CPJudgeResult {
                passed: false,
                summary: format!("Runtime error on test {}:\n{}", idx + 1, &stderr[..stderr.len().min(500)]),
            };
        }

        let actual = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let expected = test.output.trim().to_string();
        if actual != expected {
            let _ = fs::remove_dir_all(&temp_dir);
            return CPJudgeResult {
                passed: false,
                summary: format!(
                    "Wrong answer on test {}\nExpected:\n{}\nGot:\n{}",
                    idx + 1,
                    &expected[..expected.len().min(300)],
                    &actual[..actual.len().min(300)]
                ),
            };
        }
    }

    let _ = fs::remove_dir_all(&temp_dir);
    CPJudgeResult {
        passed: true,
        summary: format!("All tests passed ({}/{}).", problem.tests.len(), problem.tests.len()),
    }
}

// Profile / Config commands

#[derive(Serialize, serde::Deserialize, Clone)]
struct Profile {
    name: String,
    websites: Vec<String>,
    apps: Vec<String>,
    browsers: Vec<String>,
    #[serde(rename = "panicMode")]
    panic_mode: String,
    #[serde(rename = "quoteLength")]
    quote_length: String,
    #[serde(rename = "colorName", default = "default_color")]
    color_name: String,
}

fn default_color() -> String {
    "pink".to_string()
}

fn profiles_dir() -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    format!("{}/.config/bliss/profiles", home)
}

fn active_profile_path() -> String {
    let home = std::env::var("HOME").unwrap_or_default();
    format!("{}/.config/bliss/active_profile.txt", home)
}

#[tauri::command]
fn profile_list() -> Vec<Profile> {
    let dir = profiles_dir();
    let entries = match fs::read_dir(&dir) {
        Ok(e) => e,
        Err(_) => return vec![],
    };
    let mut profiles: Vec<Profile> = entries
        .flatten()
        .filter(|e| e.path().extension().map(|x| x == "json").unwrap_or(false))
        .filter_map(|e| {
            let data = fs::read_to_string(e.path()).ok()?;
            serde_json::from_str(&data).ok()
        })
        .collect();
    profiles.sort_by(|a, b| a.name.cmp(&b.name));
    profiles
}

#[tauri::command]
fn profile_active() -> Option<String> {
    fs::read_to_string(active_profile_path())
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

#[tauri::command]
fn profile_save(profile: Profile) -> CommandOutput {
    let dir = profiles_dir();
    let _ = fs::create_dir_all(&dir);
    let path = format!("{}/{}.json", dir, profile.name);
    match serde_json::to_string_pretty(&profile) {
        Ok(json) => match fs::write(&path, json) {
            Ok(_) => CommandOutput {
                success: true,
                stdout: String::new(),
                error: None,
            },
            Err(e) => CommandOutput {
                success: false,
                stdout: String::new(),
                error: Some(e.to_string()),
            },
        },
        Err(e) => CommandOutput {
            success: false,
            stdout: String::new(),
            error: Some(e.to_string()),
        },
    }
}

#[tauri::command]
fn profile_delete(name: String) -> CommandOutput {
    let path = format!("{}/{}.json", profiles_dir(), name);
    let _ = fs::remove_file(&path);
    // Clear active if it was this one
    if let Ok(active) = fs::read_to_string(active_profile_path()) {
        if active.trim() == name {
            let _ = fs::remove_file(active_profile_path());
        }
    }
    CommandOutput {
        success: true,
        stdout: String::new(),
        error: None,
    }
}

#[tauri::command]
fn profile_set_active(name: String) -> CommandOutput {
    match fs::write(active_profile_path(), format!("{}\n", name)) {
        Ok(_) => CommandOutput {
            success: true,
            stdout: String::new(),
            error: None,
        },
        Err(e) => CommandOutput {
            success: false,
            stdout: String::new(),
            error: Some(e.to_string()),
        },
    }
}

#[tauri::command]
fn profile_apply(profile: Profile) -> CommandOutput {
    // Clear current config and apply profile's
    // Websites
    let current_sites: Vec<String> = {
        let r = Command::new(bliss_path()).args(["config", "website", "list"]).output();
        r.map(|o| String::from_utf8_lossy(&o.stdout).lines().map(|l| l.trim().to_string()).filter(|l| !l.is_empty()).collect()).unwrap_or_default()
    };
    for site in &current_sites {
        let _ = Command::new(bliss_path()).args(["config", "website", "remove", site]).output();
    }
    for site in &profile.websites {
        let _ = Command::new(bliss_path()).args(["config", "website", "add", site]).output();
    }

    // Apps
    let current_apps: Vec<String> = {
        let r = Command::new(bliss_path()).args(["config", "app", "list", "--raw"]).output();
        r.map(|o| String::from_utf8_lossy(&o.stdout).lines().map(|l| l.trim().to_string()).filter(|l| !l.is_empty() && l != "no entries").collect()).unwrap_or_default()
    };
    for app in &current_apps {
        let _ = Command::new(bliss_path()).args(["config", "app", "remove", app]).output();
    }
    for app in &profile.apps {
        let _ = Command::new(bliss_path()).args(["config", "app", "add", app]).output();
    }

    // Browsers
    let current_browsers: Vec<String> = {
        let r = Command::new(bliss_path()).args(["config", "browser", "list"]).output();
        r.map(|o| String::from_utf8_lossy(&o.stdout).lines().map(|l| l.trim().to_string()).filter(|l| !l.is_empty() && l != "no entries").collect()).unwrap_or_default()
    };
    for b in &current_browsers {
        let _ = Command::new(bliss_path()).args(["config", "browser", "remove", b]).output();
    }
    for b in &profile.browsers {
        let _ = Command::new(bliss_path()).args(["config", "browser", "add", b]).output();
    }

    // Panic mode + quote length
    let home = std::env::var("HOME").unwrap_or_default();
    let _ = fs::write(format!("{}/.config/bliss/panic_mode.txt", home), format!("{}\n", profile.panic_mode));
    let _ = Command::new(bliss_path()).args(["config", "quotes", &profile.quote_length]).output();

    // Set active
    let _ = fs::write(active_profile_path(), format!("{}\n", profile.name));

    CommandOutput {
        success: true,
        stdout: String::new(),
        error: None,
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .invoke_handler(tauri::generate_handler![
            get_session_status,
            start_session,
            run_panic,
            run_repair,
            get_random_quote,
            config_website_list,
            config_website_add,
            config_website_remove,
            config_browser_list,
            config_browser_add,
            config_browser_remove,
            config_browser_add_from_path,
            config_app_list,
            config_app_add,
            config_app_remove,
            config_quotes_set,
            config_panic_mode_get,
            config_panic_mode_set,
            cp_load_problems,
            cp_run_judge,
            config_quote_length_get,
            profile_list,
            profile_active,
            profile_save,
            profile_delete,
            profile_set_active,
            profile_apply,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
