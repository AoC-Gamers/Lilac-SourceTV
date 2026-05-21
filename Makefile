ifeq ($(OS),Windows_NT)
PYTHON ?= python
SMX_PLATFORM ?= windows
SPCOMP ?= deps/sourcemod-windows/addons/sourcemod/scripting/spcomp.exe
else
PYTHON ?= $(shell command -v python3 >/dev/null 2>&1 && echo python3 || echo python)
SMX_PLATFORM ?= linux
SPCOMP ?= deps/sourcemod-linux/addons/sourcemod/scripting/spcomp
endif

SOURCEMOD_VERSION ?= 1.12
SMX_BUILD_DIR ?= .build/smx
SMX_PACKAGE_DIR ?= .build/package-smx
RELEASE_BASENAME ?= lilac-sourcetv-local

.PHONY: deps-smx build-smx package-smx release clean clean-all

deps-smx:
	$(PYTHON) ./scripts/fetch-sourcemod.py --root . --platform "$(SMX_PLATFORM)" --version "$(SOURCEMOD_VERSION)"

build-smx:
	$(PYTHON) ./scripts/build-local.py --root . --spcomp "$(SPCOMP)" --output-root "$(SMX_BUILD_DIR)" --compile-log deps/build-smx-compile.log

package-smx:
	$(PYTHON) ./scripts/stage-artifact.py . "$(SMX_BUILD_DIR)" "deps/build-smx-compile.log" "$(SMX_PACKAGE_DIR)"

release:
	$(PYTHON) ./scripts/stage-artifact.py . "$(SMX_PACKAGE_DIR)" "deps/build-smx-compile.log"
	$(PYTHON) ./scripts/package-release.py --root . --basename "$(RELEASE_BASENAME)"

clean:
	$(PYTHON) -c "import shutil, pathlib; [shutil.rmtree(p, ignore_errors=True) for p in map(pathlib.Path, ['.build', 'dist'])]"

clean-all:
	$(PYTHON) -c "import shutil, pathlib; [shutil.rmtree(p, ignore_errors=True) for p in map(pathlib.Path, ['.build', 'dist', 'deps'])]"
