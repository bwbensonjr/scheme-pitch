;;; Emit manifest for Pitch. Entries use paths relative to this file.
((library (pitch sequence) (source "src/pitch/sequence.sld"))
 (library (pitch table) (source "src/pitch/table.sld"))
 (library (pitch error) (source "src/pitch/error.sld"))
 (library (pitch reader) (source "src/pitch/reader.sld"))
 (library (pitch lines) (source "src/pitch/lines.sld"))
 (library (pitch cost) (source "src/pitch/cost.sld"))
 (library (pitch style) (source "src/pitch/style.sld"))
 (library (pitch diagnostic) (source "src/pitch/diagnostic.sld"))
 (library (pitch doc) (source "src/pitch/doc.sld"))
 (library (pitch layout) (source "src/pitch/layout.sld"))
 (library (pitch print) (source "src/pitch/print.sld"))
 (library (pitch config) (source "src/pitch/config.sld"))
 (library (pitch format) (source "src/pitch/format.sld"))
 (library (pitch cst) (source "src/pitch/cst.sld"))
 (library (pitch parse) (source "src/pitch/parse.sld"))
 (library (pitch datum) (source "src/pitch/datum.sld"))
 (library (pitch check) (source "src/pitch/check.sld"))
 (library (pitch align) (source "src/pitch/align.sld"))
 (library (pitch cli) (source "src/pitch/cli.sld"))
 (library (tests runner) (source "tests/runner.sld"))
 (library (tests config) (source "tests/config.sld"))
 (program test-sequence
          (source "tests/test-sequence.scm")
          (output "build/test-sequence"))
 (program test-table
          (source "tests/test-table.scm")
          (output "build/test-table"))
 (program test-error
          (source "tests/test-error.scm")
          (output "build/test-error"))
 (program test-generated-number
          (source "tests/test-generated-number.scm")
          (output "build/test-generated-number"))
 (program test-number-syntax-r7rs
          (source "tests/test-number-syntax-r7rs.scm")
          (output "build/test-number-syntax-r7rs"))
 (program test-recording-r7rs
          (source "tests/test-recording-r7rs.scm")
          (output "build/test-recording-r7rs"))
 (program test-lines
          (source "tests/test-lines.scm")
          (output "build/test-lines"))
 (program test-cost
          (source "tests/test-cost.scm")
          (output "build/test-cost"))
 (program test-style-r7rs
          (source "tests/test-style-r7rs.scm")
          (output "build/test-style-r7rs"))
 (program test-diagnostic-r7rs
          (source "tests/test-diagnostic-r7rs.scm")
          (output "build/test-diagnostic-r7rs"))
 (program test-doc-r7rs
          (source "tests/test-doc-r7rs.scm")
          (output "build/test-doc-r7rs"))
 (program test-cst-r7rs
          (source "tests/test-cst-r7rs.scm")
          (output "build/test-cst-r7rs"))
 (program test-datum-check-r7rs
          (source "tests/test-datum-check-r7rs.scm")
          (output "build/test-datum-check-r7rs"))
 (program test-datum-r7rs
          (source "tests/test-datum-r7rs.scm")
          (output "build/test-datum-r7rs"))
 (program test-check-r7rs
          (source "tests/test-check-r7rs.scm")
          (output "build/test-check-r7rs"))
 (program test-layout-r7rs
          (source "tests/test-layout-r7rs.scm")
          (output "build/test-layout-r7rs"))
 (program test-config-r7rs
          (source "tests/test-config-r7rs.scm")
          (output "build/test-config-r7rs"))
 (program test-print-r7rs
          (source "tests/test-print-r7rs.scm")
          (output "build/test-print-r7rs"))
 (program test-format-r7rs
          (source "tests/test-format-r7rs.scm")
          (output "build/test-format-r7rs"))
 (program test-align-r7rs
          (source "tests/test-align-r7rs.scm")
          (output "build/test-align-r7rs"))
 (program test-cli-r7rs
          (source "tests/test-cli-r7rs.scm")
          (output "build/test-cli-r7rs"))
 (program test-text-files-r7rs
          (source "tests/test-text-files-r7rs.scm")
          (output "build/test-text-files-r7rs"))
 (program pitch
          (source "src/pitch/main.scm")
          (output "build/pitch"))
 (program layout-oracle-emit
          (source "tests/oracle/oracle-emit.scm")
          (output "build/layout-oracle-emit")))
