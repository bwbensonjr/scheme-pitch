# Pinned laesare vendoring. See vendor/laesare/VENDOR.md.
LAESARE_TAG   := v1.0.3
LAESARE_REPO  := ../laesare
VENDOR_FILES  := reader.sls writer.sls LICENSE.txt

CHEZ    ?= chez
RACKET  ?= racket
EMIT    ?= emit
EMIT_MANIFEST ?=
LIBDIRS := src:.

ORACLE_OUT := $(shell mktemp -t pitch-layout)
ORACLE_REF := $(shell mktemp -t pitch-layout-ref)

PREFIX ?= /usr/local

READER_SOURCE    := src/pitch/reader.sls
READER_GENERATED := src/pitch/reader.sld
READER_GENERATOR := tools/generate-reader.sps

# The project's own sources: the libraries pitch is built from and owns. Run
# `make format` before committing; `make format-check` is the same question
# without the rewrite, for a hook or a CI step.
#
# src/pitch/reader.sls is deliberately absent. It is derived from
# vendor/laesare/reader.sls, and the diff between them is required to stay
# legible and minimal because it is both the record of what pitch changed and
# the candidate patch to offer upstream. Reformatting it takes `make
# vendor-diff` from 337 lines to 1804 and leaves neither. Derived code is left
# alone here for the same reason vendored code is never edited.
#
# tests/ is out of scope too: these are the files that build the tool.
# tests/test-reader.sps in particular is laesare's own suite, ported no further
# than library renaming, and reformatting it would end that.
FORMAT_SOURCES := $(filter-out src/pitch/reader.sls,$(wildcard src/pitch/*.sls)) \
                  src/pitch/main.sps

.PHONY: help test emit-preflight audit-r7rs reader-generate reader-check \
        layout-parity oracle-layout vendor-diff vendor-verify install uninstall format format-check

help:
	@echo "test           run the reader regression suite"
	@echo "emit-preflight verify the Emit capabilities required by the port"
	@echo "audit-r7rs     reject legacy R6RS surfaces in maintained .sld files"
	@echo "reader-generate regenerate the Emit reader from authoritative reader.sls"
	@echo "reader-check   fail if the generated Emit reader has drifted"
	@echo "layout-parity compare the Chez and Emit layout corpus outcomes"
	@echo "format         format pitch's own sources in place"
	@echo "format-check   check those sources; non-zero if any would change"
	@echo "bin/pitch      generate the wrapper script for this checkout"
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

audit-r7rs:
	@sh tools/audit-r7rs.sh

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

# test-reader.sps is the regression baseline: the vendored laesare suite,
# ported to (pitch reader) and otherwise unmodified. test-recording.sps covers
# what pitch adds to the reader, test-cst.sps the CST layer, test-datum.sps the
# datum projection, test-check.sps the output safety checks, test-doc.sps the
# document algebra, test-layout.sps the layout engine, test-style.sps the style
# grammar and the tables, test-print.sps the CST-to-document translation,
# test-format.sps the end-to-end pipeline, and test-cli.sps the command line.
# Must be run from the repo root; the read-files, round-trip-files,
# differential-oracle and corpus tests open relative paths.
#
# test-cli.sps is the exception: it drives (pitch cli) against an in-memory
# host, so it needs no temporary directory and opens no path at all. That is
# deliberate -- the claims that matter in that layer are negative ones, and "the
# write log is empty" is exact where "the modification time did not change"
# depends on clock resolution.
#
# This target runs on Chez alone. The layout engine's differential oracle needs
# Racket and lives in oracle-layout, deliberately outside `test`.
test: emit-preflight reader-check
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-reader.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-recording.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-number-syntax.sps
	@sh tests/test-reader-parity.sh
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-cst.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-datum.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-check.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-doc.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-layout.sps
	@EMIT_VERBOSITY=quiet $(EMIT) run tests/test-layout-r7rs.scm
	@sh tests/test-layout-parity.sh
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-style.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-config.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-print.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-format.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-cli.sps

# Pitch formats itself. This runs the program out of the source tree rather than
# through bin/pitch, so it works in a fresh clone with nothing generated.
#
# Rewriting these files while the formatter is running from them is safe: Chez
# loads every library at startup, so the process is not reading what it rewrites.
format:
	@$(CHEZ) --libdirs $(LIBDIRS) --program src/pitch/main.sps \
	  --dialect r6rs $(FORMAT_SOURCES)

# Note that make reports any failing recipe as its own exit 2, so pitch's
# distinction between "would reformat" (1) and "bad invocation" (2) is not
# visible through this target. A CI step that needs to tell them apart should
# invoke pitch directly.
format-check:
	@$(CHEZ) --libdirs $(LIBDIRS) --program src/pitch/main.sps \
	  --check --dialect r6rs $(FORMAT_SOURCES)

# The wrapper is generated, never committed: it embeds this checkout's absolute
# paths, so a committed one would be one developer's directory layout. .gitignore
# covers bin/.
bin/pitch:
	@mkdir -p bin
	@printf '#!/bin/sh\n# Generated by make; edits are lost on the next run.\nexec %s --libdirs %s --program %s "$$@"\n' \
	  '$(CHEZ)' '$(CURDIR)/src' '$(CURDIR)/src/pitch/main.sps' > $@
	@chmod +x $@
	@echo "wrote $@"

# The installed wrapper points at the installed copy of the libraries rather
# than back into the source tree, so an installed pitch keeps working after the
# checkout moves or is deleted.
install:
	@mkdir -p '$(DESTDIR)$(PREFIX)/lib/pitch/pitch' '$(DESTDIR)$(PREFIX)/bin'
	@cp src/pitch/*.sls src/pitch/*.sps src/pitch/default-config.scm \
	  '$(DESTDIR)$(PREFIX)/lib/pitch/pitch/'
	@printf '#!/bin/sh\nexec %s --libdirs %s --program %s "$$@"\n' \
	  '$(CHEZ)' '$(PREFIX)/lib/pitch' '$(PREFIX)/lib/pitch/pitch/main.sps' \
	  > '$(DESTDIR)$(PREFIX)/bin/pitch'
	@chmod +x '$(DESTDIR)$(PREFIX)/bin/pitch'
	@echo "installed $(DESTDIR)$(PREFIX)/bin/pitch"

uninstall:
	@rm -rf '$(DESTDIR)$(PREFIX)/lib/pitch'
	@rm -f '$(DESTDIR)$(PREFIX)/bin/pitch'
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
layout-parity:
	@sh tests/test-layout-parity.sh

oracle-layout:
	@if ! command -v $(RACKET) >/dev/null 2>&1; then \
	  echo "oracle-layout: no racket on PATH; skipping"; \
	  echo "  install Racket, then: raco pkg install pretty-expressive"; \
	elif ! $(RACKET) -l racket/base -e '(require pretty-expressive)' >/dev/null 2>&1; then \
	  echo "oracle-layout: the pretty-expressive package is not installed; skipping"; \
	  echo "  raco pkg install pretty-expressive"; \
	else \
	  set -e; \
	  $(CHEZ) --libdirs $(LIBDIRS) --program tests/oracle/oracle.sps > $(ORACLE_OUT); \
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
