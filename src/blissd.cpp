#include "hosts_block.h"

#include <chrono>
#include <fstream>
#include <iostream>
#include <thread>
#include <vector>
#include <sys/stat.h>

static const char* kEndTimePath = "/var/db/bliss_end_time";

static bool read_end_time(long long& end_time){
    std::ifstream in(kEndTimePath);
    if(!in.is_open()){
        return false;
    }
    in >> end_time;
    return !in.fail();
}

static std::string console_uid(){
    struct stat st{};
    if(stat("/dev/console", &st) == 0){
        return std::to_string(st.st_uid);
    }
    return "";
}

static void kill_blocked_apps(){
    std::vector<std::string> apps;
    if(!load_app_list(apps)) return;
    std::string uid = console_uid();
    for(const auto& entry : apps){
        if(entry.rfind("bundle:", 0) == 0){
            std::string bundle = entry.substr(7);
            std::string cmd;
            if(!uid.empty()){
                cmd = "/bin/launchctl asuser " + uid + " /usr/bin/osascript -e 'tell application id \"" + bundle + "\" to quit' >/dev/null 2>&1";
            }else{
                cmd = "/usr/bin/osascript -e 'tell application id \"" + bundle + "\" to quit' >/dev/null 2>&1";
            }
            std::system(cmd.c_str());
            continue;
        }
        if(entry.rfind("path:", 0) == 0){
            std::string path = entry.substr(5);
            std::string pkill_path = "/usr/bin/pkill -f \"" + path + "/Contents/\" >/dev/null 2>&1";
            std::system(pkill_path.c_str());
            continue;
        }
        if(entry.rfind("proc:", 0) == 0){
            std::string name = entry.substr(5);
            std::string pkill_name = "/usr/bin/pkill -x \"" + name + "\" >/dev/null 2>&1";
            std::system(pkill_name.c_str());
        }
    }
}

int main(int argc, char* argv[]){
    if(argc >= 3){
        set_config_path_override(argv[2]);
    }
    long long end_time = 0;
    if(!read_end_time(end_time)){
        if(argc < 2){
            std::cout << "[blissd] missing minutes/end time\n";
            return 1;
        }
        int minutes = 0;
        if(!parse_minutes(argv[1], minutes)){
            std::cout << "[blissd] invalid minutes\n";
            return 1;
        }
        auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
        end_time = static_cast<long long>(now) + static_cast<long long>(minutes) * 60;
    }

    auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    long long remaining = end_time - static_cast<long long>(now);
    if(remaining > 0){
        long long half = remaining / 2;
        long long slept = 0;
        while(slept < remaining){
            kill_blocked_apps();
            long long target = (slept < half) ? half : remaining;
            long long chunk = target - slept;
            if(chunk <= 0){
                chunk = 3;
            }
            if(chunk > 3){
                chunk = 3;
            }
            std::this_thread::sleep_for(std::chrono::seconds(chunk));
            slept += chunk;
            if(slept >= half && half > 0){
                apply_firewall_block();
                half = 0;
            }
        }
    }
    if(!remove_hosts_block()){
        std::cout << "[blissd] failed to remove block\n";
        return 1;
    }
    remove_firewall_block();
    std::remove(kEndTimePath);
    std::cout << "[blissd] unblocked\n";
    return 0;
}
