#include "hosts_block.h"

#include <arpa/inet.h>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <netdb.h>
#include <set>
#include <string>
#include <sys/types.h>
#include <unistd.h>
#include <vector>

using std::string;

static const char* kPfConfPath = "/etc/pf.conf";
static const char* kPfAnchorPath = "/etc/pf.anchors/bliss";
static const char* kAnchorMarker = "anchor \"bliss\"";
static const char* kLoadMarker = "load anchor \"bliss\" from \"/etc/pf.anchors/bliss\"";
static const char* kTableName = "bliss_block";

static bool file_contains_line(const string& path, const string& needle){
    std::ifstream in(path);
    if(!in.is_open()) return false;
    string line;
    while(std::getline(in, line)){
        if(line.find(needle) != string::npos) return true;
    }
    return false;
}

static bool ensure_pf_anchor_files(){
    if(!file_contains_line(kPfConfPath, kAnchorMarker)){
        std::ofstream out(kPfConfPath, std::ios::app);
        if(!out.is_open()){
            std::cout << "[error] unable to write " << kPfConfPath << " (try running with sudo)\n";
            return false;
        }
        out << "\n" << kAnchorMarker << "\n" << kLoadMarker << "\n";
    }

    std::ofstream anchor(kPfAnchorPath, std::ios::trunc);
    if(!anchor.is_open()){
        std::cout << "[error] unable to write " << kPfAnchorPath << " (try running with sudo)\n";
        return false;
    }
    anchor << "table <" << kTableName << "> persist\n"
           << "block drop out quick to <" << kTableName << ">\n"
           << "block drop in quick from <" << kTableName << ">\n";
    return true;
}

static bool reload_pf(){
    int rc = std::system("/sbin/pfctl -E >/dev/null 2>&1");
    if(rc != 0){
        std::cout << "[error] pfctl enable failed\n";
        return false;
    }
    rc = std::system("/sbin/pfctl -f /etc/pf.conf >/dev/null 2>&1");
    if(rc != 0){
        std::cout << "[error] pfctl reload failed\n";
        return false;
    }
    return true;
}

static std::set<string> resolve_domain_ips(const string& domain){
    std::set<string> out;
    struct addrinfo hints{};
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    struct addrinfo* res = nullptr;
    if(getaddrinfo(domain.c_str(), nullptr, &hints, &res) != 0){
        return out;
    }
    for(struct addrinfo* p = res; p != nullptr; p = p->ai_next){
        char buf[INET6_ADDRSTRLEN];
        void* addr = nullptr;
        if(p->ai_family == AF_INET){
            addr = &reinterpret_cast<struct sockaddr_in*>(p->ai_addr)->sin_addr;
        }else if(p->ai_family == AF_INET6){
            addr = &reinterpret_cast<struct sockaddr_in6*>(p->ai_addr)->sin6_addr;
        }
        if(addr && inet_ntop(p->ai_family, addr, buf, sizeof(buf))){
            out.insert(string(buf));
        }
    }
    freeaddrinfo(res);
    return out;
}

static bool write_table_file(const std::set<string>& ips, string& out_path){
    char tmpl[] = "/tmp/bliss_pf_XXXXXX";
    int fd = mkstemp(tmpl);
    if(fd < 0){
        std::cout << "[error] unable to create temp file\n";
        return false;
    }
    FILE* f = fdopen(fd, "w");
    if(!f){
        close(fd);
        std::cout << "[error] unable to open temp file\n";
        return false;
    }
    for(const auto& ip : ips){
        std::fprintf(f, "%s\n", ip.c_str());
    }
    std::fclose(f);
    out_path = tmpl;
    return true;
}

static bool load_pf_table(const std::set<string>& ips){
    if(ips.empty()){
        std::cout << "[error] no IPs resolved for block list\n";
        return false;
    }
    string path;
    if(!write_table_file(ips, path)){
        return false;
    }
    string cmd = string("/sbin/pfctl -t ") + kTableName + " -T replace -f " + path + " >/dev/null 2>&1";
    int rc = std::system(cmd.c_str());
    std::remove(path.c_str());
    if(rc != 0){
        std::cout << "[error] pfctl table update failed\n";
        return false;
    }
    return true;
}

bool apply_firewall_block(){
    if(!ensure_pf_anchor_files()){
        return false;
    }
    if(!reload_pf()){
        return false;
    }
    std::vector<string> domains;
    if(!load_block_list(domains)){
        return false;
    }
    std::set<string> ips;
    for(const auto& d : domains){
        auto resolved = resolve_domain_ips(d);
        ips.insert(resolved.begin(), resolved.end());
    }
    return load_pf_table(ips);
}

bool remove_firewall_block(){
    std::string cmd = string("/sbin/pfctl -t ") + kTableName + " -T flush >/dev/null 2>&1";
    std::system(cmd.c_str());
    return true;
}

bool is_firewall_block_active(){
    std::string cmd = string("/sbin/pfctl -t ") + kTableName + " -T show >/dev/null 2>&1";
    int rc = std::system(cmd.c_str());
    return rc == 0;
}
