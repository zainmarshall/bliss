#include "hosts_block.h"

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <limits.h>
#include <fstream>
#include <iostream>
#include <set>
#include <sstream>
#include <string>
#include <vector>

using std::string;

static const char* kHostsPath = "/etc/hosts";
static const char* kBlockStart = "# bliss-block start";
static const char* kBlockEnd = "# bliss-block end";
static std::string g_config_path_override;

static std::string get_config_dir_from_override(){
    if(g_config_path_override.empty()){
        return "";
    }
    std::string path = g_config_path_override;
    size_t slash = path.find_last_of('/');
    if(slash == std::string::npos){
        return "";
    }
    return path.substr(0, slash);
}

bool parse_minutes(const char* s, int& out_minutes){
    if(!s || *s == '\0') return false;
    char* end = nullptr;
    long val = std::strtol(s, &end, 10);
    if(*end != '\0') return false;
    if(val <= 0 || val > 1440) return false;
    out_minutes = static_cast<int>(val);
    return true;
}

static std::string trim(const std::string& s){
    size_t start = s.find_first_not_of(" \t\r\n");
    if(start == std::string::npos) return "";
    size_t end = s.find_last_not_of(" \t\r\n");
    return s.substr(start, end - start + 1);
}

static std::string to_lower_ascii(const std::string& s){
    std::string out = s;
    for(char& c : out){
        if(c >= 'A' && c <= 'Z'){
            c = static_cast<char>(c - 'A' + 'a');
        }
    }
    return out;
}

static bool is_valid_domain(const std::string& domain){
    if(domain.empty() || domain.size() > 253) return false;
    if(domain.front() == '.' || domain.back() == '.') return false;
    if(domain.front() == '-' || domain.back() == '-') return false;
    for(char c : domain){
        bool ok = (c >= 'a' && c <= 'z') ||
                  (c >= '0' && c <= '9') ||
                  c == '.' || c == '-';
        if(!ok) return false;
    }
    return true;
}

static std::string get_config_dir(){
    const char* home = std::getenv("HOME");
    if(!home || *home == '\0'){
        return ".";
    }
    return std::string(home) + "/.config/bliss";
}

std::string get_config_path(){
    if(!g_config_path_override.empty()){
        return g_config_path_override;
    }
    return get_config_dir() + "/blocks.txt";
}

std::string get_app_config_path(){
    if(!g_config_path_override.empty()){
        std::string dir = get_config_dir_from_override();
        if(!dir.empty()){
            return dir + "/apps.txt";
        }
    }
    return get_config_dir() + "/apps.txt";
}

void set_config_path_override(const std::string& path){
    g_config_path_override = path;
}

std::string get_quotes_config_path(){
    if(!g_config_path_override.empty()){
        std::string dir = get_config_dir_from_override();
        if(!dir.empty()){
            return dir + "/quotes.txt";
        }
    }
    return get_config_dir() + "/quotes.txt";
}

std::string get_browser_config_path(){
    if(!g_config_path_override.empty()){
        std::string dir = get_config_dir_from_override();
        if(!dir.empty()){
            return dir + "/browsers.txt";
        }
    }
    return get_config_dir() + "/browsers.txt";
}

static bool ensure_config_dir(){
    std::error_code ec;
    std::filesystem::create_directories(get_config_dir(), ec);
    return !ec;
}

bool write_quotes_length(const std::string& value){
    if(!ensure_config_dir()){
        std::cout << "[error] unable to create config directory (check permissions)\n";
        return false;
    }
    std::ofstream out(get_quotes_config_path(), std::ios::trunc);
    if(!out.is_open()){
        std::cout << "[error] unable to write quotes config (check permissions)\n";
        return false;
    }
    out << value << "\n";
    return true;
}

bool read_quotes_length(std::string& value){
    std::ifstream in(get_quotes_config_path());
    if(!in.is_open()){
        value = "medium";
        return true;
    }
    std::string line;
    if(!std::getline(in, line)){
        value = "medium";
        return true;
    }
    line = trim(line);
    if(line.empty()){
        value = "medium";
        return true;
    }
    value = line;
    return true;
}

static bool write_browser_list(const std::vector<std::string>& names){
    if(!ensure_config_dir()){
        std::cout << "[error] unable to create config directory (check permissions)\n";
        return false;
    }
    std::ofstream out(get_browser_config_path(), std::ios::trunc);
    if(!out.is_open()){
        std::cout << "[error] unable to write browser config file (check permissions)\n";
        std::cout << "if this was created by sudo, run: sudo chown -R $USER ~/.config/bliss\n";
        return false;
    }
    for(const auto& n : names){
        out << n << "\n";
    }
    return true;
}

