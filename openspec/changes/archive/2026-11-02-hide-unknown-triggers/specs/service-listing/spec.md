# Spec Delta

## ADDED Requirements

### Requirement: Unknown trigger visibility
The command SHALL omit services whose complete trigger value is `unknown` from the final table. This rule SHALL take precedence over row-retention and detail-display requirements when trigger data is unavailable. It SHALL preserve existing acquisition diagnostics and successful exit behavior for optional detail failures. Filtering SHALL occur before display-name disambiguation.

#### Scenario: Missing trigger information
- **WHEN** a non-Apple service has no usable source, context, or trigger configuration
- **THEN** its row is omitted even if PID, state, exit, or Reason is available

#### Scenario: Partially known configuration
- **WHEN** non-Apple services have summaries `plist:load,unknown` and `plist:none-known`
- **THEN** both rows remain visible

#### Scenario: Every trigger value is unknown
- **WHEN** initial listing succeeds but all non-Apple services have unknown triggers
- **THEN** the command prints only the six-column table header and exits successfully, retaining any acquisition diagnostics

#### Scenario: Hidden duplicate name
- **WHEN** two services share a display name but one has unknown triggers
- **THEN** the visible service does not receive a disambiguation suffix due to the hidden service

## MODIFIED Requirements

### Requirement: List registered services
`ldtop ls` SHALL output a single snapshot of the services returned by `launchctl list` in the invoking user's context, excluding labels with the case-sensitive prefix `com.apple.` and services whose complete Triggers value is `unknown`. All other services SHALL remain visible, including those without a running process. It SHALL NOT modify services or scan unloaded plist files.

#### Scenario: Running and idle services
- **WHEN** the user runs `ldtop ls` and launchctl returns both running and idle services with known trigger summaries
- **THEN** the command lists every returned service whose label does not start with `com.apple.` once and exits successfully without refreshing the output

#### Scenario: Apple services are hidden
- **WHEN** launchctl returns `com.apple.example`, `org.example.running`, and `org.example.idle`, all with known trigger summaries
- **THEN** the command omits `com.apple.example` and lists both other services regardless of whether they have a running process

#### Scenario: Exact prefix boundary
- **WHEN** launchctl returns labels `com.apple`, `com.appleother.example`, `org.com.apple.example`, and `Com.apple.example`, all with known trigger summaries
- **THEN** all four labels remain visible

#### Scenario: All services are filtered out
- **WHEN** launchctl succeeds and every returned label starts with `com.apple.` or has unknown triggers
- **THEN** the command prints only the table header and exits successfully

### Requirement: Fixed default filter
The Apple-label and unknown-trigger filters SHALL apply automatically to `ldtop ls`. The command SHALL NOT introduce a flag to disable or configure them.

#### Scenario: No override flag
- **WHEN** the user runs `ldtop ls --all`
- **THEN** the command reports a usage error and exits nonzero

### Requirement: Discoverable command
CLI help SHALL document `ldtop ls`, the automatic omission of services with unknown triggers, the distinction between plist trigger configuration and the diagnostic current launch reason, and the absence of historical reasons for stopped services. Unsupported commands and extra positional arguments SHALL produce a usage error and a nonzero exit code.

#### Scenario: Help
- **WHEN** the user runs `ldtop --help`
- **THEN** help includes `ldtop ls`, explains the unknown-trigger filter, `Triggers` and `Reason` and their limitations, and exits successfully

#### Scenario: Invalid invocation
- **WHEN** the user runs `ldtop list` or `ldtop ls extra`
- **THEN** the command reports a usage error and exits nonzero
