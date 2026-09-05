# Makefile that builds libstd using the mrustc-built rustc
# 
#
# Inputs: mrustc-built rustc (`rustc_m`) and cargo
# - Step 1: Build libstd with `minicargo`
#  - This is just so cargo can be used to build things (as it needs a working std for build scripts)
#  > This is stored in `$(PREFIX_S)`
# - Step 2: Build libstd again (this time using `cargo`)
#  - Provides full dynamic and static versions of libstd (needed for rustc's use of dynamic linking)
#  > This is stored in `$(PREFIX_2)` (with the shared libraries stored in `prefix/lib`)
# - Step 3: Build a `rustc` using that libstd
#  - Done so there's an optimised rustc around (mrustc is bad at codegen)
# - Step 4: Build `libstd` with this `rustc`
#  - Needed to match ABIs

HOST_PARLEVEL_DEF := $(shell nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 1)
PARLEVEL ?= $(HOST_PARLEVEL_DEF)
RUSTC_VERSION_DEF := $(shell cat ../rust-version)

HOST_GNU_TYPE := $(shell $(CC) -dumpmachine 2>/dev/null || echo unknown)
LINUX_RUSTC_TARGET_DEF := $(shell t="$(HOST_GNU_TYPE)"; \
  if echo "$$t" | grep -Eq '^x86_64-.*-linux-musl$$'; then echo x86_64-unknown-linux-musl; \
  elif echo "$$t" | grep -Eq '^x86_64-.*-linux-gnu'; then echo x86_64-unknown-linux-gnu; \
  elif echo "$$t" | grep -Eq '^aarch64-.*-linux-musl$$'; then echo aarch64-unknown-linux-musl; \
  elif echo "$$t" | grep -Eq '^aarch64-.*-linux-gnu'; then echo aarch64-unknown-linux-gnu; \
  elif echo "$$t" | grep -Eq '^(arm|armv[0-9]+)-.*-linux-musl'; then echo arm-unknown-linux-musl; \
  elif echo "$$t" | grep -Eq '^(arm|armv[0-9]+)-.*-linux-gnu'; then echo arm-unknown-linux-gnu; \
  elif echo "$$t" | grep -Eq '^i[0-9]86-.*-linux-musl$$'; then echo i586-unknown-linux-musl; \
  elif echo "$$t" | grep -Eq '^i[0-9]86-.*-linux-gnu'; then echo i586-unknown-linux-gnu; \
  elif echo "$$t" | grep -Eq '^m68k-.*-linux-musl$$'; then echo m68k-unknown-linux-musl; \
  elif echo "$$t" | grep -Eq '^m68k-.*-linux-gnu'; then echo m68k-unknown-linux-gnu; \
  elif echo "$$t" | grep -Eq '^powerpc64le-.*-linux-musl$$'; then echo powerpc64le-unknown-linux-musl; \
  elif echo "$$t" | grep -Eq '^powerpc64le-.*-linux-gnu'; then echo powerpc64le-unknown-linux-gnu; \
  elif echo "$$t" | grep -Eq '^powerpc64-.*-linux-musl$$'; then echo powerpc64-unknown-linux-musl; \
  elif echo "$$t" | grep -Eq '^powerpc64-.*-linux-gnu'; then echo powerpc64-unknown-linux-gnu; \
  elif echo "$$t" | grep -Eq '^riscv64-.*-linux-musl$$'; then echo riscv64-unknown-linux-musl; \
  elif echo "$$t" | grep -Eq '^riscv64-.*-linux-gnu'; then echo riscv64-unknown-linux-gnu; \
  else echo x86_64-unknown-linux-gnu; fi)

ifeq ($(OS),Windows_NT)
  EXESUF ?= .exe
endif
EXESUF ?=

MINICARGO ?= ../bin/minicargo$(EXESUF)

RUSTC_VERSION ?= $(RUSTC_VERSION_DEF)
RUST_SRC ?= ../rustc-$(RUSTC_VERSION)-src/
ifeq ($(RUSTC_VERSION),$(RUSTC_VERSION_DEF))
  OUTDIR_SUF ?=
