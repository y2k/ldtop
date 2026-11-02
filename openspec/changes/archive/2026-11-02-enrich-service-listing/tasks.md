# Tasks

## 1. Detail model and parsing

- [x] 1.1 Extend `lib/service_listing.ml` with optional service details and distinct numeric/never/unknown exit information; verify fixture assertions for explicit zero, never-exited, missing exit data, and signed list-status fallback.
- [x] 1.2 Parse immediate service fields and arguments from `launchctl print`; add sanitized fixtures in `test/listing_test.ml` covering running and idle services, absent fields, malformed output, and misleading nested state/path/exit fields; verify with `dune runtest`.

## 2. Context-aware acquisition

- [x] 2.1 Add one-time domain resolution using effective root identity or managername/manageruid, with unknown-context fallback; verify Aqua, Background, System, invalid UID, unsupported manager, and command-failure cases through an injected runner, and check supported mappings against local launchctl documentation or read-only observations.
- [x] 2.2 Enrich only visible, successfully parsed rows through argv-based launchctl print calls; adapt `run` and `bin/main.ml` as needed; verify runner traces show no calls for filtered/empty results, no cross-domain retries, and original PID/row membership preserved when a service disappears.
- [x] 2.3 Preserve fatal initial acquisition/parsing errors and add nonfatal detail/context diagnostics; verify stdout, stderr, exit status, partial details, and execution failures through fixture tests while retaining a real subprocess diagnostic test.

## 3. Table output

- [x] 3.1 Render the six specified columns, command arguments, full paths, placeholders, and escaped control characters; update assertions for sorting, filtering, empty lists, whitespace/quotes in arguments, differing argv[0], and single-line output; verify `dune runtest` passes.
- [x] 3.2 Keep help and usage behavior compatible with the existing command surface; verify `test/cli_test.ml` still covers help, invalid commands, extra arguments, and rejected flags.

## 4. Integration verification

- [x] 4.1 Run `dune runtest` and `dune build`; verify both complete successfully with all spec scenarios covered by relevant assertions or recorded smoke checks.
- [x] 4.2 Run `dune exec ./bin/main.exe -- ls` on macOS, compare available running/idle rows against read-only launchctl print output, and record elapsed time and any unavailable context checks; verify the output distinguishes `never`, numeric zero when available, and unknown evidence without modifying services.

## 5. Compact output follow-up

- [x] 5.1 Replace the wide output with aligned Label/PID/State/Exit columns, shorten long labels and states, remove unused command-formatting code, and verify rendering regressions with `dune runtest`.
- [x] 5.2 Run `dune build`, strict OpenSpec validation, and a live `ldtop ls` smoke check; verify compact aligned rows and no new flags.

- Follow-up verified: `dune runtest`, `dune build`, strict validation, and `git diff --check` passed. Live output has four aligned columns with shortened labels and no command/path columns. A concurrent dune invocation hit the build lock; the sequential smoke check then passed.

## 6. Left-side label truncation

- [x] 6.1 Move Label ellipsis to the left while preserving its suffix and column alignment; verify ASCII and UTF-8 rendering tests and a live smoke check.
- [x] 6.2 Review the implementation without subagents and fix all obvious or important findings; verify tests and strict OpenSpec validation before completion.

- Verified `dune runtest`, live `dune exec ./bin/main.exe -- ls`, strict validation, and `git diff --check`. Self-review found no obvious or important issues in the truncation change.

## 7. Readable service names

- [x] 7.1 Derive app names from program paths, shorten service prefixes, and disambiguate matching names using label suffixes; verify names, fallback, sorting, and collisions with `dune runtest`.
- [x] 7.2 Review the implementation without subagents and fix all obvious or important findings; run the build, strict OpenSpec validation, and a live smoke check before completion.

- Self-review fixed a suffix-of-another-label collision (`service` / `com.service`) with a failing regression test before the fix. `dune runtest`, `dune build`, strict validation, and `git diff --check` passed. Live smoke check displayed 19 services with names including Safari, Steam, ChatGPT, and OrbStack; no diagnostics. Missing metadata, nested apps, duplicate names, UTF-8, control characters, and original-label sorting are covered by fixtures.

## Original verification notes

- `dune runtest`, `dune build`, `git diff --check`, and strict OpenSpec validation passed. CLI help and invalid-invocation tests passed. Self-review performed without subagents.
- Parser fixtures cover running/idle states, partial and malformed data, nested fields, duplicate exit evidence, submitted applications without plist paths, and argument/control-character rendering. Acquisition fixtures cover filtering, ordering, context resolution, vanished services, and diagnostics; a real subprocess fixture covers acquisition through rendering.
- macOS GUI smoke check: 18 services, exit 0, empty stderr, 0.070 seconds including dune. Compared ssh-agent (`running`, `never`), DropboxUpdater (`not running`, `0`), and local prepare (`not running`, `never`) with read-only `launchctl print`; program and plist paths matched. Safari correctly displayed `—` for its absent plist.
- Root/Background mappings were checked against local launchctl documentation and fixtures, not exercised in live privileged/background sessions. Unknown context/evidence and failed detail reads were tested with fixtures; live failures were not induced.
