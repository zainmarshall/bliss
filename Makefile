.PHONY: all build build-gui install uninstall test setup

ROOT_DIR := $(CURDIR)
BUILD_DIR := $(ROOT_DIR)/build

# Full dev setup: build everything, install CLI + root helper, launch GUI
all: build setup build-gui
	@/usr/bin/open /Applications/Bliss.app
	@echo ""
	@echo "[bliss] ready — CLI and GUI are running"

# Build C++ CLI binaries
build:
	@cmake -S "$(ROOT_DIR)" -B "$(BUILD_DIR)" >/dev/null 2>&1
	@cmake --build "$(BUILD_DIR)"

# Build and launch GUI app bundle (includes menubar)
build-gui:
	@bash "$(ROOT_DIR)/scripts/run_gui.sh"

# Setup: symlink CLI, install root helper, copy app to /Applications
setup:
	@echo "[bliss] setting up (requires sudo)..."
	@sudo mkdir -p /usr/local/bin
	@sudo ln -sf "$(BUILD_DIR)/bliss" /usr/local/bin/bliss
	@sudo ln -sf "$(BUILD_DIR)/blissd" /usr/local/bin/blissd
	@sudo ln -sf "$(BUILD_DIR)/blissroot" /usr/local/bin/blissroot
	@sudo mkdir -p /usr/local/share/bliss/quotes /usr/local/share/bliss/problems
	@sudo cp -f "$(ROOT_DIR)/quotes/"*.txt /usr/local/share/bliss/quotes/ 2>/dev/null || true
	@sudo cp -f "$(ROOT_DIR)/problems/"*.json /usr/local/share/bliss/problems/ 2>/dev/null || true
	@if [ -f "$(ROOT_DIR)/root/com.bliss.root.plist" ]; then \
		sudo cp "$(ROOT_DIR)/root/com.bliss.root.plist" /Library/LaunchDaemons/com.bliss.root.plist; \
		sudo cp "$(ROOT_DIR)/root/com.bliss.root.plist" /usr/local/share/bliss/com.bliss.root.plist; \
		sudo /bin/launchctl bootout system/com.bliss.root 2>/dev/null || true; \
		sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/com.bliss.root.plist 2>/dev/null || true; \
		sudo /bin/launchctl kickstart -k system/com.bliss.root 2>/dev/null || true; \
		echo "[bliss] root helper installed"; \
	fi

# Full install (copies binaries, installs to /Applications, sets up launchd)
install:
	@bash "$(ROOT_DIR)/scripts/install.sh"

# Uninstall
uninstall:
	@bash "$(ROOT_DIR)/scripts/uninstall.sh"

# Run tests
test:
	@bash "$(ROOT_DIR)/scripts/run_tests.sh"