bool load_browser_list(std::vector<std::string>& out_names){
    out_names.clear();
    std::ifstream in(get_browser_config_path());
    if(!in.is_open()){
        return write_browser_list(out_names);
    }
    std::set<std::string> uniq;
    std::string line;
    while(std::getline(in, line)){
        std::string t = trim(line);
        if(t.empty() || t[0] == '#') continue;
        uniq.insert(t);
    }
    for(const auto& n : uniq){
        out_names.push_back(n);
    }
    return true;
}

bool add_browser_name(const std::string& name){
    std::string cleaned = trim(name);
    if(cleaned.empty()){
        std::cout << "[error] invalid browser name\n";
        return false;
    }
    std::vector<std::string> names;
    if(!load_browser_list(names)){
        return false;
    }
    for(const auto& n : names){
        if(n == cleaned){
            return true;
        }
    }
    names.push_back(cleaned);
    return write_browser_list(names);
}

bool remove_browser_name(const std::string& name){
    std::string cleaned = trim(name);
    if(cleaned.empty()){
        std::cout << "[error] invalid browser name\n";
        return false;
    }
    std::vector<std::string> names;
    if(!load_browser_list(names)){
        return false;
    }
    std::vector<std::string> filtered;
    for(const auto& n : names){
        if(n != cleaned){
            filtered.push_back(n);
        }
    }
    return write_browser_list(filtered);
}

static bool write_block_list(const std::vector<std::string>& domains){
    if(!ensure_config_dir()){
        std::cout << "[error] unable to create config directory (check permissions)\n";
        return false;
    }
    std::ofstream out(get_config_path(), std::ios::trunc);
    if(!out.is_open()){
        std::cout << "[error] unable to write config file (check permissions)\n";
        std::cout << "if this was created by sudo, run: sudo chown -R $USER ~/.config/bliss\n";
        return false;
    }
    for(const auto& d : domains){
        out << d << "\n";
    }
    return true;
}

bool load_block_list(std::vector<std::string>& out_domains){
    out_domains.clear();
    std::ifstream in(get_config_path());
    if(!in.is_open()){
        return write_block_list(out_domains);
    }

    std::set<std::string> uniq;
    std::string line;
    while(std::getline(in, line)){
        std::string t = trim(line);
        if(t.empty() || t[0] == '#') continue;
        std::string lower = to_lower_ascii(t);
        if(is_valid_domain(lower)){
            uniq.insert(lower);
        }
    }
    in.close();

    for(const auto& d : uniq){
        out_domains.push_back(d);
    }
    return true;
}

bool add_block_domain(const std::string& domain){
    std::string cleaned = to_lower_ascii(trim(domain));
    if(!is_valid_domain(cleaned)){
        std::cout << "[error] invalid domain\n";
        return false;
    }
    std::vector<std::string> domains;
    if(!load_block_list(domains)){
        return false;
    }
    auto add_unique = [&](const std::string& value){
        for(const auto& d : domains){
            if(d == value){
                return;
            }
        }
        domains.push_back(value);
    };
    add_unique(cleaned);
    return write_block_list(domains);
}

bool remove_block_domain(const std::string& domain){
    std::string cleaned = to_lower_ascii(trim(domain));
    if(cleaned.empty()){
        std::cout << "[error] invalid domain\n";
        return false;
    }
    std::set<std::string> remove_set;
    remove_set.insert(cleaned);
    if(cleaned.rfind("www.", 0) == 0){
        std::string base = cleaned.substr(4);
        if(!base.empty()){
            remove_set.insert(base);
        }
    }
    if(cleaned.find('.') != std::string::npos && cleaned.find('.') == cleaned.rfind('.')){
        remove_set.insert("www." + cleaned);
    }
    std::vector<std::string> domains;
    if(!load_block_list(domains)){
        return false;
    }
    std::vector<std::string> filtered;
    for(const auto& d : domains){
        if(remove_set.count(d) == 0){
            filtered.push_back(d);
        }
    }
    return write_block_list(filtered);
}

static bool write_app_list(const std::vector<std::string>& apps){
    if(!ensure_config_dir()){
        std::cout << "[error] unable to create config directory (check permissions)\n";
        return false;
    }
    std::ofstream out(get_app_config_path(), std::ios::trunc);
    if(!out.is_open()){
        std::cout << "[error] unable to write app config file (check permissions)\n";
        std::cout << "if this was created by sudo, run: sudo chown -R $USER ~/.config/bliss\n";
        return false;
    }
    for(const auto& a : apps){
        out << a << "\n";
    }
    return true;
}

bool load_app_list(std::vector<std::string>& out_apps){
    out_apps.clear();
    std::ifstream in(get_app_config_path());
    if(!in.is_open()){
        return true;
    }
    std::set<std::string> uniq;
    std::string line;
    while(std::getline(in, line)){
        std::string t = trim(line);
        if(t.empty() || t[0] == '#') continue;
        uniq.insert(t);
    }
    for(const auto& a : uniq){
        out_apps.push_back(a);
    }
    return true;
}

