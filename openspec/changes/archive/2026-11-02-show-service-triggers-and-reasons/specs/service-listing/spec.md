# Spec Delta

## MODIFIED Requirements

### Requirement: Readable sorted table
The command SHALL print an aligned plain-text table with columns `Service`, `PID`, `State`, `Exit`, `Triggers`, and `Reason`, sorted by full Label in ascending case-sensitive lexical order. Missing PIDs SHALL appear as `—`. Numeric exit values SHALL preserve their sign without implying service health. Each service SHALL occupy one output line, with control characters escaped. Commands and plist paths SHALL NOT be displayed.

#### Scenario: Unsorted service data
- **WHEN** launchctl returns `z.service` with PID `123` and status `0`, followed by `a.service` with PID `-` and status `-15`, and details confirm exit code `0` for `z.service`
- **THEN** the table shows `a.service`, `—`, and exit `-15` before `z.service`, `123`, and exit `0`, with aligned columns

#### Scenario: Empty service list
- **WHEN** launchctl succeeds with a valid header and no service rows
- **THEN** the command prints only the six-column table header and exits successfully

#### Scenario: Control characters in details
- **WHEN** a displayed detail contains a tab, newline, or terminal escape character
- **THEN** the character is escaped and the service remains on one output line

### Requirement: Discoverable command
CLI help SHALL document `ldtop ls`, the distinction between plist trigger configuration and the diagnostic current launch reason, and the absence of historical reasons for stopped services. Unsupported commands and extra positional arguments SHALL produce a usage error and a nonzero exit code.

#### Scenario: Help
- **WHEN** the user runs `ldtop --help`
- **THEN** help includes `ldtop ls`, explains `Triggers` and `Reason` and their limitations, and exits successfully

#### Scenario: Invalid invocation
- **WHEN** the user runs `ldtop list` or `ldtop ls extra`
- **THEN** the command reports a usage error and exits nonzero

## ADDED Requirements

### Requirement: Trigger configuration provenance
Triggers SHALL summarize only the source plist reported for that service in its resolved context, after verifying its Label matches the full service label. Known summaries SHALL start with `plist:` to distinguish disk configuration from loaded runtime settings. Missing source or context SHALL yield `unknown`. The command SHALL NOT search directories or other domains for a substitute source.

#### Scenario: Matching source
- **WHEN** the reported source plist has the same Label as the listed service and enables RunAtLoad
- **THEN** Triggers displays `plist:load`, without asserting that it caused the current launch

#### Scenario: Submitted application
- **WHEN** service details contain a submission description rather than a source file path
- **THEN** Triggers is `unknown` and no source file is guessed

#### Scenario: Source identity mismatch
- **WHEN** the reported plist has a missing or different Label
- **THEN** Triggers is `unknown`, a diagnostic identifies the service, and its row remains

#### Scenario: Configuration changed on disk
- **WHEN** a matching source plist differs from the loaded job configuration
- **THEN** Triggers remains explicitly marked `plist:` and is not described as the effective loaded configuration

### Requirement: Compact trigger summaries
Triggers SHALL summarize supported non-disabled keys in this order: RunAtLoad, KeepAlive, StartInterval, StartCalendarInterval, WatchPaths, QueueDirectories, StartOnMount, MachServices, Sockets, LaunchEvents. Summaries SHALL distinguish conditional from unconditional KeepAlive, preserve interval seconds and calendar constraints, and show counts for path, endpoint, and event collections. An absence of supported enabled keys SHALL display `plist:none-known`, not imply manual-only launch.

#### Scenario: Load and interval
- **WHEN** RunAtLoad is true and StartInterval is 300
- **THEN** the unshortened summary is `plist:load,every 300s`

#### Scenario: Conditional keepalive
- **WHEN** KeepAlive is a nonempty condition dictionary
- **THEN** its summary includes `keepalive(cond)` rather than unconditional `keepalive`

#### Scenario: Disabled triggers
- **WHEN** RunAtLoad and KeepAlive are false and no other supported enabled keys exist
- **THEN** the summary is `plist:none-known`

#### Scenario: Calendar schedules
- **WHEN** StartCalendarInterval contains one dictionary or an array of dictionaries
- **THEN** each schedule is represented in stable Minute, Hour, Day, Month, Weekday order, with `*` for missing fields, before display shortening

