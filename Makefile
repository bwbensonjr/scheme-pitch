# Pinned laesare vendoring. See vendor/laesare/VENDOR.md.
LAESARE_TAG   := v1.0.3
LAESARE_REPO  := ../laesare
VENDOR_FILES  := reader.sls writer.sls LICENSE.txt

CHEZ    ?= chez
LIBDIRS := src:.

.PHONY: help test vendor-diff vendor-verify

help:
	@echo "test           run the reader regression suite"
	@echo "vendor-diff    show pitch's changes to laesare's reader"
	@echo "vendor-verify  check vendor/laesare/ still matches $(LAESARE_TAG)"

# test-reader.sps is the regression baseline: the vendored laesare suite,
# ported to (pitch reader) and otherwise unmodified. test-recording.sps covers
# what pitch adds to the reader, test-cst.sps the CST layer, and test-datum.sps
# the datum projection and the layer 2 check. Must be run from the repo root;
# the read-files, round-trip-files and differential-oracle tests open relative
# paths.
test:
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-reader.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-recording.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-cst.sps
	@$(CHEZ) --libdirs $(LIBDIRS) --program tests/test-datum.sps

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
