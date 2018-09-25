.PHONY: all build-runtimes build x

SWIFT_BUILD := swift build
SWIFT_PACKAGE := swift package
BUILD_DIR := $(CURDIR)/.build

# FIXME: This is not really correct. We should query
# the swiftpm to find the exact path of the checkout
# as it depends on the state of the dependency.
# However, there is no way to do that right now.
SWIFTPM_CHECKOUT := $(BUILD_DIR)/checkouts/swift-package-manager*/

all: build

build-runtimes:
	@$(SWIFT_PACKAGE) resolve
	@$(SWIFTPM_CHECKOUT)/Utilities/bootstrap build-runtimes

build: build-runtimes
	@$(SWIFT_BUILD)

x:
	@$(SWIFT_PACKAGE) generate-xcodeproj --xcconfig-overrides config.xcconfig
