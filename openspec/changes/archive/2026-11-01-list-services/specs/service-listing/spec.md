# Spec Delta

## Purpose

Allow users to inspect registered launchd services in their current launchctl context through a single readable command.

## ADDED Requirements

### Requirement: List registered services
`ldtop ls` SHALL output a single snapshot of the services returned by `launchctl list` in the invoking user's context, excluding labels with the case-sensitive prefix `com.apple.`. All other services SHALL remain visible, including those without a running process. It SHALL NOT modify services or scan unloaded plist files.

#### Scenario: Running and idle services
- **WHEN** the user runs `ldtop ls` and launchctl returns both running and idle services
- **THEN** the command lists every returned service whose label does not start with `com.apple.` once and exits successfully without refreshing the output

#### Scenario: Apple services are hidden
- **WHEN** launchctl returns `com.apple.example`, `org.example.running`, and `org.example.idle`
- **THEN** the command omits `com.apple.example` and lists both other services regardless of whether they have a running process

#### Scenario: Exact prefix boundary
- **WHEN** launchctl returns labels `com.apple`, `com.appleother.example`, `org.com.apple.example`, and `Com.apple.example`
- **THEN** all four labels remain visible

#### Scenario: All services are filtered out
- **WHEN** launchctl succeeds and every returned label starts with `com.apple.`
- **THEN** the command prints only the table header and exits successfully

### Requirement: Fixed default filter
The Apple-label filter SHALL apply automatically to `ldtop ls`. The command SHALL NOT introduce a flag to disable or configure it.

#### Scenario: No override flag
- **WHEN** the user runs `ldtop ls --all`
- **THEN** the command reports a usage error and exits nonzero

### Requirement: Readable sorted table
The command SHALL print a plain-text table to stdout with columns `Label`, `PID`, and `Last exit`, sorted by Label in ascending case-sensitive lexical order. Missing PIDs SHALL appear as `—`. Last exit values SHALL preserve the reported signed numeric value, without interpreting it as service health.

#### Scenario: Unsorted service data
- **WHEN** launchctl returns `z.service` with PID `123` and status `0`, followed by `a.service` with PID `-` and status `-15`
- **THEN** the table shows `a.service`, `—`, `-15` before `z.service`, `123`, `0`

#### Scenario: Empty service list
- **WHEN** launchctl succeeds with a valid header and no service rows
- **THEN** the command prints only the table header and exits successfully

### Requirement: Acquisition failures are visible
If launchctl cannot be executed or terminates unsuccessfully, the command SHALL report the failure on stderr and exit nonzero, without printing a service table. Diagnostics from launchctl SHALL remain visible on stderr.

#### Scenario: Launchctl failure
- **WHEN** launchctl writes a diagnostic and exits nonzero
- **THEN** the diagnostic is visible on stderr, stdout contains no table, and ldtop exits nonzero

#### Scenario: Execution failure
- **WHEN** launchctl cannot be started
- **THEN** ldtop writes an explanatory diagnostic to stderr and exits nonzero

### Requirement: Reject malformed service data
The command SHALL reject unrecognized headers or malformed service rows with a diagnostic on stderr and a nonzero exit code rather than returning a partial or misleading table.

#### Scenario: Invalid service row
- **WHEN** otherwise successful launchctl output contains a row with an invalid PID or missing field
- **THEN** ldtop reports a parsing error and prints no table

### Requirement: Discoverable command
CLI help SHALL document `ldtop ls`. Unsupported commands and extra positional arguments SHALL produce a usage error and a nonzero exit code.

#### Scenario: Help
- **WHEN** the user runs `ldtop --help`
- **THEN** help includes `ldtop ls` and the command exits successfully

#### Scenario: Invalid invocation
- **WHEN** the user runs `ldtop list` or `ldtop ls extra`
- **THEN** the command reports a usage error and exits nonzero
