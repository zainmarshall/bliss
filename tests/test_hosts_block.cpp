#include "../src/hosts_block.h"

#include <cassert>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <unistd.h>
#include <vector>

static int tests_run = 0;
static int tests_passed = 0;

#define TEST(name) \
    static void test_##name(); \
    struct Register_##name { Register_##name() { test_##name(); } } reg_##name; \
    static void test_##name()

#define ASSERT(expr) do { \
    tests_run++; \
    if (!(expr)) { \
        std::cerr << "  FAIL: " #expr " (" << __FILE__ << ":" << __LINE__ << ")\n"; \
    } else { \
        tests_passed++; \
    } \
} while(0)

#define ASSERT_EQ(a, b) do { \
    tests_run++; \
    if ((a) != (b)) { \
        std::cerr << "  FAIL: " #a " == " #b " (got \"" << (a) << "\" vs \"" << (b) << "\")\n"; \
    } else { \
        tests_passed++; \
    } \
} while(0)

// Helper: create a temp directory for test config isolation
class TempDir {
public:
    TempDir() {
        char tmpl[] = "/tmp/bliss_test_XXXXXX";
        char* result = mkdtemp(tmpl);
        if (result) path_ = result;
    }
    ~TempDir() {
        if (!path_.empty()) {
            std::filesystem::remove_all(path_);
        }
    }
    const std::string& path() const { return path_; }
    std::string file(const std::string& name) const { return path_ + "/" + name; }
private:
    std::string path_;
};

// ---- parse_minutes tests ----

TEST(parse_minutes_valid) {
    std::cout << "test: parse_minutes_valid\n";
    int m = 0;
    ASSERT(parse_minutes("25", m));
    ASSERT_EQ(m, 25);
    ASSERT(parse_minutes("1", m));
    ASSERT_EQ(m, 1);
    ASSERT(parse_minutes("1440", m));
    ASSERT_EQ(m, 1440);
}

TEST(parse_minutes_invalid) {
    std::cout << "test: parse_minutes_invalid\n";
    int m = 0;
    ASSERT(!parse_minutes("0", m));
    ASSERT(!parse_minutes("-1", m));
    ASSERT(!parse_minutes("1441", m));
    ASSERT(!parse_minutes("abc", m));
    ASSERT(!parse_minutes("", m));
    ASSERT(!parse_minutes(nullptr, m));
    ASSERT(!parse_minutes("25abc", m));
}

// ---- domain block list tests ----

TEST(add_and_load_domains) {
    std::cout << "test: add_and_load_domains\n";
    TempDir tmp;
    set_config_path_override(tmp.file("blocks.txt"));

    ASSERT(add_block_domain("example.com"));
    ASSERT(add_block_domain("test.org"));
    // Duplicate should be fine
    ASSERT(add_block_domain("example.com"));

    std::vector<std::string> domains;
    ASSERT(load_block_list(domains));
    ASSERT_EQ(domains.size(), (size_t)2);

    // Domains should be lowercased and sorted (stored in std::set)
    bool found_example = false, found_test = false;
    for (const auto& d : domains) {
        if (d == "example.com") found_example = true;
        if (d == "test.org") found_test = true;
    }
    ASSERT(found_example);
    ASSERT(found_test);

    set_config_path_override("");
}

TEST(remove_domain) {
    std::cout << "test: remove_domain\n";
    TempDir tmp;
    set_config_path_override(tmp.file("blocks.txt"));

    add_block_domain("example.com");
    add_block_domain("test.org");
    ASSERT(remove_block_domain("example.com"));

    std::vector<std::string> domains;
    load_block_list(domains);
    ASSERT_EQ(domains.size(), (size_t)1);
    ASSERT_EQ(domains[0], std::string("test.org"));

    set_config_path_override("");
}

TEST(domain_case_insensitive) {
    std::cout << "test: domain_case_insensitive\n";
    TempDir tmp;
    set_config_path_override(tmp.file("blocks.txt"));

    ASSERT(add_block_domain("Example.COM"));

    std::vector<std::string> domains;
    load_block_list(domains);
    ASSERT_EQ(domains.size(), (size_t)1);
    ASSERT_EQ(domains[0], std::string("example.com"));

    set_config_path_override("");
}

