#include "hosts_block.h"

#include <cstdlib>
#include <fstream>
#include <iostream>
#include <chrono>
#include <limits.h>
#include <random>
#include <sstream>
#include <string>
#include <unistd.h>
#include <termios.h>
#include <vector>
#include <fstream>
#include <sys/stat.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/ioctl.h>
#include <cstdio>
#include <filesystem>
#include <algorithm>
#include <cctype>

using std::string;

static const char* kLaunchdLabel = "com.bliss.timer";
static const char* kLaunchdPlistPath = "/Library/LaunchDaemons/com.bliss.timer.plist";
static const char* kEndTimePath = "/var/db/bliss_end_time";
static const char* kMenubarLabel = "com.bliss.menubar";
static const char* kRootHelperPlistPath = "/Library/LaunchDaemons/com.bliss.root.plist";
static const char* kRootHelperPlistBackupPath = "/usr/local/share/bliss/com.bliss.root.plist";

static void print_usage(){
    std::cout
        << "bliss start <minutes>           Start a focus lock for N minutes\n"
        << "bliss panic                     Early exit (typing challenge)\n"
        << "bliss status                    Show remaining time + firewall state\n"
        << "bliss repair                    Repair root helper + clear state (requires sudo)\n"
        << "bliss uninstall                 Remove Bliss (requires puzzle)\n"
        << "bliss config website add <url>  Add a blocked website\n"
        << "bliss config website remove <url> Remove a blocked website\n"
        << "bliss config website list       List blocked websites\n"
        << "bliss config app add            Add an app to block (picker)\n"
        << "bliss config app remove         Remove a blocked app (picker)\n"
        << "bliss config app list           List blocked apps\n"
        << "bliss config browser add <name> Add a browser to kill on start\n"
        << "bliss config browser remove <name> Remove a browser from kill list\n"
        << "bliss config browser list       List extra browsers to kill\n"
        << "bliss config quotes <short|medium|long|huge>  Quote length for panic\n"
        << "bliss --help                    Show this help\n";
}

class TerminalRawMode {
public:
    TerminalRawMode() : enabled(false) {
        if(!isatty(STDIN_FILENO)) return;
        if(tcgetattr(STDIN_FILENO, &orig) != 0) return;
        struct termios raw = orig;
        raw.c_lflag &= ~(ICANON | ECHO);
        raw.c_cc[VMIN] = 1;
        raw.c_cc[VTIME] = 0;
        if(tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0){
            enabled = true;
        }
    }
    ~TerminalRawMode(){
        if(enabled){
            tcsetattr(STDIN_FILENO, TCSANOW, &orig);
        }
    }
private:
    struct termios orig{};
    bool enabled;
};

static int terminal_width(){
    struct winsize w{};
    if(ioctl(STDOUT_FILENO, TIOCGWINSZ, &w) == 0 && w.ws_col > 0){
        return static_cast<int>(w.ws_col);
    }
    return 80;
}

static void render_prompt(const std::string& prompt, const std::string& typed){
    int width = terminal_width();
    if(width < 20) width = 20;
    std::cout << "\033[H\033[J";
    size_t col = 0;
    for(size_t i = 0; i < prompt.size(); ++i){
        if(col >= static_cast<size_t>(width)){
            std::cout << "\n";
            col = 0;
        }
        if(i < typed.size()){
            if(typed[i] == prompt[i]){
                std::cout << "\033[32m" << prompt[i] << "\033[0m";
            }else{
                std::cout << "\033[31m" << prompt[i] << "\033[0m";
            }
        }else{
            std::cout << "\033[90m" << prompt[i] << "\033[0m";
        }
        col++;
    }
    std::cout << std::flush;
}

static bool typing_test(double& out_accuracy){
    const char* quotes_fallback = "/usr/local/share/bliss/quotes.txt";
    std::string length = "medium";
    read_quotes_length(length);
    std::string quotes_path = "quotes.txt";
    if(length == "short" || length == "medium" || length == "long" || length == "huge"){
        quotes_path = "quotes/" + length + ".txt";
    }
    std::vector<std::string> kQuotes;
    std::ifstream quotes_file(quotes_path);
    if(!quotes_file.is_open()){
        std::string fallback_path = "/usr/local/share/bliss/quotes/" + length + ".txt";
        quotes_file.open(fallback_path);
    }
    if(quotes_file.is_open()){
        std::string line;
        while(std::getline(quotes_file, line)){
            if(!line.empty()){
                kQuotes.push_back(line);
            }
        }
    }
    if(kQuotes.empty()){
        std::cout << "no quotes found, using default\n";
        kQuotes.push_back("Focus is a practice, not a mood.");
    }

    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<size_t> dist(0, kQuotes.size() - 1);
    const std::string prompt = kQuotes[dist(gen)];
    std::string typed;

    std::cout << "\033[?25l";
    std::cout << "panic mode: type the line with >=95% accuracy\n";
    render_prompt(prompt, typed);

    TerminalRawMode raw;

    while(true){
        char c = 0;
        if(read(STDIN_FILENO, &c, 1) != 1) continue;

        if(c == 3){
            std::cout << "\033[?25h";
            std::cout << "\n";
            return false;
        }

        if(c == 127 || c == 8){
            if(!typed.empty()){
                typed.pop_back();
            }
        }else if(c == '\n' || c == '\r'){
            break;
        }else if(c >= 32 && c <= 126){
            if(typed.size() < prompt.size()){
                typed.push_back(c);
            }
        }

        render_prompt(prompt, typed);

        if(typed.size() == prompt.size()){
            break;
        }
    }

    size_t correct = 0;
    for(size_t i = 0; i < prompt.size() && i < typed.size(); ++i){
        if(prompt[i] == typed[i]) correct++;
    }
    double accuracy = (prompt.empty() ? 0.0 : (100.0 * correct) / prompt.size());

    std::cout << "\naccuracy: " << static_cast<int>(accuracy + 0.5) << "%\n";
    std::cout << "\033[?25h";
    out_accuracy = accuracy;
    return accuracy >= 95.0;
}