bool add_block_app(const std::string& app){
    std::string cleaned = trim(app);
    if(cleaned.empty()){
        std::cout << "[error] invalid app\n";
        return false;
    }
    std::vector<std::string> apps;
    if(!load_app_list(apps)){
        return false;
    }
    for(const auto& a : apps){
        if(a == cleaned){
            return true;
        }
    }
    apps.push_back(cleaned);
    return write_app_list(apps);
}

bool remove_block_app(const std::string& app){
    std::string cleaned = trim(app);
    if(cleaned.empty()){
        std::cout << "[error] invalid app\n";
        return false;
    }
    std::vector<std::string> apps;
    if(!load_app_list(apps)){
        return false;
    }
    std::vector<std::string> filtered;
    for(const auto& a : apps){
        if(a != cleaned){
            filtered.push_back(a);
        }
    }
    return write_app_list(filtered);
}

bool remove_block_app_entries(const std::vector<std::string>& entries){
    if(entries.empty()){
        return true;
    }
    std::vector<std::string> apps;
    if(!load_app_list(apps)){
        return false;
    }
    std::set<std::string> remove_set(entries.begin(), entries.end());
    std::vector<std::string> filtered;
    for(const auto& a : apps){
        if(remove_set.find(a) == remove_set.end()){
            filtered.push_back(a);
        }
    }
    return write_app_list(filtered);
}

static void flush_dns(){
    std::system("/usr/bin/dscacheutil -flushcache");
    std::system("/usr/bin/killall -HUP mDNSResponder");
}

void kill_browser_apps(){
    const char* defaults[] = {
        "Safari",
        "Google Chrome",
        "Google Chrome Helper",
        "Brave Browser",
        "Brave Browser Helper",
        "Firefox",
        "Firefox Developer Edition",
        "Arc",
        "Microsoft Edge",
        "Opera"
    };
    std::set<std::string> names;
    for(const auto* name : defaults){
        names.insert(name);
    }
    std::vector<std::string> extra;
    if(load_browser_list(extra)){
        for(const auto& name : extra){
            names.insert(name);
        }
    }
    for(const auto& name : names){
        std::string cmd = std::string("/usr/bin/pkill -x \"") + name + "\" >/dev/null 2>&1";
        std::system(cmd.c_str());
    }
}

bool apply_hosts_block(){
    std::ifstream in(kHostsPath);
    if(!in.is_open()){
        std::cerr << "[error] unable to read " << kHostsPath << " (" << std::strerror(errno) << ")\n";
        return false;
    }

    std::ostringstream buffer;
    buffer << in.rdbuf();
    string content = buffer.str();
    in.close();

    if(content.find(kBlockStart) != string::npos && content.find(kBlockEnd) != string::npos){
        std::cout << "hosts already blocked\n";
        return true;
    }

    std::ostringstream out;
    out << content;
    if(!content.empty() && content.back() != '\n'){
        out << "\n";
    }
    std::vector<std::string> domains;
    if(!load_block_list(domains)){
        return false;
    }
    if(domains.empty()){
        return true;
    }

    out << kBlockStart << "\n";
    for(const auto& d : domains){
        out << "0.0.0.0 " << d << "\n";
    }
    for(const auto& d : domains){
        out << "::1 " << d << "\n";
    }
    out << kBlockEnd << "\n";

    std::ofstream overwrite(kHostsPath, std::ios::trunc);
    if(!overwrite.is_open()){
        std::cerr << "[error] unable to write " << kHostsPath << " (" << std::strerror(errno) << ")\n";
        return false;
    }
    overwrite << out.str();
    overwrite.close();
    flush_dns();
    return true;
}

bool remove_hosts_block(){
    std::ifstream in(kHostsPath);
    if(!in.is_open()){
        std::cerr << "[error] unable to read " << kHostsPath << " (" << std::strerror(errno) << ")\n";
        return false;
    }

    std::ostringstream buffer;
    buffer << in.rdbuf();
    string content = buffer.str();
    in.close();

    size_t start = content.find(kBlockStart);
    size_t end = content.find(kBlockEnd);
    if(start == string::npos || end == string::npos || end < start){
        std::cout << "no bliss block found\n";
        return true;
    }

    end += std::strlen(kBlockEnd);
    if(end < content.size() && content[end] == '\n'){
        end += 1;
    }

    string updated = content.substr(0, start);
    updated += content.substr(end);

    std::ofstream overwrite(kHostsPath, std::ios::trunc);
    if(!overwrite.is_open()){
        std::cerr << "[error] unable to write " << kHostsPath << " (" << std::strerror(errno) << ")\n";
        return false;
    }
    overwrite << updated;
    overwrite.close();
    flush_dns();
    return true;
}
