# Tasks

## 1. Discover configured log sources

- [x] 1.1 Extend launchctl detail parsing in `lib/service_listing.ml` with optional stdout/stderr paths, update affected record constructors and fixtures, and verify parser tests for both, one, absent, malformed, and nested unrelated fields while preserving listing behavior.
- [x] 1.2 Add exact-label log discovery using the existing context resolver and a single print query; verify fake-runner tests for stopped/hidden services, context and print failures, malformed responses, and absence of list, plist, blame, or cross-domain fallback queries.

## 2. Read and present file snapshots

- [x] 2.1 Implement regular-file validation and last-200-line reading using the system tail without shell interpolation; verify temporary-file tests for 0, fewer than 200, exactly 200, and more than 200 lines, unterminated final lines, paths with spaces, invalid paths, missing files, and nonblocking rejection of FIFOs/directories.
- [x] 2.2 Add ordered stream sections, identical-path deduplication, escaped headings/diagnostics, no-path messaging, and partial-error aggregation; verify tests for shared and separate files, stdout-only/stderr-only, raw content preservation, readable-source retention after another source fails, and permission/read failures through injected readers.

## 3. Expose the CLI

- [x] 3.1 Wire `ldtop log <label>` into `bin/main.ml` with exit codes 0/1/2 and full-label validation; extend `test/cli_test.ml` to verify help, invalid arity, empty labels, domain-qualified targets, unsupported options and the rejected `logs` alias, retaining existing ls checks.
- [x] 3.2 Update help and `README.md` with the singular command, 200 lines per distinct file, full-label requirement, no follow mode, unconfigured-source behavior, and file-error behavior; verify documented syntax against CLI tests and `--help` output.

## 4. Integration and implementation review

- [x] 4.1 Run `dune build` and `dune runtest`; perform a read-only smoke check with `local.kofftop-tldr.prepare` when available, comparing the single combined section with its file's last 200 lines and recording any environmental limitation without starting the service.
- [x] 4.2 Review the implementation against both delta specs, fix all obvious or important findings before completion, and rerun checks affected by fixes; record review findings and their resolution.

## Verification and review notes

- `dune build`, `dune runtest`, `git diff --check`, and strict OpenSpec validation passed.
- Read-only smoke check against the installed `local.kofftop-tldr.prepare` passed: exit 0, empty stderr, one combined heading, and content identical to `/usr/bin/tail -n 200` on its configured log. No service was started or reconfigured.
- Review found that malformed log-path blocks, missing value separators, and duplicate path fields could be mistaken for absent or valid configuration. Added regression cases, confirmed failure, and fixed recognition in the shared parser; all tests pass.
- File reading opens a nonblocking descriptor, verifies it is a regular file, and passes that same descriptor as tail's stdin, avoiding reopening a changed path.
- The initial simultaneous build/test invocation hit Dune's build lock; the subsequent sequential test run passed.
