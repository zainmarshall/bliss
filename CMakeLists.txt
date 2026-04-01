cmake_minimum_required(VERSION 3.16)
project(bliss)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Platform-specific firewall implementation.
if(APPLE)
    set(FIREWALL_SRC src/firewall_block.cpp)
elseif(UNIX)
    set(FIREWALL_SRC src/firewall_linux.cpp)
endif()

add_executable(bliss
    src/main.cpp
    src/hosts_block.cpp
    ${FIREWALL_SRC}
)

add_executable(blissd
    src/blissd.cpp
    src/hosts_block.cpp
    ${FIREWALL_SRC}
)

add_executable(blissroot
    src/blissroot.cpp
    src/hosts_block.cpp
    ${FIREWALL_SRC}
)

# Tests
enable_testing()

add_executable(test_hosts_block
    tests/test_hosts_block.cpp
    src/hosts_block.cpp
    ${FIREWALL_SRC}
)

add_test(NAME hosts_block COMMAND test_hosts_block)