TEST(invalid_domains_rejected) {
    std::cout << "test: invalid_domains_rejected\n";
    TempDir tmp;
    set_config_path_override(tmp.file("blocks.txt"));

    ASSERT(!add_block_domain(""));
    ASSERT(!add_block_domain(".example.com"));
    ASSERT(!add_block_domain("example.com."));
    ASSERT(!add_block_domain("-example.com"));
    ASSERT(!add_block_domain("exam ple.com"));

    std::vector<std::string> domains;
    load_block_list(domains);
    ASSERT_EQ(domains.size(), (size_t)0);

    set_config_path_override("");
}

// ---- quotes config tests ----

TEST(quotes_length_default) {
    std::cout << "test: quotes_length_default\n";
    TempDir tmp;
    set_config_path_override(tmp.file("blocks.txt"));

    std::string length;
    ASSERT(read_quotes_length(length));
    ASSERT_EQ(length, std::string("medium"));

    set_config_path_override("");
}

TEST(quotes_length_write_read) {
    std::cout << "test: quotes_length_write_read\n";
    TempDir tmp;
    set_config_path_override(tmp.file("blocks.txt"));

    ASSERT(write_quotes_length("huge"));
    std::string length;
    ASSERT(read_quotes_length(length));
    ASSERT_EQ(length, std::string("huge"));

    set_config_path_override("");
}

// ---- browser list tests ----

TEST(browser_add_remove) {
    std::cout << "test: browser_add_remove\n";
    TempDir tmp;
    set_config_path_override(tmp.file("blocks.txt"));

    ASSERT(add_browser_name("Chrome"));
    ASSERT(add_browser_name("Firefox"));
    ASSERT(add_browser_name("Chrome")); // duplicate

    std::vector<std::string> browsers;
    ASSERT(load_browser_list(browsers));
    ASSERT_EQ(browsers.size(), (size_t)2);

    ASSERT(remove_browser_name("Chrome"));
    load_browser_list(browsers);
    ASSERT_EQ(browsers.size(), (size_t)1);
    ASSERT_EQ(browsers[0], std::string("Firefox"));

    set_config_path_override("");
}

// ---- app list tests ----

TEST(app_add_remove) {
    std::cout << "test: app_add_remove\n";
    TempDir tmp;
    set_config_path_override(tmp.file("blocks.txt"));

    std::string entry = "Slack|bundle=com.tinyspeck.slackmacgap|path=/Applications/Slack.app";
    ASSERT(add_block_app(entry));

    std::vector<std::string> apps;
    ASSERT(load_app_list(apps));
    ASSERT_EQ(apps.size(), (size_t)1);
    ASSERT_EQ(apps[0], entry);

    ASSERT(remove_block_app(entry));
    load_app_list(apps);
    ASSERT_EQ(apps.size(), (size_t)0);

    set_config_path_override("");
}

TEST(empty_lists_on_fresh_config) {
    std::cout << "test: empty_lists_on_fresh_config\n";
    TempDir tmp;
    set_config_path_override(tmp.file("blocks.txt"));

    std::vector<std::string> domains, apps, browsers;
    ASSERT(load_block_list(domains));
    ASSERT_EQ(domains.size(), (size_t)0);
    ASSERT(load_app_list(apps));
    ASSERT_EQ(apps.size(), (size_t)0);
    ASSERT(load_browser_list(browsers));
    ASSERT_EQ(browsers.size(), (size_t)0);

    set_config_path_override("");
}

int main() {
    std::cout << "\n=== bliss C++ unit tests ===\n\n";
    // Tests already ran via static registration
    std::cout << "\n" << tests_passed << "/" << tests_run << " assertions passed\n";
    if (tests_passed == tests_run) {
        std::cout << "ALL TESTS PASSED\n";
        return 0;
    }
    std::cout << "SOME TESTS FAILED\n";
    return 1;
}
