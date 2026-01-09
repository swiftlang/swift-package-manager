SRC_FILES := $(wildcard *.c)

# Define architectures and platforms
ARCHS := x86_64 arm64
PLATFORMS := macos linux

# Define output directories
BUILD_DIR := build
DIST_DIR := dist

# Platform-specific settings
MACOS_SDK := $(shell xcrun --sdk macosx --show-sdk-path 2>/dev/null || echo "")
MACOS_MIN_VERSION := 10.15

# Compiler flags
COMMON_FLAGS := -O2

# Platform and architecture specific flags
MACOS_X86_64_FLAGS := -target x86_64-apple-macos$(MACOS_MIN_VERSION) -isysroot $(MACOS_SDK)
MACOS_ARM64_FLAGS := -target arm64-apple-macos$(MACOS_MIN_VERSION) -isysroot $(MACOS_SDK)
LINUX_X86_64_FLAGS := -target x86_64-unknown-linux-gnu
LINUX_ARM64_FLAGS := -target aarch64-unknown-linux-gnu

.PHONY: all clean macos linux universal

all: macos linux

# Create necessary directories
$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)/macos/x86_64
	mkdir -p $(BUILD_DIR)/macos/arm64
	mkdir -p $(BUILD_DIR)/linux/x86_64
	mkdir -p $(BUILD_DIR)/linux/arm64

$(DIST_DIR):
	mkdir -p $(DIST_DIR)/macos
	mkdir -p $(DIST_DIR)/linux

# macOS x86_64 build
$(BUILD_DIR)/macos/x86_64/%.o: %.c | $(BUILD_DIR)
	clang $(COMMON_FLAGS) $(MACOS_X86_64_FLAGS) -c -o $@ $<

# macOS arm64 build
$(BUILD_DIR)/macos/arm64/%.o: %.c | $(BUILD_DIR)
	clang $(COMMON_FLAGS) $(MACOS_ARM64_FLAGS) -c -o $@ $<

# Linux x86_64 build
$(BUILD_DIR)/linux/x86_64/%.o: %.c | $(BUILD_DIR)
	clang $(COMMON_FLAGS) $(LINUX_X86_64_FLAGS) -c -o $@ $<

# Linux arm64 build
$(BUILD_DIR)/linux/arm64/%.o: %.c | $(BUILD_DIR)
	clang $(COMMON_FLAGS) $(LINUX_ARM64_FLAGS) -c -o $@ $<

# Define object files for each platform and architecture
MACOS_X86_64_OBJ_FILES := $(patsubst %.c,$(BUILD_DIR)/macos/x86_64/%.o,$(SRC_FILES))
MACOS_ARM64_OBJ_FILES := $(patsubst %.c,$(BUILD_DIR)/macos/arm64/%.o,$(SRC_FILES))
LINUX_X86_64_OBJ_FILES := $(patsubst %.c,$(BUILD_DIR)/linux/x86_64/%.o,$(SRC_FILES))
LINUX_ARM64_OBJ_FILES := $(patsubst %.c,$(BUILD_DIR)/linux/arm64/%.o,$(SRC_FILES))

# Create individual architecture libraries
$(DIST_DIR)/macos/libSimple_x86_64.a: $(MACOS_X86_64_OBJ_FILES) | $(DIST_DIR)
	llvm-ar rc $@ $^

$(DIST_DIR)/macos/libSimple_arm64.a: $(MACOS_ARM64_OBJ_FILES) | $(DIST_DIR)
	llvm-ar rc $@ $^

$(DIST_DIR)/linux/libSimple_x86_64.a: $(LINUX_X86_64_OBJ_FILES) | $(DIST_DIR)
	llvm-ar rc $@ $^

$(DIST_DIR)/linux/libSimple_arm64.a: $(LINUX_ARM64_OBJ_FILES) | $(DIST_DIR)
	llvm-ar rc $@ $^

# Create universal binary for macOS
$(DIST_DIR)/macos/libSimple.a: $(DIST_DIR)/macos/libSimple_x86_64.a $(DIST_DIR)/macos/libSimple_arm64.a
	lipo -create -output $@ $^

# For Linux, we'll provide separate libraries since lipo is macOS-specific
linux: $(DIST_DIR)/linux/libSimple_x86_64.a $(DIST_DIR)/linux/libSimple_arm64.a
	@echo "Linux libraries built in $(DIST_DIR)/linux/"
	@echo "Note: For Linux, use the architecture-specific libraries as needed."

macos: $(DIST_DIR)/macos/libSimple.a
	@echo "macOS universal library built at $(DIST_DIR)/macos/libSimple.a"

clean:
	rm -rf $(BUILD_DIR) $(DIST_DIR)