else
  OUTDIR_SUF ?= -$(RUSTC_VERSION)
endif
# Extension for dynamic libraries and platform for script overrides
ifeq ($(shell uname -s || echo not),Darwin)
  DYLIB_EXT := dylib
  PLATFORM := macos
  RUSTC_TARGET ?= x86_64-apple-darwin
else
  DYLIB_EXT := so
  PLATFORM := linux
  RUSTC_TARGET ?= $(LINUX_RUSTC_TARGET_DEF)
endif

TARGETVER_LEAST_1_29 := $(shell test "$(RUSTC_VERSION)" ">" "1.29" && echo yes)
TARGETVER_LEAST_1_39 := $(shell test "$(RUSTC_VERSION)" ">" "1.39" && echo yes)
TARGETVER_LEAST_1_54 := $(shell test "$(RUSTC_VERSION)" ">" "1.54" && echo yes)
TARGETVER_LEAST_1_74 := $(shell test "$(RUSTC_VERSION)" ">" "1.74" && echo yes)

RUSTC_BINNAME := rustc_binary
CARGO_FLAGS_rustc := 
ifneq ($(TARGETVER_LEAST_1_54),)
 RUST_SRC_LIBS := $(RUST_SRC)library/
 RUST_SRC_RUSTC := $(RUST_SRC)compiler/rustc/
 RUST_SRC_CODEGEN := $(RUST_SRC)compiler/rustc_codegen_llvm/
 RUST_SRC_CARGO := $(RUST_SRC)src/tools/cargo/
 VENDOR_DIR := $(RUST_SRC)vendor
 RUSTC_BINNAME := rustc-main
 CARGO_FLAGS_rustc += --features llvm
else ifneq ($(TARGETVER_LEAST_1_39),)
 RUST_SRC_LIBS := $(RUST_SRC)src/lib
 RUST_SRC_RUSTC := $(RUST_SRC)src/rustc/
 RUST_SRC_CODEGEN := $(RUST_SRC)src/librustc_codegen_llvm/
 RUST_SRC_CARGO := $(RUST_SRC)src/tools/cargo/
 VENDOR_DIR := $(RUST_SRC)vendor
else
 RUST_SRC_LIBS := $(RUST_SRC)src/lib
 RUST_SRC_RUSTC := $(RUST_SRC)src/rustc/
 RUST_SRC_CARGO := $(RUST_SRC)src/tools/cargo/
 # librustc_codegen_llvm
 VENDOR_DIR := $(RUST_SRC)src/vendor
endif
RUST_SRC_HELLO := ../samples/hello.rs

RUSTC_ARCH := $(firstword $(subst -, ,$(RUSTC_TARGET)))
HELLO_RUSTFLAGS :=
ifneq ($(filter %-linux-musl,$(RUSTC_TARGET)),)
HELLO_RUSTFLAGS += -C target-feature=-crt-static
endif

OUTDIR := output$(OUTDIR_SUF)/
ifeq ($(filter %-linux-musl,$(RUSTC_TARGET)),)
MINICARGO_SYSROOT_FEATURES :=
SYSROOT_CARGO_FEATURES := panic-unwind
LLVM_CXX_RUNTIME_ENV :=
else
MINICARGO_SYSROOT_FEATURES := --features system-llvm-libunwind
SYSROOT_CARGO_FEATURES := panic-unwind,system-llvm-libunwind
LLVM_CXX_RUNTIME_ENV := LLVM_USE_LIBCXX=1
endif
comma := ,
SYSROOT_BUILD_TAG := $(subst $(comma),_,$(SYSROOT_CARGO_FEATURES))
RUN_RUSTC_BUILD_REV := 2
MUSL_LIBCXX_TARGET_INCLUDE := /usr/include/$(HOST_GNU_TYPE)/c++/v1
# Stage 1: standard library built with `rustc_m` (using minicargo)
PREFIX_S := $(OUTDIR)prefix-s/
LIBDIR_S := $(PREFIX_S)lib/rustlib/$(RUSTC_TARGET)/lib/
BINDIR_S := $(PREFIX_S)bin/
# Stage 2: standard library built with `rustc_m` (using cargo)
PREFIX_2 := $(OUTDIR)prefix-2/
LIBDIR_2 := $(PREFIX_2)lib/rustlib/$(RUSTC_TARGET)/lib/
BINDIR_2 := $(PREFIX_2)bin/
# Stage X: clean rustc and stage 2 libstd
PREFIX := $(OUTDIR)prefix/
BINDIR := $(PREFIX)bin/
LIBDIR := $(PREFIX)lib/rustlib/$(RUSTC_TARGET)/lib/
CARGO_HOME := $(PREFIX)cargo_home/

