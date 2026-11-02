# Tasks

## 1. Permanent trigger filter

- [x] 1.1 Filter unavailable triggers in `render` before name disambiguation, without altering pre-acquisition filtering; verify mixed known/unknown rows, partial summaries, `plist:none-known`, hidden duplicate names, and header-only output in `test/listing_test.ml`.
- [x] 1.2 Update existing presentation fixtures to supply known triggers where row visibility is required, retaining their formatting and naming assertions; verify collection-to-render coverage with both available and unavailable sources and run `dune runtest`.
- [x] 1.3 Document the permanent filter in CLI help and README; update the CLI help assertion and verify `dune exec ./bin/main.exe -- --help`.

## 2. Integration and review

- [x] 2.1 Run `dune build` and `dune runtest`; verify successful results and retained diagnostics for optional acquisition failures.
- [x] 2.2 Review the implementation diff against the delta specification, fix all obvious or important findings before completion, and rerun affected checks after fixes.