static bool file_exists(const char* path){
    struct stat st{};
    return stat(path, &st) == 0;
}

static bool send_to_root_helper(const std::string& line);

static bool repair_root_helper(){
    std::error_code ec;
    if(std::filesystem::exists(kRootHelperPlistBackupPath, ec)){
        std::filesystem::copy_file(
            kRootHelperPlistBackupPath,
            kRootHelperPlistPath,
            std::filesystem::copy_options::overwrite_existing,
            ec
        );
        if(ec){
            std::cout << "[error] unable to copy root helper plist\n";
            return false;
        }
    }else if(!std::filesystem::exists(kRootHelperPlistPath, ec)){
        std::cout << "[error] root helper plist missing; reinstall bliss\n";
        return false;
    }
    std::system("/bin/launchctl bootout system/com.bliss.root >/dev/null 2>&1");
    std::string bootstrap = std::string("/bin/launchctl bootstrap system ") + kRootHelperPlistPath + " >/dev/null 2>&1";
    int rc = std::system(bootstrap.c_str());
    if(rc != 0){
        std::cout << "[error] launchctl bootstrap failed; try reinstall\n";
        return false;
    }
    std::system("/bin/launchctl kickstart -k system/com.bliss.root >/dev/null 2>&1");
    return true;
}

static std::string dirname_from_path(const std::string& path){
    size_t slash = path.find_last_of('/');
    if(slash == std::string::npos){
        return "";
    }
    if(slash == 0){
        return "/";
    }
    return path.substr(0, slash);
}

static bool path_needs_chown(const std::string& path, uid_t uid, gid_t gid){
    struct stat st{};
    if(stat(path.c_str(), &st) != 0){
        return false;
    }
    return st.st_uid != uid || st.st_gid != gid;
}

static bool ensure_config_ownership(){
    uid_t uid = getuid();
    gid_t gid = getgid();
    std::string config_path = get_config_path();
    std::string config_dir = dirname_from_path(config_path);
    if(config_dir.empty()){
        return true;
    }
    bool needs_fix =
        path_needs_chown(config_dir, uid, gid) ||
        path_needs_chown(config_path, uid, gid) ||
        path_needs_chown(get_app_config_path(), uid, gid) ||
        path_needs_chown(get_quotes_config_path(), uid, gid) ||
        path_needs_chown(get_browser_config_path(), uid, gid);
    if(!needs_fix){
        return true;
    }
    std::ostringstream cmd;
    cmd << "fix-config " << uid << " " << gid << " " << config_dir;
    return send_to_root_helper(cmd.str());
}

static bool send_to_root_helper(const std::string& line){
    static bool attempted_restart = false;
    auto try_start_helper = [&]() {
        if(attempted_restart){
            return false;
        }
        if(geteuid() != 0){
            return false;
        }
        attempted_restart = true;
        std::system("/bin/launchctl bootout system/com.bliss.root >/dev/null 2>&1");
        std::system("/bin/launchctl bootstrap system /Library/LaunchDaemons/com.bliss.root.plist >/dev/null 2>&1");
        std::system("/bin/launchctl kickstart -k system/com.bliss.root >/dev/null 2>&1");
        return true;
    };

    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if(fd < 0){
        std::cout << "unable to open root helper socket\n";
        return false;
    }
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", "/var/run/bliss.sock");
    if(connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0){
        close(fd);
        if(try_start_helper()){
            return send_to_root_helper(line);
        }
        std::cout << "unable to reach bliss root helper. try: sudo /bin/launchctl kickstart -k system/com.bliss.root\n";
        return false;
    }
    std::string msg = line + "\n";
    if(write(fd, msg.c_str(), msg.size()) <= 0){
        close(fd);
        return false;
    }
    char buf[512];
    ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    if(n <= 0){
        return false;
    }
    buf[n] = '\0';
    std::string resp(buf);
    if(resp.rfind("ok", 0) == 0){
        return true;
    }
    std::cout << resp;
    return false;
}

