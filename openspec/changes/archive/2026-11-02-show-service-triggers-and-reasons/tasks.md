# Tasks

## 1. Source plist acquisition and trigger summaries

- [x] 1.1 Add `yojson` to `lib/dune` and document the dependency installation/build command in project documentation; verify `dune build` resolves the dependency.
- [x] 1.2 Extend the detail model and implement pure JSON-to-trigger summaries with Label validation, ordered tokens, interval/calendar validation, collection counts, conditional KeepAlive, and partial-data markers; verify fixture tests cover all supported keys, false/empty values, malformed values, mixed valid/invalid entries, missing/mismatched Label, and unknown keys.
- [x] 1.3 Add an injectable source reader using `/usr/bin/plutil -convert json -o -` on the reported absolute path only; verify temporary XML and binary plist fixtures produce equivalent summaries, paths with spaces remain a single argument, and conversion/read errors preserve rows with source-specific diagnostics.
- [x] 1.4 Integrate optional source acquisition into `collect` without directory scanning or cross-domain lookup; verify fixtures cover submitted applications, missing and invalid paths, filtered rows, unresolved contexts, and unavailable source data while preserving existing details.

## 2. Current launch reasons

- [x] 2.1 Query `blame` for visible rows with an initial PID in the resolved domain, independently of print/plist success; verify runner-call fixtures cover running/stopped rows, root/GUI/background domains, unknown contexts, filtered services, and print failure followed by successful blame.
- [x] 2.2 Handle successful diagnostic text, whitespace-only responses, process failures, and disappearance races; verify tests preserve the original PID and available trigger/state/exit fields, use `unknown` appropriately, and emit concise escaped diagnostics identifying the service and source.
- [x] 2.3 Generalize hard-coded launchctl error names in the process helper for plutil use and update subprocess fixtures; verify nonzero exits, signals, execution failures, quiet stderr, and fake launchctl integration still behave correctly.

## 3. Table and help

- [x] 3.1 Render `Service PID State Exit Triggers Reason` with 32/40-character limits for the new columns; update exact-output tests and replace the obsolete whole-row 80-character assertion with column-limit checks, verifying alignment, empty lists, UTF-8, escaping, provenance prefixes, name collision handling, and existing state/exit fallbacks.
- [x] 3.2 Update CLI help to explain disk configuration, summary tokens, conditional/abbreviated trigger information, diagnostic current reasons, and unavailable historical reasons; verify `test/cli_test.ml` covers both help aliases and still rejects unsupported flags and commands.

## 4. Integration and implementation review

- [x] 4.1 Run `dune runtest --force` and then `dune build` sequentially, plus `openspec validate show-service-triggers-and-reasons --strict` and `git diff --check`; record the results and resolve failures.
- [x] 4.2 Run a read-only live `ldtop ls` smoke-test, compare available trigger summaries to their source plist and current reasons to same-domain blame, and record latency and data-availability limitations; use fixtures for inaccessible contexts without changing launchd jobs.
- [x] 4.3 Review the implementation against the delta scenarios, source provenance, conditional trigger semantics, independent error handling, and command scope; fix all obvious or important findings before completion and rerun the affected checks, recording the review outcome.

## Verification record

- 4.1: `dune runtest --force`, followed by `dune build`, `openspec validate show-service-triggers-and-reasons --strict`, and `git diff --check` all passed on 2026-11-02.
- 4.2: Live read-only listing returned 17 rows without diagnostics in 0.112 seconds. Independently checked ssh-agent (`socket(1)` / `ipc (socket)`), steamclean (`load,watch(1)`), and Samsung (`load` / `speculative`) against plistlib-decoded source files and same-domain blame. Submitted applications showed unknown triggers and `launch job demand`; stopped services showed unknown reasons. Root/background contexts were covered by fixtures, not privileged live sessions. No launchd jobs were modified.
- 4.3: Self-review completed without subagents per project instructions. Checked provenance, source independence, domain/PID rules, key validation, partial collections, display limits, escaping, subprocess arguments, and compatibility. Found build instructions under the ignored `/docs/` directory and moved them to root `README.md`. Extended edge-case fixtures for empty collections, malformed supported values, partial nested collections, and calendar boundaries. Corrected indentation. Final `dune runtest --force`, `dune build`, strict change validation, and whitespace checks passed. No outstanding obvious or important findings.
