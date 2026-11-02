# service-listing Specification

## Purpose

Allow users to inspect registered launchd services in their current launchctl context through a single readable command.

## Requirements

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

### Requirement: Acquisition failures are visible
If the initial service-list acquisition cannot execute launchctl or terminates unsuccessfully, the command SHALL report the failure on stderr and exit nonzero, without printing a service table. Diagnostics from that acquisition SHALL remain visible on stderr. Failures of optional detail acquisition SHALL instead follow the partial-detail behavior.

#### Scenario: Launchctl failure
- **WHEN** the initial launchctl list writes a diagnostic and exits nonzero
- **THEN** the diagnostic is visible on stderr, stdout contains no table, and ldtop exits nonzero

#### Scenario: Execution failure
- **WHEN** launchctl cannot be started for the initial service list
- **THEN** ldtop writes an explanatory diagnostic to stderr and exits nonzero

### Requirement: Reject malformed service data
The command SHALL reject unrecognized headers or malformed service rows with a diagnostic on stderr and a nonzero exit code rather than returning a partial or misleading table.

#### Scenario: Invalid service row
- **WHEN** otherwise successful launchctl output contains a row with an invalid PID or missing field
- **THEN** ldtop reports a parsing error and prints no table

### Requirement: Discoverable command
CLI help SHALL document `ldtop ls`, the automatic omission of services with unknown triggers, the distinction between plist trigger configuration and the diagnostic current launch reason, and the absence of historical reasons for stopped services. It SHALL also document `ldtop log <label>` using a full label, its fixed 200-line snapshot per distinct stdout/stderr file, and the absence of follow mode. Unsupported commands and extra positional arguments SHALL produce a usage error and a nonzero exit code.

#### Scenario: Help
- **WHEN** the user runs `ldtop --help`
- **THEN** help includes `ldtop ls`, explains the unknown-trigger filter, `Triggers` and `Reason` and their limitations, documents `ldtop log <label>` and its fixed snapshot behavior, and exits successfully

#### Scenario: Invalid invocation
- **WHEN** the user runs `ldtop list` or `ldtop ls extra`
- **THEN** the command reports a usage error and exits nonzero

### Requirement: Service details in the current context
For each visible service, the command SHALL display the reported launchd state. It SHALL obtain details only from the same launchctl context as the initial list and SHALL NOT infer health. Missing state SHALL appear as `unknown`.

#### Scenario: Known service details
- **WHEN** a listed service reports state `running`, program `/usr/bin/ssh-agent`, arguments `/usr/bin/ssh-agent` and `-l`, and a source plist path
- **THEN** its row displays `running` without the command or plist path

#### Scenario: Idle service and missing source
- **WHEN** a listed service reports state `not running` and a program but no source plist path
- **THEN** its row displays `not running` without the command or plist path

#### Scenario: Same label in different domains
- **WHEN** two launchd domains contain the same label
- **THEN** the row uses only details belonging to the initial list's context, or unknown values when that context cannot be resolved

### Requirement: Distinct last exit information
The command SHALL show `never` only when service details explicitly report that the service has never exited. A reported numeric detail exit code SHALL be displayed as a signed number. Without either detail, a nonzero list status SHALL remain numeric and a zero list status SHALL appear as `unknown`. Missing or ambiguous evidence SHALL NOT be presented as a successful exit.

#### Scenario: Never exited
- **WHEN** the list status is `0` and details report `last exit code = (never exited)`
- **THEN** Exit displays `never`

#### Scenario: Successful previous exit
- **WHEN** details explicitly report numeric last exit code `0`
- **THEN** Exit displays `0`, distinct from `never`

#### Scenario: Missing exit evidence
- **WHEN** no usable last exit detail is available and the list status is `0`
- **THEN** Exit displays `unknown`

#### Scenario: Signed fallback status
- **WHEN** no usable last exit detail is available and the list status is `-15`
- **THEN** Exit displays `-15`

### Requirement: Partial detail availability
Failure to obtain or recognize optional details SHALL NOT remove a listed service or fail the command. Available fields SHALL remain visible and unavailable fields SHALL use their documented placeholders. Detail failures SHALL produce a concise diagnostic on stderr identifying the affected service, or the context when resolution fails. The initial list SHALL remain the authority for row membership and PID.

