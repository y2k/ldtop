# Spec Delta

## MODIFIED Requirements

### Requirement: Discoverable command
CLI help SHALL document `ldtop ls`, the automatic omission of services with unknown triggers, the distinction between plist trigger configuration and the diagnostic current launch reason, and the absence of historical reasons for stopped services. It SHALL also document `ldtop log <label>` using a full label, its fixed 200-line snapshot per distinct stdout/stderr file, and the absence of follow mode. Unsupported commands and extra positional arguments SHALL produce a usage error and a nonzero exit code.

#### Scenario: Help
- **WHEN** the user runs `ldtop --help`
- **THEN** help includes `ldtop ls`, explains the unknown-trigger filter, `Triggers` and `Reason` and their limitations, documents `ldtop log <label>` and its fixed snapshot behavior, and exits successfully

#### Scenario: Invalid invocation
- **WHEN** the user runs `ldtop list` or `ldtop ls extra`
- **THEN** the command reports a usage error and exits nonzero

### Requirement: Compact trigger and reason presentation
Triggers and Reason SHALL be left-aligned and limited to 32 and 40 characters respectively after escaping, with trailing `...` when shortened. The `plist:` provenance prefix SHALL remain visible. These columns SHALL use `unknown` for unavailable data without changing existing service-name disambiguation, state shortening, filtering, sorting, or PID alignment. The `ls` command SHALL NOT add flags or positional arguments for these columns; the separate `log` command is outside this restriction.

#### Scenario: Long diagnostic and multiple triggers
- **WHEN** a trigger summary exceeds 32 characters and a reason exceeds 40 characters
- **THEN** both are shortened with trailing `...`, remain aligned on one row, and retain valid UTF-8

#### Scenario: Untrusted diagnostic text
- **WHEN** a successful blame response contains embedded newlines, tabs, or escape characters
- **THEN** those characters are escaped before shortening and cannot introduce extra table rows or terminal control sequences
