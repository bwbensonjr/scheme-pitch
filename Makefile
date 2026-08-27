# Pinned laesare vendoring. See vendor/laesare/VENDOR.md.
LAESARE_TAG   := v1.0.3
LAESARE_REPO  := ../laesare
VENDOR_FILES  := reader.sls writer.sls LICENSE.txt

CHEZ    ?= chez
RACKET  ?= racket
EMIT    ?= emit
EMIT_MANIFEST ?=
PITCH_ARGS ?=
LIBDIRS := src:.

ORACLE_OUT := $(shell mktemp -t pitch-layout)
ORACLE_REF := $(shell mktemp -t pitch-layout-ref)

PREFIX ?= /usr/local
PITCH_LIBEXECDIR ?= $(PREFIX)/libexec/pitch

READER_SOURCE    := src/pitch/reader.sls
READER_GENERATED := src/pitch/reader.sld
READER_GENERATOR := tools/generate-reader.sps
PITCH_PROGRAM     := src/pitch/main.scm
PITCH_MANIFEST    := emit-libs.scm
PITCH_R7RS_SOURCES := $(wildcard src/pitch/*.sld) $(PITCH_PROGRAM) $(PITCH_MANIFEST)
PITCH_FORMAT_SOURCES := $(filter-out src/pitch/reader.sld,$(wildcard src/pitch/*.sld)) \
                        $(PITCH_PROGRAM)

EMIT_TEST_PROGRAMS := test-sequence test-table test-error \
                      test-generated-number test-number-syntax-r7rs \
                      test-recording-r7rs test-lines test-cost \
                      test-style-r7rs test-diagnostic-r7rs test-doc-r7rs \
                      test-cst-r7rs test-datum-check-r7rs test-datum-r7rs \
                      test-check-r7rs test-layout-r7rs test-config-r7rs \
                      test-print-r7rs test-format-r7rs test-cli-r7rs \
                      test-text-files-r7rs
EMIT_EXECUTABLE_TESTS := $(filter-out test-text-files-r7rs,$(EMIT_TEST_PROGRAMS))

.PHONY: help test pitch-run pitch-build self-format self-check real-host-test door-parity no-chez-smoke install-test emit-preflight emit-tests-build emit-tests-run emit-text-files-test audit-r7rs audit-invariants reader-generate reader-check \
        oracle-datum oracle-layout vendor-diff vendor-verify install uninstall format format-check

help:
	@echo "test           run the complete Emit application verification matrix"
	@echo "pitch-run      run Pitch through Emit; pass arguments with PITCH_ARGS='...'"
	@echo "pitch-build    build the standalone Emit executable"
	@echo "self-format    format maintained Pitch R7RS sources with Emit Pitch"
	@echo "self-check     check maintained Pitch R7RS sources with Emit Pitch"
	@echo "real-host-test exercise the standalone command against real filesystem effects"
	@echo "door-parity    compare development and AOT CLI behavior and effects"
	@echo "no-chez-smoke  build and format stdin with Chez absent from PATH"
	@echo "install-test   verify relocatable install and scoped uninstall"
	@echo "emit-preflight verify the Emit capabilities required by the port"
	@echo "emit-tests-build compile every Pitch R7RS test program with Emit"
	@echo "emit-tests-run run every Pitch R7RS test program as an AOT executable"
	@echo "emit-text-files-test verify Emit UTF-8 and line endings through real files"
	@echo "audit-r7rs     reject legacy R6RS surfaces in maintained .sld files"
	@echo "audit-invariants reject forbidden behavior below Pitch's host edges"
	@echo "reader-generate regenerate the Emit reader from authoritative reader.sls"
	@echo "reader-check   fail if the generated Emit reader has drifted"
	@echo "oracle-datum  compare Pitch projection with Chez's external reader"
	@echo "format         format pitch's own sources in place"
	@echo "format-check   check those sources; non-zero if any would change"
	@echo "install        install pitch under PREFIX (default $(PREFIX))"
	@echo "uninstall      remove an installed pitch from PREFIX"
	@echo "oracle-layout  diff the layout engine against Racket's pretty-expressive"
	@echo "vendor-diff    show pitch's changes to laesare's reader"
	@echo "vendor-verify  check vendor/laesare/ still matches $(LAESARE_TAG)"

# Every Emit compilation target depends on this gate. Keeping the probe in one
# script also lets CI exercise missing and older compiler diagnostics directly.
emit-preflight:
	@EMIT='$(EMIT)' EMIT_MANIFEST='$(EMIT_MANIFEST)' \
	  sh tools/check-emit-prerequisites.sh

emit-tests-build: emit-preflight
	@set -e; \
	for program in $(EMIT_TEST_PROGRAMS); do \
	  $(EMIT) build "$$program"; \
	done

emit-tests-run: emit-tests-build
	@set -e; \
	for program in $(EMIT_EXECUTABLE_TESTS); do \
	  "build/$$program"; \
	done
	@sh tests/test-text-files.sh

emit-text-files-test: emit-preflight
	@$(EMIT) build test-text-files-r7rs
	@sh tests/test-text-files.sh

pitch-run: emit-preflight
	@$(EMIT) run $(PITCH_PROGRAM) --manifest $(PITCH_MANIFEST) -- $(PITCH_ARGS)

pitch-build: build/pitch

self-format: build/pitch
	@build/pitch --dialect r7rs $(PITCH_FORMAT_SOURCES)

self-check: build/pitch
	@build/pitch --check --dialect r7rs $(PITCH_FORMAT_SOURCES)

real-host-test: build/pitch
	@sh tests/test-real-host.sh

door-parity: build/pitch
	@sh tests/test-door-parity.sh

no-chez-smoke: emit-preflight
	@sh tests/test-no-chez.sh

install-test:
	@sh tests/test-install.sh

build/pitch: emit-preflight $(PITCH_R7RS_SOURCES) src/pitch/default-config.scm
	@$(EMIT) build pitch --manifest $(PITCH_MANIFEST)
	@cp src/pitch/default-config.scm build/default-config.scm

audit-r7rs:
	@sh tools/audit-r7rs.sh

audit-invariants:
	@sh tools/audit-invariants.sh

reader-generate:
	@$(CHEZ) --program $(READER_GENERATOR) $(READER_SOURCE) $(READER_GENERATED)

reader-check:
	@tmp=$$(mktemp -d); \
	trap 'rm -rf "$$tmp"' EXIT HUP INT TERM; \
	$(CHEZ) --program $(READER_GENERATOR) $(READER_SOURCE) "$$tmp/reader.sld"; \
	if ! cmp -s $(READER_GENERATED) "$$tmp/reader.sld"; then \
	  echo "reader-check: $(READER_GENERATED) has drifted; run make reader-generate" >&2; \
	  diff -u $(READER_GENERATED) "$$tmp/reader.sld" >&2 || true; \
	  exit 1; \
	fi; \
	echo "reader-check: ok"

# Chez remains only at independent reader/oracle boundaries. The application
# suites, real host, and both executable doors are all exercised through Emit.
test: audit-r7rs audit-invariants reader-check emit-tests-run pitch-build
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-reader.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-recording.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-number-syntax.sps
	@sh tests/test-reader-parity.sh
	@$(MAKE) --no-print-directory oracle-datum
	@sh tests/test-real-host.sh
	@sh tests/test-door-parity.sh
	@sh tests/test-no-chez.sh
	@sh tests/test-install.sh
	@$(MAKE) --no-print-directory self-check
	@$(MAKE) --no-print-directory vendor-verify

format: self-format

format-check: self-check

# The launcher names only the private installed executable. The real program
# finds default-config.scm beside itself, so neither file points at the source
# checkout or build directory.
install: build/pitch
	@mkdir -p '$(DESTDIR)$(PITCH_LIBEXECDIR)' '$(DESTDIR)$(PREFIX)/bin'
	@cp build/pitch build/default-config.scm '$(DESTDIR)$(PITCH_LIBEXECDIR)/'
	@printf '#!/bin/sh\nexec "%s/pitch" "$$@"\n' \
	  '$(PITCH_LIBEXECDIR)' > '$(DESTDIR)$(PREFIX)/bin/pitch'
	@chmod +x '$(DESTDIR)$(PREFIX)/bin/pitch'
	@echo "installed $(DESTDIR)$(PREFIX)/bin/pitch"

uninstall:
	@rm -f '$(DESTDIR)$(PREFIX)/bin/pitch'
	@rm -f '$(DESTDIR)$(PITCH_LIBEXECDIR)/pitch' \
	  '$(DESTDIR)$(PITCH_LIBEXECDIR)/default-config.scm'
	@rmdir '$(DESTDIR)$(PITCH_LIBEXECDIR)' 2>/dev/null || true
	@echo "removed pitch from $(DESTDIR)$(PREFIX)"

# The layout engine is a port of sorawee/pretty-expressive. Written
# expectations confirm the cases we thought of; only the original disagreeing
# finds the ones we did not. Both sides render tests/oracle/documents.scm --
# one corpus, so a case cannot be added to one side and forgotten on the other
# -- and the rendered text, the cost and the taint flag must all agree.
#
# A missing Racket or a missing package is reported and skipped, not failed.
# `make test` must pass without Racket, and a red target nobody can fix trains
# people to ignore it.
# One shell for the whole recipe: make gives each line its own, so a skip has
# to be a branch rather than an early `exit 0`.
# Host `read` is an independent development oracle, never a runtime dependency.
# Its driver receives serialized source text and re-reads it independently on
# both sides; keeping it in tests/oracle makes that boundary visible and
# auditable.
oracle-datum:
	@sh tests/test-datum-oracle.sh

oracle-layout:
	@if ! command -v $(RACKET) >/dev/null 2>&1; then \
	  echo "oracle-layout: no racket on PATH; skipping"; \
	  echo "  install Racket, then: raco pkg install pretty-expressive"; \
	elif ! $(RACKET) -l racket/base -e '(require pretty-expressive)' >/dev/null 2>&1; then \
	  echo "oracle-layout: the pretty-expressive package is not installed; skipping"; \
	  echo "  raco pkg install pretty-expressive"; \
	else \
	  set -e; \
	  EMIT_VERBOSITY=quiet $(EMIT) run tests/oracle/oracle-emit.scm > $(ORACLE_OUT); \
	  $(RACKET) tests/oracle/oracle.rkt > $(ORACLE_REF); \
	  set +e; \
	  if diff -u $(ORACLE_REF) $(ORACLE_OUT); then \
	    echo "oracle-layout: $$(head -1 $(ORACLE_OUT)), all agree"; \
	  else \
	    echo "oracle-layout: FAILED (left: reference, right: pitch)"; exit 1; \
	  fi; \
	fi

# The authoritative changeset: pristine upstream reader vs. pitch's derived one.
# Exit status is ignored because a non-empty diff is the expected state.
vendor-diff:
	@diff -u vendor/laesare/reader.sls src/pitch/reader.sls || true

# Guard against accidental edits to the pristine copy.
vendor-verify:
	@test -d $(LAESARE_REPO)/.git || { \
	  echo "vendor-verify: no laesare clone at $(LAESARE_REPO)"; exit 1; }
	@status=0; \
	for f in $(VENDOR_FILES); do \
	  if git -C $(LAESARE_REPO) show $(LAESARE_TAG):$$f \
	     | diff -q - vendor/laesare/$$f >/dev/null 2>&1; then \
	    echo "ok       vendor/laesare/$$f"; \
	  else \
	    echo "MODIFIED vendor/laesare/$$f"; status=1; \
	  fi; \
	done; \
	exit $$status
