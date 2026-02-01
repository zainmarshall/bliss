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
static const char* kDefaultDomains[] = {
    "youtube.com",
    "www.youtube.com",
    "m.youtube.com",
    "youtu.be"
};
static const size_t kDefaultDomainCount = sizeof(kDefaultDomains) / sizeof(kDefaultDomains[0]);
static std::string g_config_path_override;

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

void set_config_path_override(const std::string& path){
    g_config_path_override = path;
}

static bool ensure_config_dir(){
    std::error_code ec;
    std::filesystem::create_directories(get_config_dir(), ec);
    return !ec;
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
        for(size_t i = 0; i < kDefaultDomainCount; ++i){
            out_domains.push_back(kDefaultDomains[i]);
        }
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

    if(uniq.empty()){
        for(size_t i = 0; i < kDefaultDomainCount; ++i){
            uniq.insert(kDefaultDomains[i]);
        }
    }

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
    for(const auto& d : domains){
        if(d == cleaned){
            return true;
        }
    }
    domains.push_back(cleaned);
    return write_block_list(domains);
}

bool remove_block_domain(const std::string& domain){
    std::string cleaned = to_lower_ascii(trim(domain));
    if(cleaned.empty()){
        std::cout << "[error] invalid domain\n";
        return false;
    }
    std::vector<std::string> domains;
    if(!load_block_list(domains)){
        return false;
    }
    std::vector<std::string> filtered;
    for(const auto& d : domains){
        if(d != cleaned){
            filtered.push_back(d);
        }
    }
    return write_block_list(filtered);
}

static void flush_dns(){
    std::system("/usr/bin/dscacheutil -flushcache");
    std::system("/usr/bin/killall -HUP mDNSResponder");
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