static bool command_exists(const std::string& cmd){
    std::string test = "command -v " + cmd + " >/dev/null 2>&1";
    return std::system(test.c_str()) == 0;
}

static std::string normalize_domain(const std::string& input){
    std::string s = input;
    // trim spaces
    while(!s.empty() && std::isspace(static_cast<unsigned char>(s.front()))){ s.erase(s.begin()); }
    while(!s.empty() && std::isspace(static_cast<unsigned char>(s.back()))){ s.pop_back(); }
    // strip scheme
    const std::string http = "http://";
    const std::string https = "https://";
    if(s.rfind(http, 0) == 0) s = s.substr(http.size());
    if(s.rfind(https, 0) == 0) s = s.substr(https.size());
    // strip path
    size_t slash = s.find('/');
    if(slash != std::string::npos) s = s.substr(0, slash);
    // strip port
    size_t colon = s.find(':');
    if(colon != std::string::npos) s = s.substr(0, colon);
    // lowercase
    for(char& c : s){
        if(c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    }
    // trim trailing dot
    while(!s.empty() && s.back() == '.') s.pop_back();
    return s;
}

static std::string pick_app_path_fzf(){
    const char* no_fzf = std::getenv("BLISS_NO_FZF");
    if(no_fzf && *no_fzf != '\0'){
        return "";
    }
    if(!command_exists("fzf")){
        return "";
    }
    const char* script =
        "find /Applications ~/Applications -maxdepth 2 -type d -name \"*.app\" 2>/dev/null | "
        "sed 's#.*/##' | sort -f | fzf";
    FILE* pipe = popen(script, "r");
    if(!pipe){
        return "";
    }
    char buf[512];
    std::string selection;
    if(fgets(buf, sizeof(buf), pipe)){
        selection = buf;
        selection.erase(selection.find_last_not_of("\r\n") + 1);
    }
    pclose(pipe);
    if(selection.empty()){
        return "";
    }
    std::string path_script = "find /Applications ~/Applications -maxdepth 2 -type d -name \"" + selection + "\" 2>/dev/null | head -n 1";
    FILE* pipe2 = popen(path_script.c_str(), "r");
    if(!pipe2){
        return "";
    }
    std::string path;
    if(fgets(buf, sizeof(buf), pipe2)){
        path = buf;
        path.erase(path.find_last_not_of("\r\n") + 1);
    }
    pclose(pipe2);
    return path;
}

static std::string pick_app_path_manual(){
    std::vector<std::string> apps;
    std::vector<std::string> roots = {"/Applications", std::string(std::getenv("HOME") ? std::getenv("HOME") : "") + "/Applications"};
    for(const auto& root : roots){
        if(root.empty()) continue;
        std::error_code ec;
        for(const auto& entry : std::filesystem::directory_iterator(root, ec)){
            if(ec) break;
            if(entry.is_directory()){
                auto path = entry.path();
                if(path.extension() == ".app"){
                    apps.push_back(path.string());
                }
            }
        }
    }
    if(apps.empty()){
        return "";
    }
    std::sort(apps.begin(), apps.end());
    std::cout << "search by app name (press Enter for full list): ";
    std::string filter;
    if(!std::getline(std::cin, filter)){
        return "";
    }
    std::vector<std::string> filtered;
    if(filter.empty()){
        filtered = apps;
    }else{
        std::string f = filter;
        for(char& c : f) c = static_cast<char>(std::tolower(c));
        for(const auto& path : apps){
            std::string name = std::filesystem::path(path).stem().string();
            std::string low = name;
            for(char& c : low) c = static_cast<char>(std::tolower(c));
            if(low.find(f) != std::string::npos){
                filtered.push_back(path);
            }
        }
    }
    if(filtered.empty()){
        std::cout << "no matches\n";
        return "";
    }
    std::cout << "select app:\n";
    for(size_t i = 0; i < filtered.size(); ++i){
        std::string path = filtered[i];
        std::string name = std::filesystem::path(path).stem().string();
        std::string short_path = path;
        const char* home = std::getenv("HOME");
        if(home && *home){
            std::string home_prefix = std::string(home) + "/";
            if(short_path.find(home_prefix) == 0){
                short_path = "~/" + short_path.substr(home_prefix.size());
            }
        }
        if(short_path.find("/Applications/") == 0){
            short_path = short_path.substr(std::string("/Applications/").size());
            short_path = "Apps/" + short_path;
        }
        std::cout << "  \033[32m[" << (i + 1) << "] " << name << "\033[0m"
                  << "  \033[90m" << short_path << "\033[0m\n";
    }
    std::cout << "enter number: ";
    std::string line;
    if(!std::getline(std::cin, line)){
        return "";
    }
    int idx = 0;
    try{
        idx = std::stoi(line);
    }catch(...){
        return "";
    }
    if(idx <= 0 || static_cast<size_t>(idx) > filtered.size()){
        return "";
    }
    return filtered[idx - 1];
}

static std::string pick_app_entry_fzf(const std::vector<std::string>& entries){
    const char* no_fzf = std::getenv("BLISS_NO_FZF");
    if(no_fzf && *no_fzf != '\0'){
        return "";
    }
    if(!command_exists("fzf") || entries.empty()){
        return "";
    }
    char tmpl[] = "/tmp/bliss_apps_XXXXXX";
    int fd = mkstemp(tmpl);
    if(fd < 0){
        return "";
    }
    {
        std::ofstream out(tmpl, std::ios::trunc);
        for(const auto& e : entries){
            out << e << "\n";
        }
    }
    std::string cmd = std::string("cat '") + tmpl + "' | fzf";
    FILE* pipe = popen(cmd.c_str(), "r");
    if(!pipe){
        std::remove(tmpl);
        return "";
    }
    char buf[512];
    std::string selection;
    if(fgets(buf, sizeof(buf), pipe)){
        selection = buf;
        selection.erase(selection.find_last_not_of("\r\n") + 1);
    }
    pclose(pipe);
    std::remove(tmpl);
    return selection;
}

static std::string pick_app_entry_manual(const std::vector<std::string>& entries){
    if(entries.empty()){
        return "";
    }
    std::cout << "select app entry to remove:\n";
    for(size_t i = 0; i < entries.size(); ++i){
        std::cout << "  [" << (i + 1) << "] " << entries[i] << "\n";
    }
    std::cout << "enter number: ";
    std::string line;
    if(!std::getline(std::cin, line)){
        return "";
    }
    int idx = 0;
    try{
        idx = std::stoi(line);
    }catch(...){
        return "";
    }
    if(idx <= 0 || static_cast<size_t>(idx) > entries.size()){
        return "";
    }
    return entries[idx - 1];
}

struct AppEntry {
    std::string name;
    std::string bundle;
    std::string path;
    std::string raw;
};

static std::string shorten_app_path(const std::string& path){
    std::string short_path = path;
    const char* home = std::getenv("HOME");
    if(home && *home){
        std::string home_prefix = std::string(home) + "/";
        if(short_path.find(home_prefix) == 0){
            short_path = "~/" + short_path.substr(home_prefix.size());
        }
    }
    if(short_path.find("/Applications/") == 0){
        short_path = short_path.substr(std::string("/Applications/").size());
        short_path = "Apps/" + short_path;
    }
    return short_path;
}

static bool parse_app_line(const std::string& line, AppEntry& out){
    out = {};
    out.raw = line;
    size_t bar = line.find('|');
    if(bar == std::string::npos){
        return false;
    }
    out.name = line.substr(0, bar);
    std::string rest = line.substr(bar + 1);
    std::stringstream ss(rest);
    std::string item;
    while(std::getline(ss, item, '|')){
        if(item.rfind("bundle=", 0) == 0){
            out.bundle = item.substr(7);
        }else if(item.rfind("path=", 0) == 0){
            out.path = item.substr(5);
        }
    }
    return !out.name.empty();
}

static std::vector<AppEntry> parse_app_entries(const std::vector<std::string>& entries){
    std::vector<AppEntry> out;
    for(const auto& e : entries){
        AppEntry a;
        if(parse_app_line(e, a)){
            out.push_back(a);
            continue;
        }
        if(e.rfind("bundle:", 0) == 0){
            AppEntry b;
            b.name = e.substr(7);
            b.bundle = b.name;
            b.raw = e;
            out.push_back(b);
        }else if(e.rfind("path:", 0) == 0){
            AppEntry p;
            p.path = e.substr(5);
            p.name = std::filesystem::path(p.path).stem().string();
            p.raw = e;
            out.push_back(p);
        }else{
            AppEntry u;
            u.name = e;
            u.raw = e;
            out.push_back(u);
        }
    }
    return out;
}

static std::vector<std::string> app_entry_display(const std::vector<AppEntry>& entries){
    std::vector<std::string> lines;
    for(const auto& e : entries){
        std::string line = "\033[32m" + e.name + "\033[0m";
        if(!e.bundle.empty()){
            line += "  \033[90mbundle:" + e.bundle + "\033[0m";
        }
        if(!e.path.empty()){
            line += "  \033[90m" + shorten_app_path(e.path) + "\033[0m";
        }
        lines.push_back(line);
    }
    return lines;
}

static std::vector<std::string> app_entry_display_plain(const std::vector<AppEntry>& entries){
    std::vector<std::string> lines;
    for(const auto& e : entries){
        std::string line = e.name;
        if(!e.bundle.empty()){
            line += "  bundle:" + e.bundle;
        }
        if(!e.path.empty()){
            line += "  " + shorten_app_path(e.path);
        }
        lines.push_back(line);
    }
    return lines;
}

static int pick_app_group_index_manual(const std::vector<std::string>& display){
    if(display.empty()){
        return -1;
    }
    std::cout << "select app to remove:\n";
    for(size_t i = 0; i < display.size(); ++i){
        std::cout << "  [" << (i + 1) << "] " << display[i] << "\n";
    }
    std::cout << "enter number: ";
    std::string line;
    if(!std::getline(std::cin, line)){
        return -1;
    }
    int idx = 0;
    try{
        idx = std::stoi(line);
    }catch(...){
        return -1;
    }
    if(idx <= 0 || static_cast<size_t>(idx) > display.size()){
        return -1;
    }
    return idx - 1;
}

static int pick_app_group_index_fzf(const std::vector<std::string>& display){
    const char* no_fzf = std::getenv("BLISS_NO_FZF");
    if(no_fzf && *no_fzf != '\0'){
        return -1;
    }
    if(!command_exists("fzf") || display.empty()){
        return -1;
    }
    char tmpl[] = "/tmp/bliss_app_groups_XXXXXX";
    int fd = mkstemp(tmpl);
    if(fd < 0){
        return -1;
    }
    {
        std::ofstream out(tmpl, std::ios::trunc);
        for(const auto& e : display){
            out << e << "\n";
        }
    }
    std::string cmd = std::string("cat '") + tmpl + "' | fzf";
    FILE* pipe = popen(cmd.c_str(), "r");
    if(!pipe){
        std::remove(tmpl);
        return -1;
    }
    char buf[1024];
    std::string selection;
    if(fgets(buf, sizeof(buf), pipe)){
        selection = buf;
        selection.erase(selection.find_last_not_of("\r\n") + 1);
    }
    pclose(pipe);
    std::remove(tmpl);
    if(selection.empty()){
        return -1;
    }
    for(size_t i = 0; i < display.size(); ++i){
        if(display[i] == selection){
            return static_cast<int>(i);
        }
    }
    return -1;
}

static std::string get_bundle_id_for_path(const std::string& app_path){
    std::string cmd = "/usr/bin/mdls -name kMDItemCFBundleIdentifier -raw \"" + app_path + "\" 2>/dev/null";
    FILE* pipe = popen(cmd.c_str(), "r");
    if(!pipe){
        return "";
    }
    char buf[512];
    std::string bundle;
    if(fgets(buf, sizeof(buf), pipe)){
        bundle = buf;
        bundle.erase(bundle.find_last_not_of("\r\n") + 1);
    }
    pclose(pipe);
    if(bundle == "(null)"){
        return "";
    }
    return bundle;
}

static bool read_end_time(long long& end_time){
    std::ifstream in(kEndTimePath);
    if(!in.is_open()){
        return false;
    }
    in >> end_time;
    return !in.fail();
}

static void print_status(){
    long long end_time = 0;
    if(!read_end_time(end_time)){
        std::cout << "status: not running\n";
        return;
    }
    auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    long long remaining = end_time - static_cast<long long>(now);
    std::cout << "status: running\n";
    std::cout << "ends at (epoch): " << end_time << "\n";
    if(remaining > 0){
        long long minutes = remaining / 60;
        long long seconds = remaining % 60;
        std::cout << "remaining: " << minutes << "m " << seconds << "s\n";
    }else{
        std::cout << "remaining: 0m 0s\n";
    }
    if(geteuid() == 0){
        std::cout << "pf table active: " << (is_firewall_block_active() ? "yes" : "no") << "\n";
        return;
    }
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if(fd >= 0){
        sockaddr_un addr{};
        addr.sun_family = AF_UNIX;
        std::snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", "/var/run/bliss.sock");
        if(connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) == 0){
            std::string msg = "status\n";
            write(fd, msg.c_str(), msg.size());
            char buf[128];
            ssize_t n = read(fd, buf, sizeof(buf) - 1);
            if(n > 0){
                buf[n] = '\0';
                std::string resp(buf);
                if(resp.rfind("pf:", 0) == 0){
                    std::cout << "pf table active: " << resp.substr(3) << "\n";
                    close(fd);
                    return;
                }
            }
        }
        close(fd);
    }
    std::cout << "pf table active: unknown (requires root helper)\n";
}

