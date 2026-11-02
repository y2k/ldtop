# Tasks

## 1. Parse and render service data

- [x] 1.1 Confirm `/bin/launchctl list` header and row separators in the current session; verify the observed format matches the design without committing actual service labels.
- [x] 1.2 Add `lib/service_listing.ml` and the Dune library/test stanzas; implement strict parsing, Label sorting, and table rendering. Verify synthetic tests for mixed running/idle rows, signed status, empty lists, whitespace separators, invalid headers, and malformed rows pass with `dune runtest`.

## 2. Acquire the snapshot

- [x] 2.1 Add shell-free launchctl execution using Unix, inherited stderr, stdout capture, process waiting, and descriptor cleanup. Verify controlled process tests cover success, failed execution, nonzero exit, signal termination, visible stderr, and no table on failure.

## 3. Expose the CLI

- [x] 3.1 Replace the greeting with `ls` dispatch in `bin/main.ml` and link the library in `bin/dune`. Update help and verify CLI checks cover `--help`, no command, unknown commands including `list`, extra arguments, and the documented exit codes.
- [x] 3.2 Add a short Russian usage guide in `docs/usage.md` covering `make run ARGS=ls`, columns, and the inherited launchctl context. Verify its command runs and its description matches the output without claiming service health or coverage across domains.

## 4. Integration verification

- [x] 4.1 Run `make build` and `make test`, then compare `make run ARGS=ls` with `/bin/launchctl list` in the same session. Verify headers, sorting, idle rows, and matching service sets while allowing processes to change between snapshots; record any environment limitation.

## 5. Default Apple-label filtering

- [x] 5.1 Filter the case-sensitive `com.apple.` prefix in `lib/service_listing.ml` before rendering, without adding a flag. Add tests in `test/listing_test.ml` for mixed labels, idle non-Apple services, exact prefix boundaries, header-only output when all rows are hidden, and rejection of malformed Apple rows; verify `dune runtest` passes.
- [x] 5.2 Verify `ldtop ls --all` remains a usage error in `test/cli_test.ml` and update `docs/usage.md` with the exact default filter and `launchctl list` as the full-list command; verify the CLI test and documented commands.
- [x] 5.3 Run `make build` and `make test`, then compare `ldtop ls` with the same-session launchctl service set excluding the case-sensitive `com.apple.` prefix. Verify sorting, preserved idle services, and absence of matching labels; record the result and any snapshot differences.

## Verification notes (default filtering)

- `make build` and `make test` passed. Both `make run ARGS=ls` and `~/.local/bin/ldtop ls` matched the filtered launchctl snapshot: 18 of 545 services, including 5 idle services. Sorting matched, no Apple-prefix labels remained, and no label-set differences or environment blockers were observed.

## Verification notes (before default filtering)

- `make build` and `make test` passed on macOS.
- Live comparison matched 556 service labels; table headers, sorting, and idle rows passed. No environment blockers were observed. Other macOS versions were not tested.