#### Scenario: Event collections
- **WHEN** a source has two WatchPaths, one QueueDirectories entry, enabled StartOnMount, one enabled MachServices entry, two named Sockets entries, and three LaunchEvents descriptors
- **THEN** the unshortened summary includes `watch(2),queue(1),mount,mach(1),socket(2),event(3)` in that order

### Requirement: Partial trigger configuration
Unavailable or invalid source data SHALL NOT fail listing or discard existing details. Failed conversion, malformed structure, or invalid supported key values SHALL produce a service diagnostic. Valid trigger entries SHALL survive unrelated invalid entries, with `unknown` appended to their summary; if none remain, Triggers SHALL be `unknown`. Missing optional source paths and unsupported keys alone SHALL NOT cause warnings.

#### Scenario: Unreadable or unsupported plist
- **WHEN** the reported source cannot be read or converted into supported structured data
- **THEN** Triggers is `unknown`, a service diagnostic is emitted, and PID, state, exit, and available Reason remain visible

#### Scenario: Invalid interval alongside valid trigger
- **WHEN** RunAtLoad is true and StartInterval is a string rather than a positive integer
- **THEN** the summary is `plist:load,unknown` and a diagnostic identifies the service

#### Scenario: No source available
- **WHEN** a service has no source path but its other optional details were obtained successfully
- **THEN** Triggers is `unknown` without a warning for the absent path

### Requirement: Current launch reason
For visible services with a PID in the initial list and a resolved context, the command SHALL query `launchctl blame` using the full label in that context. Successful nonempty diagnostic text SHALL populate Reason without inferring a trigger from configuration, state, or exit status. Services without an initial PID SHALL show `unknown` without a blame query. Reason SHALL NOT claim historical or exhaustive causality.

#### Scenario: Running service
- **WHEN** blame successfully reports a timer-related reason for a visible service with an initial PID
- **THEN** Reason contains that diagnostic text even if its plist is unavailable

#### Scenario: Stopped service
- **WHEN** the initial list contains no PID for a service with a configured timer
- **THEN** Reason is `unknown` and no blame query is made for that row

#### Scenario: Same label across contexts
- **WHEN** a service label exists in multiple domains
- **THEN** blame is queried only in the initial list's resolved domain, or not at all if that domain is unavailable

#### Scenario: Filtered service
- **WHEN** the initial list contains a label starting with `com.apple.`
- **THEN** no source plist or blame query is performed for that filtered row

### Requirement: Launch reason failures
Failed or empty blame responses SHALL yield `unknown` with a concise service diagnostic, retaining the row and other available fields and exiting successfully. The initial list SHALL remain authoritative for PID and membership even when a service exits during acquisition. Failure of print or plist acquisition SHALL NOT prevent an independent blame query when the context and initial PID are known.

#### Scenario: Service stops during query
- **WHEN** a service has an initial PID but blame fails because it stopped
- **THEN** its original PID remains visible, Reason is `unknown`, and a diagnostic identifies the service

#### Scenario: Details failure but reason available
- **WHEN** print fails but blame succeeds for a row with an initial PID and a known domain
- **THEN** the reported reason is displayed alongside the existing detail fallbacks

#### Scenario: Empty successful response
- **WHEN** blame exits successfully with only whitespace
- **THEN** Reason is `unknown` and a service diagnostic is emitted

### Requirement: Compact trigger and reason presentation
Triggers and Reason SHALL be left-aligned and limited to 32 and 40 characters respectively after escaping, with trailing `...` when shortened. The `plist:` provenance prefix SHALL remain visible. These columns SHALL use `unknown` for unavailable data without changing existing service-name disambiguation, state shortening, filtering, sorting, or PID alignment. No commands or flags SHALL be added.

#### Scenario: Long diagnostic and multiple triggers
- **WHEN** a trigger summary exceeds 32 characters and a reason exceeds 40 characters
- **THEN** both are shortened with trailing `...`, remain aligned on one row, and retain valid UTF-8

#### Scenario: Untrusted diagnostic text
- **WHEN** a successful blame response contains embedded newlines, tabs, or escape characters
- **THEN** those characters are escaped before shortening and cannot introduce extra table rows or terminal control sequences
