.PHONY: all build build-gui build-menubar install install-gui install-menubar

ROOT_DIR := $(CURDIR)

all: build build-gui build-menubar

build:
	cmake -S "$(ROOT_DIR)" -B "$(ROOT_DIR)/build"
	cmake --build "$(ROOT_DIR)/build"

build-gui:
	bash "$(ROOT_DIR)/scripts/run_gui.sh"

build-menubar:
	bash "$(ROOT_DIR)/scripts/install_menubar.sh"

install:
	bash "$(ROOT_DIR)/scripts/install.sh"

install-gui:
	bash "$(ROOT_DIR)/scripts/install.sh"

install-menubar:
	bash "$(ROOT_DIR)/scripts/install_menubar.sh"
