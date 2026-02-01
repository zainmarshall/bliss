#include "hosts_block.h"

#include <chrono>
#include <fstream>
#include <iostream>
#include <thread>

static const char* kEndTimePath = "/var/db/bliss_end_time";

static bool read_end_time(long long& end_time){
    std::ifstream in(kEndTimePath);
    if(!in.is_open()){
        return false;
    }
    in >> end_time;
    return !in.fail();
}

int main(int argc, char* argv[]){
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
        if(half > 0){
            std::this_thread::sleep_for(std::chrono::seconds(half));
            apply_firewall_block();
            std::this_thread::sleep_for(std::chrono::seconds(remaining - half));
        }else{
            std::this_thread::sleep_for(std::chrono::seconds(remaining));
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
