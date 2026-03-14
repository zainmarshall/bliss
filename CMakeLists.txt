cmake_minimum_required(VERSION 3.16)
project(bliss)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(bliss
    src/main.cpp
    src/hosts_block.cpp
    src/firewall_block.cpp
)

add_executable(blissd
    src/blissd.cpp
    src/hosts_block.cpp
    src/firewall_block.cpp
)

add_executable(blissroot
    src/blissroot.cpp
    src/hosts_block.cpp
    src/firewall_block.cpp
)

# Tests
enable_testing()

add_executable(test_hosts_block
    tests/test_hosts_block.cpp
    src/hosts_block.cpp
    src/firewall_block.cpp
)

add_test(NAME hosts_block COMMAND test_hosts_block)