static bool run_uninstall_script(){
    const char* script_paths[] = {
        "/usr/local/share/bliss/uninstall.sh",
        "scripts/uninstall.sh"
    };
    for(const char* p : script_paths){
        if(file_exists(p)){
            std::string cmd = std::string("/bin/bash \"") + p + "\"";
            int rc = std::system(cmd.c_str());
            return rc == 0;
        }
    }
    std::cout << "uninstall script not found\n";
    return false;
}

static string get_exe_dir(const char* argv0){
    char resolved[PATH_MAX];
    if(realpath(argv0, resolved)){
        string path = resolved;
        size_t slash = path.find_last_of('/');
        if(slash == string::npos) return ".";
        return path.substr(0, slash);
    }
    return ".";
}

static string find_blissd_path(const char* argv0){
    string dir = get_exe_dir(argv0);
    string candidate = dir + "/blissd";
    if(file_exists(candidate.c_str())){
        char resolved[PATH_MAX];
        if(realpath(candidate.c_str(), resolved)){
            return string(resolved);
        }
        return candidate;
    }
    if(file_exists("/usr/local/bin/blissd")){
        return "/usr/local/bin/blissd";
    }
    return "";
}

static bool install_launchd_job(int minutes, const string& blissd_path){
    std::ofstream plist(kLaunchdPlistPath, std::ios::trunc);
    if(!plist.is_open()){
        std::cout << "[error] unable to write " << kLaunchdPlistPath << " (try running with sudo)\n";
        return false;
    }

    plist << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
          << "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n"
          << "<plist version=\"1.0\">\n"
          << "<dict>\n"
          << "  <key>Label</key>\n"
          << "  <string>" << kLaunchdLabel << "</string>\n"
          << "  <key>ProgramArguments</key>\n"
          << "  <array>\n"
          << "    <string>" << blissd_path << "</string>\n"
          << "    <string>" << minutes << "</string>\n"
          << "  </array>\n"
          << "  <key>RunAtLoad</key>\n"
          << "  <true/>\n"
          << "  <key>KeepAlive</key>\n"
          << "  <false/>\n"
          << "  <key>StandardOutPath</key>\n"
          << "  <string>/tmp/blissd.out</string>\n"
          << "  <key>StandardErrorPath</key>\n"
          << "  <string>/tmp/blissd.err</string>\n"
          << "</dict>\n"
          << "</plist>\n";
    plist.close();

    std::string bootout = std::string("/bin/launchctl bootout system/") + kLaunchdLabel + " >/dev/null 2>&1";
    std::system(bootout.c_str());

    std::string bootstrap = std::string("/bin/launchctl bootstrap system ") + kLaunchdPlistPath;
    int rc = std::system(bootstrap.c_str());
    if(rc != 0){
        std::cout << "[error] launchctl bootstrap failed\n";
        return false;
    }
    return true;
}

