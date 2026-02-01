#pragma once

#include <string>
#include <vector>

bool apply_hosts_block();
bool remove_hosts_block();
bool parse_minutes(const char* s, int& out_minutes);
bool load_block_list(std::vector<std::string>& out_domains);
bool add_block_domain(const std::string& domain);
bool remove_block_domain(const std::string& domain);
std::string get_config_path();
bool apply_firewall_block();
bool remove_firewall_block();
bool is_firewall_block_active();
void set_config_path_override(const std::string& path);
bool load_app_list(std::vector<std::string>& out_apps);
bool add_block_app(const std::string& app);
bool remove_block_app(const std::string& app);
std::string get_app_config_path();