LLVM_CONFIG ?= $(RUST_SRC)build/bin/llvm-config
LLVM_TARGETS ?= X86;ARM;AArch64#;Mips;PowerPC;SystemZ;JSBackend;MSP430;Sparc;NVPTX

RUSTC_ENV_VARS := CFG_COMPILER_HOST_TRIPLE=$(RUSTC_TARGET)
RUSTC_ENV_VARS += LLVM_CONFIG=$(abspath $(LLVM_CONFIG))
RUSTC_ENV_VARS += CFG_RELEASE=$(RUSTC_VERSION)	# Claiming stable
RUSTC_ENV_VARS += CFG_RELEASE_CHANNEL=$(RUSTC_CHANNEL)
RUSTC_ENV_VARS += CFG_VERSION=$(RUSTC_VERSION)-stable-mrustc
RUSTC_ENV_VARS += CFG_PREFIX=mrustc
RUSTC_ENV_VARS += CFG_LIBDIR_RELATIVE=lib
RUSTC_ENV_VARS += LD_LIBRARY_PATH=$(abspath $(LIBDIR))
RUSTC_ENV_VARS += REAL_LIBRARY_PATH_VAR=LD_LIBRARY_PATH
RUSTC_ENV_VARS += RUSTC_INSTALL_BINDIR=bin
RUSTC_ENV_VARS += RUSTC_ERROR_METADATA_DST=$(abspath $(PREFIX))

CARGO_FLAGS := --target $(RUSTC_TARGET) -j $(PARLEVEL) --release --verbose

CARGO_ENV := CFG_COMPILER_HOST_TRIPLE=$(RUSTC_TARGET)
CARGO_ENV += RUSTC_BOOTSTRAP=1
CARGO_ENV += CARGO_HOME=$(CARGO_HOME)
CARGO_ENV += $(LLVM_CXX_RUNTIME_ENV)
CARGO_ENV += RUSTFLAGS="-Z force-unstable-if-unmarked -C link_args=-Wl,-rpath,\$$ORIGIN/../lib -C target-feature=-crt-static"
ifneq ($(filter %-linux-musl,$(RUSTC_TARGET)),)
ifneq ($(wildcard $(MUSL_LIBCXX_TARGET_INCLUDE)/__config_site),)
CARGO_ENV += CPLUS_INCLUDE_PATH=$(MUSL_LIBCXX_TARGET_INCLUDE)
endif
endif

fn_opt_copy = (test -e "$2" && test ! "$1" -nt "$2") || cp "$1" "$2"

V ?= @


all: $(BINDIR_S)hello_world
all: $(BINDIR)hello_world	# Implies $(LIBDIR)libstd.rlib
all: $(BINDIR)rustc
all: $(BINDIR)cargo