static void unload_launchd_job(){
    std::string bootout = std::string("/bin/launchctl bootout system/") + kLaunchdLabel + " >/dev/null 2>&1";
    std::system(bootout.c_str());
    std::remove(kLaunchdPlistPath);
}

static bool plist_uses_absolute_blissd(){
    std::ifstream in(kLaunchdPlistPath);
    if(!in.is_open()){
        return false;
    }
    std::ostringstream buffer;
    buffer << in.rdbuf();
    std::string content = buffer.str();
    size_t key_pos = content.find("<key>ProgramArguments</key>");
    if(key_pos == std::string::npos) return false;
    size_t str_start = content.find("<string>", key_pos);
    if(str_start == std::string::npos) return false;
    str_start += 8;
    size_t str_end = content.find("</string>", str_start);
    if(str_end == std::string::npos) return false;
    std::string path = content.substr(str_start, str_end - str_start);
    return !path.empty() && path[0] == '/';
}

static bool is_launchd_job_loaded(){
    std::string cmd = std::string("/bin/launchctl print system/") + kLaunchdLabel + " >/dev/null 2>&1";
    int rc = std::system(cmd.c_str());
    return rc == 0;
}

static bool write_end_time(int minutes){
    auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    long long end_time = static_cast<long long>(now) + static_cast<long long>(minutes) * 60;
    std::ofstream out(kEndTimePath, std::ios::trunc);
    if(!out.is_open()){
        std::cout << "[error] unable to write " << kEndTimePath << " (try running with sudo)\n";
        return false;
    }
    out << end_time << "\n";
    return true;
}