#### Scenario: Service disappears during acquisition
- **WHEN** a service is listed successfully but disappears before its details are read
- **THEN** its row remains with its original PID, unavailable detail placeholders, and last exit fallback, a diagnostic identifies the service, and the command exits successfully

#### Scenario: Partial or unfamiliar detail output
- **WHEN** detail output has a recognized program but no usable state or last exit field
- **THEN** the command uses the documented state and exit fallbacks and does not infer state from PID

#### Scenario: Context unavailable
- **WHEN** the initial list succeeds but its detail domain cannot be resolved reliably
- **THEN** the command prints all eligible rows with detail placeholders and exit fallbacks, emits a context diagnostic, and exits successfully

### Requirement: Compact default presentation
The command SHALL shorten service names beyond 40 characters using a leading `...` before disambiguation, and states beyond 16 characters using a trailing `...`, without changing sorting, filtering, or acquisition identifiers. It SHALL align PID values to the right and other columns to the left. No output-mode flags SHALL be introduced.

#### Scenario: Long labels and paths
- **WHEN** services have long labels, commands, and plist paths
- **THEN** each row displays a service name of at most 40 characters before disambiguation, with a leading `...` when shortened, omits commands and paths, and keeps column positions aligned

#### Scenario: Long state
- **WHEN** a reported state exceeds 16 characters
- **THEN** its display is shortened with `...` while PID and exit values remain complete

### Requirement: Readable service names
For labels starting with `application.`, the command SHALL use the innermost nonempty `.app` directory name from the reported program path, without `.app`. If unavailable, it SHALL use the original label. For other labels it SHALL remove one leading `com.`, `org.`, or `us.` prefix; it SHALL preserve `local.` and other prefixes. Names SHALL affect display only.

#### Scenario: Application name
- **WHEN** an application label has program `/Applications/Editor.app/Contents/MacOS/Editor`
- **THEN** Service displays `Editor` without generated label numbers

#### Scenario: Nested application
- **WHEN** an application program is inside `/Applications/Editor.app/Contents/Helpers/Helper.app/Contents/MacOS/Helper`
- **THEN** Service displays `Helper`

#### Scenario: Service prefix
- **WHEN** services have labels `com.openssh.ssh-agent`, `org.example.worker`, `us.zoom.updater`, and `local.prepare`
- **THEN** their names are `openssh.ssh-agent`, `example.worker`, `zoom.updater`, and `local.prepare`

#### Scenario: Application details unavailable
- **WHEN** an application has no usable `.app` program path
- **THEN** its name falls back to its original label with the usual shortening

### Requirement: Distinguishable names
When visible rows have the same shortened name, the command SHALL append a distinguishing dot-separated suffix of each full label in brackets. The suffix SHALL be kept complete, even if the resulting name exceeds 40 characters. Rows SHALL remain distinct and sorted by full label.

#### Scenario: Duplicate application names
- **WHEN** labels `application.a.1` and `application.b.2` both resolve to `Editor`
- **THEN** Service displays `Editor [1]` and `Editor [2]`

#### Scenario: Shared last component
- **WHEN** labels `com.example.worker` and `org.example.worker` share the shortened name `example.worker`
- **THEN** names include enough of their labels to distinguish the `com` and `org` services

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
Triggers and Reason SHALL be left-aligned and limited to 32 and 40 characters respectively after escaping, with trailing `...` when shortened. The `plist:` provenance prefix SHALL remain visible. These columns SHALL use `unknown` for unavailable data without changing existing service-name disambiguation, state shortening, filtering, sorting, or PID alignment. The `ls` command SHALL NOT add flags or positional arguments for these columns; the separate `log` command is outside this restriction.

#### Scenario: Long diagnostic and multiple triggers
- **WHEN** a trigger summary exceeds 32 characters and a reason exceeds 40 characters
- **THEN** both are shortened with trailing `...`, remain aligned on one row, and retain valid UTF-8

#### Scenario: Untrusted diagnostic text
- **WHEN** a successful blame response contains embedded newlines, tabs, or escape characters
- **THEN** those characters are escaped before shortening and cannot introduce extra table rows or terminal control sequences

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
