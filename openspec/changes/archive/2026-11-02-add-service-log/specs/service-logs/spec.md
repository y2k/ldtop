# Spec Delta

## Purpose

Allow users to inspect recent stdout and stderr file output of a registered launchd service without manually locating its log files.

## ADDED Requirements

### Requirement: Singular log command
`ldtop log <label>` SHALL accept exactly one full launchd label and display a finite snapshot of its configured file logs. It SHALL reject missing or extra arguments, empty labels, domain-qualified targets, and unsupported options with a usage diagnostic and exit status 2. It SHALL NOT accept shortened display names as aliases or provide a `logs` alias.

#### Scenario: Valid invocation
- **WHEN** the user invokes `ldtop log local.kofftop-tldr.prepare`
- **THEN** the command requests logs for that exact label

#### Scenario: Invalid invocation
- **WHEN** the user invokes `ldtop log`, `ldtop logs example`, `ldtop log example extra`, `ldtop log gui/501/example`, or `ldtop log example -f`
- **THEN** the command reports a usage error and exits with status 2

### Requirement: Loaded service log discovery
The command SHALL obtain `stdout path` and `stderr path` from `launchctl print` for the exact label in the same resolved context used by `ls`. It SHALL NOT search other domains, read source plists as a fallback, or apply listing visibility filters. A running PID SHALL NOT be required.

#### Scenario: Stopped or hidden service
- **WHEN** a registered service is stopped, has unknown triggers, or has a `com.apple.` label
- **THEN** its configured log paths remain available through its exact label

#### Scenario: Same label in different domains
- **WHEN** another domain contains a service with the requested label
- **THEN** the command only queries the current resolved domain

#### Scenario: Discovery failure
- **WHEN** context resolution, service lookup, or recognition of the service response fails
- **THEN** the command reports the failure on stderr, exits with status 1, and does not guess log sources

### Requirement: Last 200 lines per distinct path
The command SHALL display the last 200 lines of each configured log file, or all its lines if fewer exist, in original order. An unterminated final line SHALL count as a line. Identical stdout and stderr path strings SHALL be read once. Distinct paths SHALL be displayed stdout first, then stderr, without chronological merging or waiting for new records.

#### Scenario: Shared file
- **WHEN** stdout and stderr point to the same file containing 250 lines
- **THEN** lines 51 through 250 are displayed once

#### Scenario: Separate files
- **WHEN** stdout and stderr use distinct files with more than 200 lines each
- **THEN** the output contains the last 200 lines of stdout followed by the last 200 lines of stderr

#### Scenario: Short or empty file
- **WHEN** a configured file is empty or has fewer than 200 lines, including an unterminated final line
- **THEN** all available content is displayed and the command exits successfully

### Requirement: Identifiable output
Each file section SHALL have a heading identifying its stream (`stdout`, `stderr`, or `stdout/stderr`) and path, separate from its content. Log content SHALL be preserved; a separator newline SHALL keep a subsequent heading separate from an unterminated final line. Paths and diagnostics SHALL escape terminal control characters.

#### Scenario: Combined stream heading
- **WHEN** both streams use the same path
- **THEN** one heading identifies `stdout/stderr` and that path

### Requirement: Unconfigured file logs
If neither stream has a configured path, the command SHALL print an explicit informational message that file logs are not configured and exit with status 0. A missing optional stream SHALL NOT be treated as an error or trigger a search in Unified Log or application-specific locations.

#### Scenario: No configured paths
- **WHEN** a valid service response contains neither log path
- **THEN** the command reports that file logs are not configured and exits successfully

#### Scenario: Only stderr configured
- **WHEN** only stderr has a configured path
- **THEN** only that file is displayed without a warning for absent stdout

### Requirement: File read failures
The command SHALL read only absolute paths without NUL bytes that resolve to regular files. It SHALL report invalid paths, missing files, permission failures, non-regular files, and read failures on stderr with the affected stream and path, and exit with status 1 if any configured source fails. Other readable configured sources SHALL still be displayed. It SHALL NOT create files or modify service configuration.

#### Scenario: Partial availability
- **WHEN** stdout is readable but the stderr file is missing
- **THEN** stdout is displayed, stderr is identified in an error diagnostic, and the command exits with status 1

#### Scenario: Non-regular source
- **WHEN** a configured source is a directory, device, or FIFO
- **THEN** the command reports an unsupported source without waiting for input from it