static void remove_end_time(){
    std::remove(kEndTimePath);
}

int main(int argc, char* argv[]){
    if(argc < 2){
        print_usage();
        return 1;
    }

    string command = argv[1];
    if(command == "--help" || command == "help" || command == "-h"){
        print_usage();
        return 0;
    }
    if(command == "start"){
        bool is_root = geteuid() == 0;
        long long existing_end = 0;
        if(read_end_time(existing_end)){
            auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
            if(existing_end <= static_cast<long long>(now)){
                remove_firewall_block();
                remove_hosts_block();
                remove_end_time();
            }else{
                std::cout << "[error] session already running; wait or use panic\n";
                return 1;
            }
        }
        if(argc < 3){
            std::cout << "[error] start requires <minutes>\n";
            print_usage();
            return 1;
        }
        int minutes = 0;
        if(!parse_minutes(argv[2], minutes)){
            std::cout << "[error] invalid minutes; use 1-1440\n";
            return 1;
        }
        if(!is_root){
            std::string cfg = get_config_path();
            if(!send_to_root_helper("start " + std::to_string(minutes) + " " + cfg)){
                return 1;
            }
            std::cout << "lockdown started for " << minutes << " minutes\n";
            std::vector<std::string> domains;
            load_block_list(domains);
            std::cout << "blocking " << domains.size() << " domains\n";
            return 0;
        }
        // Ensure DNS resolution isn't poisoned by existing hosts block.
        remove_hosts_block();
        if(!apply_firewall_block()){
            return 1;
        }
        kill_browser_apps();
        drop_web_states();
        if(!apply_hosts_block()){
            return 1;
        }
        if(!write_end_time(minutes)){
            return 1;
        }
        if(is_launchd_job_loaded()){
            if(!plist_uses_absolute_blissd()){
                unload_launchd_job();
            }
        }
        if(!is_launchd_job_loaded()){
            string blissd_path = find_blissd_path(argv[0]);
            if(blissd_path.empty()){
                std::cout << "[error] unable to find blissd (install or use absolute path)\n";
                return 1;
            }
            if(!install_launchd_job(minutes, blissd_path)){
                return 1;
            }
        }
        std::vector<std::string> domains;
        load_block_list(domains);
        std::cout << "lockdown started for " << minutes << " minutes\n";
        std::cout << "blocking " << domains.size() << " domains\n";
        return 0;
    }

    if(command == "panic"){
        bool is_root = geteuid() == 0;
        long long end_time = 0;
        if(!read_end_time(end_time)){
            std::cout << "no active session; nothing to panic\n";
            return 0;
        }
        double accuracy = 0.0;
        if(!typing_test(accuracy)){
            std::cout << "puzzle failed (still blocked)\n";
            std::cout << "target: 95%, actual: " << static_cast<int>(accuracy + 0.5) << "%\n";
            return 1;
        }
        std::cout << "target: 95%, actual: " << static_cast<int>(accuracy + 0.5) << "%\n";
        if(!is_root){
            if(!send_to_root_helper("panic")){
                return 1;
            }
            std::cout << "panic succeeded (unblocked)\n";
            return 0;
        }
        unload_launchd_job();
        remove_end_time();
        if(!remove_hosts_block()){
            return 1;
        }
        remove_firewall_block();
        std::cout << "panic succeeded (unblocked)\n";
        return 0;
    }
    if(command == "status"){
        print_status();
        return 0;
    }
    if(command == "repair"){
        bool is_root = geteuid() == 0;
        if(!is_root){
            std::cout << "repair requires sudo: sudo bliss repair\n";
            return 1;
        }
        if(!repair_root_helper()){
            return 1;
        }
        unload_launchd_job();
        remove_end_time();
        remove_hosts_block();
        remove_firewall_block();
        drop_web_states();
        std::cout << "repaired and flushed\n";
        return 0;
    }
    if(command == "uninstall"){
        bool is_root = geteuid() == 0;
        if(!is_root){
            std::cout << "uninstall requires sudo: sudo bliss uninstall\n";
            return 1;
        }
        double accuracy = 0.0;
        if(!typing_test(accuracy)){
            std::cout << "puzzle failed (still installed)\n";
            std::cout << "target: 95%, actual: " << static_cast<int>(accuracy + 0.5) << "%\n";
            return 1;
        }
        std::cout << "target: 95%, actual: " << static_cast<int>(accuracy + 0.5) << "%\n";
        if(!run_uninstall_script()){
            return 1;
        }
        std::cout << "uninstall complete\n";
        return 0;
    }

    if(command == "config"){
        if(argc < 3){
            print_usage();
            return 1;
        }
        bool is_root = geteuid() == 0;
        long long end_time = 0;
        if(read_end_time(end_time)){
            auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
            if(end_time > static_cast<long long>(now)){
                std::cout << "[error] config is locked while a session is active\n";
                return 1;
            }
        }
        string sub = argv[2];
        if(sub == "app"){
            if(argc < 4){
                print_usage();
                return 1;
            }
            string action = argv[3];
            if(action == "add"){
                if(!is_root && !ensure_config_ownership()){
                    return 1;
                }
                std::string app_path;
                if(argc >= 5){
                    app_path = argv[4];
                }else{
                    app_path = pick_app_path_fzf();
                    if(app_path.empty()){
                        app_path = pick_app_path_manual();
                    }
                }
                if(app_path.empty()){
                    std::cout << "[error] no app selected (install fzf or pass a .app path)\n";
                    return 1;
                }
                std::string bundle = get_bundle_id_for_path(app_path);
                std::string name = std::filesystem::path(app_path).stem().string();
                std::string line = name + "|";
                if(!bundle.empty()){
                    line += "bundle=" + bundle + "|";
                }
                line += "path=" + app_path;
                add_block_app(line);
                std::cout << "selected: " << app_path << "\n";
                if(!bundle.empty()){
                    std::cout << "bundle: " << bundle << "\n";
                }
                std::cout << "added app\n";
                return 0;
            }
            if(action == "remove"){
                if(!is_root && !ensure_config_ownership()){
                    return 1;
                }
                std::vector<std::string> apps;
                if(!load_app_list(apps)){
                    return 1;
                }
                auto entries = parse_app_entries(apps);
                auto display_plain = app_entry_display_plain(entries);
                auto display_color = app_entry_display(entries);
                int idx = pick_app_group_index_fzf(display_plain);
                if(idx < 0){
                    idx = pick_app_group_index_manual(display_color);
                }
                if(idx < 0 || static_cast<size_t>(idx) >= entries.size()){
                    std::cout << "[error] no app selected\n";
                    return 1;
                }
                if(!remove_block_app(entries[idx].raw)){
                    return 1;
                }
                std::cout << "removed app\n";
                return 0;
            }
            if(action == "list"){
                std::vector<std::string> apps;
                if(!load_app_list(apps)){
                    return 1;
                }
                auto entries = parse_app_entries(apps);
                auto display = app_entry_display(entries);
                if(display.empty()){
                    std::cout << "no entries\n";
                    return 0;
                }
                for(const auto& line : display){
                    std::cout << line << "\n";
                }
                return 0;
            }
            print_usage();
            return 1;
        }
        if(sub == "website"){
            if(argc < 4){
                print_usage();
                return 1;
            }
            string action = argv[3];
            if(action == "add"){
                if(!is_root && !ensure_config_ownership()){
                    return 1;
                }
                if(argc < 5){
                    std::cout << "[error] config website add requires <domain>\n";
                    return 1;
                }
                std::string domain = normalize_domain(argv[4]);
                if(domain.empty()){
                    std::cout << "[error] invalid domain\n";
                    return 1;
                }
                if(!add_block_domain(domain)){
                    return 1;
                }
                // auto-add www for bare domains
                if(domain.find('.') != std::string::npos && domain.find('.') == domain.rfind('.')){
                    add_block_domain("www." + domain);
                }
                std::cout << "added domain\n";
                return 0;
            }
            if(action == "remove"){
                if(!is_root && !ensure_config_ownership()){
                    return 1;
                }
                if(argc < 5){
                    std::cout << "[error] config website remove requires <domain>\n";
                    return 1;
                }
                std::string domain = normalize_domain(argv[4]);
                if(domain.empty()){
                    std::cout << "[error] invalid domain\n";
                    return 1;
                }
                if(!remove_block_domain(domain)){
                    return 1;
                }
                std::cout << "removed domain\n";
                return 0;
            }
            if(action == "list"){
                std::vector<std::string> domains;
                if(!load_block_list(domains)){
                    return 1;
                }
                if(domains.empty()){
                    std::cout << "no entries\n";
                    return 0;
                }
                for(const auto& d : domains){
                    std::cout << d << "\n";
                }
                return 0;
            }
            print_usage();
            return 1;
        }
        if(sub == "browser"){
            if(argc < 4){
                print_usage();
                return 1;
            }
            string action = argv[3];
            if(action == "add"){
                if(!is_root && !ensure_config_ownership()){
                    return 1;
                }
                std::string name;
                if(argc >= 5){
                    std::string input = argv[4];
                    if(input.find('/') != std::string::npos || input.size() > 4 && input.rfind(".app") == input.size() - 4){
                        std::filesystem::path p(input);
                        if(p.extension() == ".app"){
                            name = p.stem().string();
                        }
                    }
                    if(name.empty()){
                        name = input;
                    }
                }else{
                    std::string app_path = pick_app_path_fzf();
                    if(app_path.empty()){
                        app_path = pick_app_path_manual();
                    }
                    if(app_path.empty()){
                        std::cout << "[error] no app selected (install fzf or pass a .app path)\n";
                        return 1;
                    }
                    name = std::filesystem::path(app_path).stem().string();
                    std::cout << "selected: " << app_path << "\n";
                }
                if(!add_browser_name(name)){
                    return 1;
                }
                std::cout << "added browser: " << name << "\n";
                std::cout << "note: browsers will be closed on start; save work first\n";
                return 0;
            }
            if(action == "remove"){
                if(!is_root && !ensure_config_ownership()){
                    return 1;
                }
                std::string name;
                if(argc >= 5){
                    name = argv[4];
                }else{
                    std::vector<std::string> names;
                    if(!load_browser_list(names)){
                        return 1;
                    }
                    if(names.empty()){
                        std::cout << "no entries\n";
                        return 0;
                    }
                    std::string picked = pick_app_entry_fzf(names);
                    if(picked.empty()){
                        picked = pick_app_entry_manual(names);
                    }
                    if(picked.empty()){
                        std::cout << "[error] no browser selected\n";
                        return 1;
                    }
                    name = picked;
                }
                if(!remove_browser_name(name)){
                    return 1;
                }
                std::cout << "removed browser: " << name << "\n";
                return 0;
            }
            if(action == "list"){
                std::vector<std::string> names;
                if(!load_browser_list(names)){
                    return 1;
                }
                if(names.empty()){
                    std::cout << "no entries\n";
                    return 0;
                }
                for(const auto& n : names){
                    std::cout << n << "\n";
                }
                return 0;
            }
            print_usage();
            return 1;
        }
        if(sub == "quotes"){
            if(argc < 4){
                std::cout << "[error] options: short, medium, long, huge\n";
                return 1;
            }
            std::string q = argv[3];
            if(q != "short" && q != "medium" && q != "long" && q != "huge"){
                std::cout << "[error] options: short, medium, long, huge\n";
                return 1;
            }
            if(!is_root && !ensure_config_ownership()){
                return 1;
            }
            if(!write_quotes_length(q)){
                return 1;
            }
            std::cout << "quotes: " << q << "\n";
            return 0;
        }
        std::cout << "[error] use: bliss config website <add|remove|list>\n";
        print_usage();
        return 1;
    }

    std::cout << "Unknown command: " << command << "\n";
    print_usage();
    return 1;
}
