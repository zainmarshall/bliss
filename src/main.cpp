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
#include <cstdio>
#include <filesystem>
#include <algorithm>
#include <cctype>

using std::string;

static const char* kLaunchdLabel = "com.bliss.timer";
static const char* kLaunchdPlistPath = "/Library/LaunchDaemons/com.bliss.timer.plist";
static const char* kEndTimePath = "/var/db/bliss_end_time";
static const char* kMenubarLabel = "com.bliss.menubar";

static void print_usage(){
    std::cout
        << "bliss start <minutes>\n"
        << "bliss panic\n"
        << "bliss status\n"
        << "bliss uninstall\n"
        << "bliss config add <domain>\n"
        << "bliss config remove <domain>\n"
        << "bliss config list\n"
        << "bliss config app add [<app name>]\n"
        << "bliss config app remove <app entry>\n"
        << "bliss config app list\n"
        << "bliss --help\n";
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

static void render_prompt(const std::string& prompt, const std::string& typed){
    std::cout << "\r\033[2K";
    for(size_t i = 0; i < prompt.size(); ++i){
        if(i < typed.size()){
            if(typed[i] == prompt[i]){
                std::cout << "\033[32m" << prompt[i] << "\033[0m";
            }else{
                std::cout << "\033[31m" << prompt[i] << "\033[0m";
            }
        }else{
            std::cout << "\033[90m" << prompt[i] << "\033[0m";
        }
    }
    std::cout << std::flush;
}

static bool typing_test(double& out_accuracy){
    const char* quotes_path = "quotes.txt";
    const char* quotes_fallback = "/usr/local/share/bliss/quotes.txt";
    std::vector<std::string> kQuotes;
    std::ifstream quotes_file(quotes_path);
    if(!quotes_file.is_open()){
        quotes_file.open(quotes_fallback);
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

static bool send_to_root_helper(const std::string& line){
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
        std::cout << "unable to reach bliss root helper (try: sudo bliss " << line << ")\n";
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
    std::cout << "pf table active: " << (is_firewall_block_active() ? "yes" : "no") << "\n";
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
                unload_launchd_job();
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
        if(!apply_hosts_block()){
            return 1;
        }
        if(!apply_firewall_block()){
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
    if(command == "uninstall"){
        bool is_root = geteuid() == 0;
        double accuracy = 0.0;
        if(!typing_test(accuracy)){
            std::cout << "puzzle failed (still installed)\n";
            std::cout << "target: 95%, actual: " << static_cast<int>(accuracy + 0.5) << "%\n";
            return 1;
        }
        std::cout << "target: 95%, actual: " << static_cast<int>(accuracy + 0.5) << "%\n";
        if(!is_root){
            if(!send_to_root_helper("uninstall")){
                return 1;
            }
            std::cout << "uninstall complete\n";
            return 0;
        }
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
        string sub = argv[2];
        if(sub == "app"){
            if(argc < 4){
                print_usage();
                return 1;
            }
            string action = argv[3];
            if(action == "add"){
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
                if(!bundle.empty()){
                    add_block_app("bundle:" + bundle);
                }
                add_block_app("path:" + app_path);
                std::cout << "selected: " << app_path << "\n";
                if(!bundle.empty()){
                    std::cout << "bundle: " << bundle << "\n";
                }
                std::cout << "added app\n";
                return 0;
            }
            if(action == "remove"){
                if(argc < 5){
                    std::cout << "[error] config app remove requires <app entry>\n";
                    return 1;
                }
                if(!remove_block_app(argv[4])){
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
                std::cout << "config: " << get_app_config_path() << "\n";
                for(const auto& a : apps){
                    std::cout << a << "\n";
                }
                return 0;
            }
            print_usage();
            return 1;
        }
        if(sub == "add"){
            if(argc < 4){
                std::cout << "[error] config add requires <domain>\n";
                return 1;
            }
            if(!add_block_domain(argv[3])){
                return 1;
            }
            std::cout << "added domain\n";
            return 0;
        }
        if(sub == "remove"){
            if(argc < 4){
                std::cout << "[error] config remove requires <domain>\n";
                return 1;
            }
            if(!remove_block_domain(argv[3])){
                return 1;
            }
            std::cout << "removed domain\n";
            return 0;
        }
        if(sub == "list"){
            std::vector<std::string> domains;
            if(!load_block_list(domains)){
                return 1;
            }
            std::cout << "config: " << get_config_path() << "\n";
            for(const auto& d : domains){
                std::cout << d << "\n";
            }
            return 0;
        }
        print_usage();
        return 1;
    }

    std::cout << "Unknown command: " << command << "\n";
    print_usage();
    return 1;
}
