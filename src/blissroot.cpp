#include "hosts_block.h"

#include <arpa/inet.h>
#include <chrono>
#include <cstring>
#include <fstream>
#include <iostream>
#include <netinet/in.h>
#include <sstream>
#include <string>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <unistd.h>

using std::string;

static const char* kSocketPath = "/var/run/bliss.sock";
static const char* kLaunchdLabel = "com.bliss.timer";
static const char* kLaunchdPlistPath = "/Library/LaunchDaemons/com.bliss.timer.plist";
static const char* kEndTimePath = "/var/db/bliss_end_time";

static void log_line(const std::string& msg){
    std::ofstream out("/tmp/blissroot.out", std::ios::app);
    if(out.is_open()){
        out << msg << "\n";
    }
}

static bool read_end_time(long long& end_time){
    std::ifstream in(kEndTimePath);
    if(!in.is_open()){
        return false;
    }
    in >> end_time;
    return !in.fail();
}

static bool write_end_time(int minutes){
    auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    long long end_time = static_cast<long long>(now) + static_cast<long long>(minutes) * 60;
    std::ofstream out(kEndTimePath, std::ios::trunc);
    if(!out.is_open()){
        std::cout << "[error] unable to write " << kEndTimePath << "\n";
        return false;
    }
    out << end_time << "\n";
    return true;
}

static void remove_end_time(){
    std::remove(kEndTimePath);
}

static bool is_launchd_job_loaded(){
    std::string cmd = std::string("/bin/launchctl print system/") + kLaunchdLabel + " >/dev/null 2>&1";
    int rc = std::system(cmd.c_str());
    return rc == 0;
}

static void unload_launchd_job(){
    std::string bootout = std::string("/bin/launchctl bootout system/") + kLaunchdLabel + " >/dev/null 2>&1";
    std::system(bootout.c_str());
    std::remove(kLaunchdPlistPath);
}

static bool install_launchd_job(int minutes, const std::string& config_path){
    std::ofstream plist(kLaunchdPlistPath, std::ios::trunc);
    if(!plist.is_open()){
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
          << "    <string>/usr/local/bin/blissd</string>\n"
          << "    <string>" << minutes << "</string>\n";
    if(!config_path.empty()){
        plist << "    <string>" << config_path << "</string>\n";
    }
    plist << "  </array>\n"
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
    return rc == 0;
}

static bool cleanup_if_stale(){
    long long end_time = 0;
    if(!read_end_time(end_time)){
        return false;
    }
    auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    if(end_time > static_cast<long long>(now)){
        return false;
    }
    remove_firewall_block();
    remove_hosts_block();
    remove_end_time();
    return true;
}

static bool handle_start(int minutes, const std::string& config_path, std::string& out_msg){
    log_line("handle_start called");
    if(!config_path.empty()){
        set_config_path_override(config_path);
    }
    cleanup_if_stale();
    if(is_launchd_job_loaded()){
        unload_launchd_job();
    }
    if(!apply_hosts_block()){
        log_line("apply_hosts_block failed");
        out_msg = "error: hosts block failed (see /tmp/blissroot.err)\n";
        return false;
    }
    if(!apply_firewall_block()){
        log_line("apply_firewall_block failed");
        out_msg = "error: firewall block failed (see /tmp/blissroot.err)\n";
        return false;
    }
    if(!write_end_time(minutes)){
        out_msg = "error: end time write failed (see /tmp/blissroot.err)\n";
        return false;
    }
    if(!install_launchd_job(minutes, config_path)){
        out_msg = "error: launchd install failed (see /tmp/blissroot.err)\n";
        return false;
    }
    out_msg = "ok";
    return true;
}

static bool handle_panic(std::string& out_msg){
    log_line("handle_panic called");
    unload_launchd_job();
    remove_end_time();
    if(!remove_hosts_block()){
        out_msg = "error: hosts unblock failed";
        return false;
    }
    remove_firewall_block();
    out_msg = "ok";
    return true;
}

static bool run_uninstall_script(){
    const char* script_paths[] = {
        "/usr/local/share/bliss/uninstall.sh",
        "scripts/uninstall.sh"
    };
    for(const char* p : script_paths){
        struct stat st{};
        if(stat(p, &st) == 0){
            std::string cmd = std::string("/bin/bash \"") + p + "\"";
            int rc = std::system(cmd.c_str());
            return rc == 0;
        }
    }
    return false;
}

static bool handle_uninstall(std::string& out_msg){
    log_line("handle_uninstall called");
    if(!run_uninstall_script()){
        out_msg = "error: uninstall failed";
        return false;
    }
    out_msg = "ok";
    return true;
}

static bool handle_line(const std::string& line, std::string& out_msg){
    std::istringstream iss(line);
    std::string cmd;
    iss >> cmd;
    if(cmd == "start"){
        int minutes = 0;
        iss >> minutes;
        if(minutes <= 0){
            out_msg = "error: invalid minutes";
            return false;
        }
        std::string cfg_path;
        std::getline(iss, cfg_path);
        if(!cfg_path.empty() && cfg_path[0] == ' '){
            cfg_path.erase(0, cfg_path.find_first_not_of(' '));
        }
        return handle_start(minutes, cfg_path, out_msg);
    }
    if(cmd == "panic"){
        return handle_panic(out_msg);
    }
    if(cmd == "uninstall"){
        return handle_uninstall(out_msg);
    }
    if(cmd == "status"){
        out_msg = std::string("pf: ") + (is_firewall_block_active() ? "yes" : "no");
        return true;
    }
    out_msg = "error: unknown command";
    return false;
}

int main(){
    log_line("blissroot started");
    unlink(kSocketPath);
    int fd = socket(AF_UNIX, SOCK_STREAM, 0);
    if(fd < 0){
        return 1;
    }
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::snprintf(addr.sun_path, sizeof(addr.sun_path), "%s", kSocketPath);
    if(bind(fd, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0){
        close(fd);
        return 1;
    }
    chmod(kSocketPath, 0666);
    if(listen(fd, 5) != 0){
        close(fd);
        return 1;
    }

    while(true){
        int client = accept(fd, nullptr, nullptr);
        if(client < 0){
            continue;
        }
        char buf[512];
        ssize_t n = read(client, buf, sizeof(buf) - 1);
        if(n > 0){
            buf[n] = '\0';
            std::string line(buf);
            line.erase(line.find_last_not_of("\r\n") + 1);
            std::string out_msg;
            handle_line(line, out_msg);
            out_msg.push_back('\n');
            write(client, out_msg.c_str(), out_msg.size());
        }
        close(client);
    }
    return 0;
}
