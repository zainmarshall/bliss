#ifdef __linux__

#include "hosts_block.h"

#include <arpa/inet.h>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <netdb.h>
#include <set>
#include <sstream>
#include <string>
#include <sys/types.h>
#include <unistd.h>
#include <vector>

using std::string;

static const char* kChainName = "bliss";

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

static bool chain_exists(){
    string cmd = "iptables -L " + string(kChainName) + " -n >/dev/null 2>&1";
    return std::system(cmd.c_str()) == 0;
}

static bool ensure_chain(){
    if(chain_exists()){
        return true;
    }
    // Create the bliss chain.
    string create = "iptables -N " + string(kChainName) + " 2>/dev/null";
    std::system(create.c_str());

    // Also create for ip6tables.
    string create6 = "ip6tables -N " + string(kChainName) + " 2>/dev/null";
    std::system(create6.c_str());

    // Jump to bliss chain from OUTPUT and INPUT.
    string jump_out = "iptables -C OUTPUT -j " + string(kChainName) + " 2>/dev/null || iptables -I OUTPUT -j " + string(kChainName);
    string jump_in = "iptables -C INPUT -j " + string(kChainName) + " 2>/dev/null || iptables -I INPUT -j " + string(kChainName);
    std::system(jump_out.c_str());
    std::system(jump_in.c_str());

    string jump_out6 = "ip6tables -C OUTPUT -j " + string(kChainName) + " 2>/dev/null || ip6tables -I OUTPUT -j " + string(kChainName);
    string jump_in6 = "ip6tables -C INPUT -j " + string(kChainName) + " 2>/dev/null || ip6tables -I INPUT -j " + string(kChainName);
    std::system(jump_out6.c_str());
    std::system(jump_in6.c_str());

    return true;
}

static void flush_chain(){
    string flush4 = "iptables -F " + string(kChainName) + " 2>/dev/null";
    string flush6 = "ip6tables -F " + string(kChainName) + " 2>/dev/null";
    std::system(flush4.c_str());
    std::system(flush6.c_str());
}

static void remove_chain(){
    // Remove jump rules from OUTPUT and INPUT.
    string del_out = "iptables -D OUTPUT -j " + string(kChainName) + " 2>/dev/null";
    string del_in = "iptables -D INPUT -j " + string(kChainName) + " 2>/dev/null";
    std::system(del_out.c_str());
    std::system(del_in.c_str());

    string del_out6 = "ip6tables -D OUTPUT -j " + string(kChainName) + " 2>/dev/null";
    string del_in6 = "ip6tables -D INPUT -j " + string(kChainName) + " 2>/dev/null";
    std::system(del_out6.c_str());
    std::system(del_in6.c_str());

    // Flush and delete the chain.
    flush_chain();
    string del4 = "iptables -X " + string(kChainName) + " 2>/dev/null";
    string del6 = "ip6tables -X " + string(kChainName) + " 2>/dev/null";
    std::system(del4.c_str());
    std::system(del6.c_str());
}

bool apply_firewall_block(){
    if(!ensure_chain()){
        return false;
    }
    // Flush existing rules before re-populating.
    flush_chain();

    std::vector<string> domains;
    if(!load_block_list(domains)){
        return false;
    }
    if(domains.empty()){
        return true;
    }

    std::set<string> all_ips;
    for(const auto& d : domains){
        auto resolved = resolve_domain_ips(d);
        all_ips.insert(resolved.begin(), resolved.end());
    }

    for(const auto& ip : all_ips){
        bool is_v6 = ip.find(':') != string::npos;
        string tool = is_v6 ? "ip6tables" : "iptables";
        // Block outgoing traffic to the IP.
        string block_out = tool + " -A " + kChainName + " -d " + ip + " -j REJECT 2>/dev/null";
        std::system(block_out.c_str());
        // Block incoming traffic from the IP.
        string block_in = tool + " -A " + kChainName + " -s " + ip + " -j REJECT 2>/dev/null";
        std::system(block_in.c_str());
    }

    return true;
}

bool remove_firewall_block(){
    flush_chain();
    remove_chain();
    return true;
}

bool deep_remove_firewall_block(){
    return remove_firewall_block();
}

bool is_firewall_block_active(){
    if(!chain_exists()){
        return false;
    }
    // Check if chain has any rules.
    string cmd = "iptables -L " + string(kChainName) + " -n 2>/dev/null | grep -c REJECT";
    FILE* pipe = popen(cmd.c_str(), "r");
    if(!pipe) return false;
    char buf[32];
    string result;
    if(fgets(buf, sizeof(buf), pipe)){
        result = buf;
    }
    pclose(pipe);
    int count = 0;
    try { count = std::stoi(result); } catch(...) {}
    return count > 0;
}

void drop_web_states(){
    // On Linux, REJECT already sends RST/ICMP-unreachable, so existing
    // connections get torn down. Nothing extra needed.
}

#endif // __linux__