clean:
	rm -rf -- output$(OUTDIR_SUF)/*

# Helper rules to ensure that mrustc has built rustc and cargo
../output$(OUTDIR_SUF)/rustc:
	$(MAKE) -C ../ -f minicargo.mk output$(OUTDIR_SUF)/rustc
../output$(OUTDIR_SUF)/cargo:
	$(MAKE) -C ../ -f minicargo.mk output$(OUTDIR_SUF)/cargo
# The top-level rustc build also builds minicargo. Order this target after it
# so parallel make cannot observe or rebuild a half-published binary.
../bin/minicargo$(EXESUF): | ../output$(OUTDIR_SUF)/rustc
	$(MAKE) -C ../ -f minicargo.mk bin/minicargo$(EXESUF)
	test -e $@
$(RUST_SRC_HELLO):
	$(MAKE) -C ../ RUSTCSRC

# Stage 0 setup
$(BINDIR)rustc_m: ../output$(OUTDIR_SUF)/rustc
	@mkdir -p $(dir $@)
	cp $< $@
$(BINDIR_S)rustc: ../output$(OUTDIR_SUF)/rustc
	@mkdir -p $(dir $@)
	cp $< $@
$(BINDIR_S)cargo: ../output$(OUTDIR_SUF)/cargo
	@mkdir -p $(dir $@)
	cp $< $@

$(CARGO_HOME)config: Makefile
	@mkdir -p $(dir $@)
	@echo "[create] $@"
	$Vecho "[source.crates-io]" > $@
	$Vecho "replace-with = \"vendored-sources\"" >> $@
	$Vecho "[source.vendored-sources]" >> $@
	$Vecho "directory = \"$(abspath $(VENDOR_DIR))\"" >> $@

# -------------------------------------
# Stage 1: Build standard library (using minicargo with rustc)
# - Can't use `cargo` because there isn't a rustc-compatible std yet
# - _could_ use it if mrustc accepted all the arguments rustc does (via the proxy)
# -------------------------------------
$(LIBDIR_S)libstd.rlib: $(BINDIR_S)rustc $(MINICARGO) Makefile
	@echo "[MINICARGO] $(RUST_SRC_LIBS)std > $(LIBDIR_S)"
	mkdir -p $(LIBDIR_S)
ifneq ($(TARGETVER_LEAST_1_74),)
	$V+STD_ENV_ARCH=$(RUSTC_ARCH) MRUSTC_PATH=$(abspath $(BINDIR_S)rustc) $(MINICARGO) --vendor-dir $(VENDOR_DIR) --script-overrides ../script-overrides/stable-$(RUSTC_VERSION)-$(PLATFORM)/ --output-dir $(LIBDIR_S) $(MINICARGO_SYSROOT_FEATURES) $(RUST_SRC_LIBS)sysroot
else
	$V+MRUSTC_PATH=$(abspath $(BINDIR_S)rustc) $(MINICARGO) --vendor-dir $(VENDOR_DIR) --script-overrides ../script-overrides/stable-$(RUSTC_VERSION)-$(PLATFORM)/ --output-dir $(LIBDIR_S) $(RUST_SRC_LIBS)std
	$V+MRUSTC_PATH=$(abspath $(BINDIR_S)rustc) $(MINICARGO) --vendor-dir $(VENDOR_DIR) --script-overrides ../script-overrides/stable-$(RUSTC_VERSION)-$(PLATFORM)/ --output-dir $(LIBDIR_S) $(RUST_SRC_LIBS)panic_unwind
	$V+MRUSTC_PATH=$(abspath $(BINDIR_S)rustc) $(MINICARGO) --vendor-dir $(VENDOR_DIR) --script-overrides ../script-overrides/stable-$(RUSTC_VERSION)-$(PLATFORM)/ --output-dir $(LIBDIR_S) $(RUST_SRC_LIBS)test
endif

# Build hello_world using the bootstrapping compiler (mrustc-built rustc)
$(BINDIR_S)hello_world: $(RUST_SRC_HELLO) $(LIBDIR_S)libstd.rlib $(BINDIR_S)rustc
	@mkdir -p $(dir $@)
	$V$(BINDIR_S)rustc $(HELLO_RUSTFLAGS) $(RUSTFLAGS_$@) -L $(LIBDIR_S) $< -o $@

# ---
# Stage 2: Build a proper libstd (which includes dynamc libraries too)
# ---
STAGE2_STD_TARGET_DIR := $(OUTDIR)build-std2-$(SYSROOT_BUILD_TAG)-r$(RUN_RUSTC_BUILD_REV)
CARGO_OUTDIR_STAGE2_STD := $(STAGE2_STD_TARGET_DIR)/$(RUSTC_TARGET)/release/
CARGO_ENV_STAGE2_STD := CARGO_TARGET_DIR=$(STAGE2_STD_TARGET_DIR) RUSTC=$(abspath rustc_proxy.sh) PROXY_RUSTC=$(abspath $(BINDIR_2)rustc) PROXY_MRUSTC=$(abspath $(BINDIR_S)rustc) $(CARGO_ENV)
$(LIBDIR_2)libtest.rlib: $(LIBDIR_S)libstd.rlib $(BINDIR_2)rustc $(BINDIR_S)rustc $(BINDIR_S)cargo $(CARGO_HOME)config Makefile
	@mkdir -p $(LIBDIR_2)
	@echo [CARGO] $(RUST_SRC_LIBS)test/Cargo.toml '>' $(STAGE2_STD_TARGET_DIR)
ifneq ($(TARGETVER_LEAST_1_74),)
	$V$(CARGO_ENV_STAGE2_STD) $(BINDIR_S)cargo build $(CARGO_FLAGS) --manifest-path $(RUST_SRC_LIBS)sysroot/Cargo.toml --features $(SYSROOT_CARGO_FEATURES)
else ifeq ($(TARGETVER_LEAST_1_39),)
	$V$(CARGO_ENV_STAGE2_STD) $(BINDIR_S)cargo build $(CARGO_FLAGS) --manifest-path $(RUST_SRC_LIBS)std/Cargo.toml --features panic-unwind
	$Vcp --remove-destination $(CARGO_OUTDIR_STAGE2_STD)deps/*.rlib $(CARGO_OUTDIR_STAGE2_STD)deps/*.$(DYLIB_EXT) $(LIBDIR_2)
	$V$(CARGO_ENV_STAGE2_STD) $(BINDIR_S)cargo build $(CARGO_FLAGS) --manifest-path $(RUST_SRC_LIBS)test/Cargo.toml
else
	$V$(CARGO_ENV_STAGE2_STD) $(BINDIR_S)cargo build $(CARGO_FLAGS) --manifest-path $(RUST_SRC_LIBS)test/Cargo.toml --features panic-unwind
endif
	$Vcp $(CARGO_OUTDIR_STAGE2_STD)deps/*.rlib $(CARGO_OUTDIR_STAGE2_STD)deps/*.rmeta $(CARGO_OUTDIR_STAGE2_STD)deps/*.$(DYLIB_EXT) $(LIBDIR_2)

$(BINDIR_2)rustc: ../output$(OUTDIR_SUF)/rustc
	@mkdir -p $(dir $@)
	cp $< $@

# ---
# Stage 3: Build rustc using the above (full) std for building other libs
# ---

RUSTC_STAGE_TARGET_DIR := $(OUTDIR)build-rustc-$(SYSROOT_BUILD_TAG)-r$(RUN_RUSTC_BUILD_REV)
CARGO_OUTDIR_RUSTC := $(RUSTC_STAGE_TARGET_DIR)/$(RUSTC_TARGET)/release/
CARGO_ENV_RUSTC := CARGO_TARGET_DIR=$(RUSTC_STAGE_TARGET_DIR) RUSTC=$(abspath rustc_proxy.sh) PROXY_RUSTC=$(abspath $(BINDIR_2)rustc) PROXY_MRUSTC=$(abspath $(BINDIR_S)rustc) $(CARGO_ENV)
# - Build rustc with itself (so we have a rustc with the right ABI)
$(BINDIR)rustc: $(BINDIR_2)rustc $(BINDIR_S)cargo $(CARGO_HOME)config $(LIBDIR_2)libtest.rlib Makefile
	@mkdir -p $(PREFIX)tmp
	@echo [CARGO] $(RUST_SRC_RUSTC)Cargo.toml '>' $(RUSTC_STAGE_TARGET_DIR)/
	$V$(RUSTC_ENV_VARS) TMPDIR=$(abspath $(PREFIX)tmp) $(CARGO_ENV_RUSTC) $(BINDIR_S)cargo build $(CARGO_FLAGS) --manifest-path $(RUST_SRC_RUSTC)Cargo.toml $(CARGO_FLAGS_rustc)
ifeq ($(RUSTC_VERSION),1.39.0)
	@echo [CARGO] $(RUST_SRC_CODEGEN)Cargo.toml '>' $(RUSTC_STAGE_TARGET_DIR)/
	$V$(RUSTC_ENV_VARS) TMPDIR=$(abspath $(PREFIX)tmp) $(CARGO_ENV_RUSTC) $(BINDIR_S)cargo rustc $(CARGO_FLAGS) --manifest-path $(RUST_SRC_CODEGEN)Cargo.toml -- -L $(abspath $(CARGO_OUTDIR_RUSTC)deps)
	@mkdir -p $(LIBDIR)../codegen-backends
	@echo "[CP] libraries and results ($@)"
	$V$(call fn_opt_copy,$(CARGO_OUTDIR_RUSTC)librustc_codegen_llvm.$(DYLIB_EXT),$(LIBDIR)../codegen-backends/librustc_codegen_llvm-llvm.$(DYLIB_EXT))
else
	@echo "[CP] libraries and results ($@)"
endif
	@mkdir -p $(LIBDIR)
	$Vcp $(LIBDIR_2)*.$(DYLIB_EXT) $(PREFIX)lib
	$Vcp $(CARGO_OUTDIR_RUSTC)deps/*.rlib $(LIBDIR)
	$Vcp $(CARGO_OUTDIR_RUSTC)deps/*.$(DYLIB_EXT) $(LIBDIR)
	@mkdir -p $(BINDIR)
ifeq ($(RUSTC_VERSION),1.19.0)
	$Vcp $(CARGO_OUTDIR_RUSTC)rustc $(BINDIR)rustc_binary
else
	$V$(call fn_opt_copy,$(CARGO_OUTDIR_RUSTC)$(RUSTC_BINNAME),$(BINDIR)rustc_binary)
endif
	$V{ \
		echo '#!/bin/sh'; \
		echo 'set -eu'; \
		echo 'd=$$(dirname "$$0")'; \
		echo 'TARGET_TRIPLE="$(RUSTC_TARGET)"'; \
		echo 'is_target() {'; \
		echo '    for a in "$$@"'; \
		echo '    do'; \
		echo '        case "$$a" in'; \
		echo '        --target|--target*|-vV)'; \
		echo '            return 0'; \
		echo '            ;;'; \
		echo '        esac'; \
		echo '    done'; \
		echo '    return 1'; \
		echo '}'; \
		echo 'has_target_feature_flag() {'; \
		echo '    prev_was_c=0'; \
		echo '    for a in "$$@"'; \
		echo '    do'; \
		echo '        if [ "$$prev_was_c" = 1 ]; then'; \
		echo '            case "$$a" in'; \
		echo '            target-feature=*)'; \
		echo '                return 0'; \
		echo '                ;;'; \
		echo '            esac'; \
		echo '            prev_was_c=0'; \
		echo '        fi'; \
		echo '        case "$$a" in'; \
		echo '        -C)'; \
		echo '            prev_was_c=1'; \
		echo '            ;;'; \
		echo '        -Ctarget-feature=*)'; \
		echo '            return 0'; \
		echo '            ;;'; \
		echo '        esac'; \
		echo '    done'; \
		echo '    return 1'; \
		echo '}'; \
		echo 'case "$$TARGET_TRIPLE" in'; \
		echo '    *-linux-musl)'; \
		echo '        if ! is_target "$$@" && ! has_target_feature_flag "$$@"; then'; \
		echo '            LD_LIBRARY_PATH="$(abspath $(OUTDIR)prefix/lib):$(abspath $(LIBDIR))" exec "$$d/rustc_binary" -C target-feature=-crt-static "$$@"'; \
		echo '        fi'; \
		echo '        ;;'; \
		echo 'esac'; \
		echo 'LD_LIBRARY_PATH="$(abspath $(OUTDIR)prefix/lib):$(abspath $(LIBDIR))" exec "$$d/rustc_binary" "$$@"'; \
	} >$@
	$Vchmod +x $@

#
#
#
$(BINDIR)cargo: $(BINDIR)rustc
	@echo [CARGO] $(RUST_SRC_RUSTC)Cargo.toml '>' $(RUSTC_STAGE_TARGET_DIR)/
	$VTMPDIR=$(abspath $(PREFIX)tmp) $(CARGO_ENV_RUSTC) $(BINDIR_S)cargo build $(CARGO_FLAGS) --manifest-path $(RUST_SRC_CARGO)Cargo.toml
	$Vcp $(CARGO_OUTDIR_RUSTC)cargo $(BINDIR)cargo


#
#
#
STAGE3_STD_TARGET_DIR := $(OUTDIR)build-std-$(SYSROOT_BUILD_TAG)-r$(RUN_RUSTC_BUILD_REV)
CARGO_OUTDIR_STAGE3_STD := $(STAGE3_STD_TARGET_DIR)/$(RUSTC_TARGET)/release/
CARGO_ENV_STAGE3_STD := CARGO_TARGET_DIR=$(STAGE3_STD_TARGET_DIR) RUSTC=$(abspath rustc_proxy.sh) PROXY_RUSTC=$(abspath $(BINDIR)rustc) PROXY_MRUSTC=$(abspath $(BINDIR_2)rustc) $(CARGO_ENV)
$(LIBDIR)libstd.rlib: $(BINDIR)rustc
	@mkdir -p $(LIBDIR)
	@echo [CARGO] $(RUST_SRC_LIBS)test/Cargo.toml '>' $(STAGE3_STD_TARGET_DIR)
ifneq ($(TARGETVER_LEAST_1_74),)
	$V$(CARGO_ENV_STAGE3_STD) $(BINDIR_S)cargo build $(CARGO_FLAGS) --manifest-path $(RUST_SRC_LIBS)sysroot/Cargo.toml --features $(SYSROOT_CARGO_FEATURES)
else ifeq ($(TARGETVER_LEAST_1_39),)
	$V$(CARGO_ENV_STAGE3_STD) $(BINDIR_S)cargo build $(CARGO_FLAGS) --manifest-path $(RUST_SRC_LIBS)std/Cargo.toml --features panic-unwind
	$Vcp --remove-destination $(CARGO_OUTDIR_STAGE3_STD)deps/*.rlib $(CARGO_OUTDIR_STAGE3_STD)deps/*.$(DYLIB_EXT) $(LIBDIR)
	$V$(CARGO_ENV_STAGE3_STD) $(BINDIR_S)cargo build $(CARGO_FLAGS) --manifest-path $(RUST_SRC_LIBS)test/Cargo.toml
else
	$V$(CARGO_ENV_STAGE3_STD) $(BINDIR_S)cargo build $(CARGO_FLAGS) --manifest-path $(RUST_SRC_LIBS)test/Cargo.toml --features panic-unwind
endif
	$Vcp $(CARGO_OUTDIR_STAGE3_STD)deps/*.rlib $(CARGO_OUTDIR_STAGE3_STD)deps/*.$(DYLIB_EXT) $(LIBDIR)

# Build hello_world using the final fully-bootstrapped compiler
$(BINDIR)hello_world: $(RUST_SRC_HELLO) $(BINDIR)rustc $(LIBDIR)libstd.rlib
	@mkdir -p $(dir $@)
	@echo "[RUSTC] -o $@"
	$V$(DBG) $(BINDIR)rustc $(HELLO_RUSTFLAGS) -L $(LIBDIR) $< -o $@
	./$@

#.PHONY: TEST_BOOTSTRAP
#all:  TEST_BOOTSTRAP
#TEST_BOOTSTRAP: $(BINDIR)rustc $(LIBDIR)libstd.rlib
#	@echo [CARGO] $(RUST_SRC)src/bootstrap/Cargo.toml '>' $(OUTDIR)build-rustc2/
#	$V$(RUSTC_ENV_VARS) TMPDIR=$(abspath $(PREFIX)tmp) CARGO_TARGET_DIR=$(OUTDIR)build-bootstrap RUSTC=$(BINDIR)rustc $(CARGO_ENV) $(BINDIR)cargo build --manifest-path $(RUST_SRC)bootstrap/Cargo.toml --release -j $(PARLEVEL) --frozen --verbose
