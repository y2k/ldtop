# Spec Delta

## MODIFIED Requirements

### Requirement: Readable sorted table
The command SHALL print an aligned plain-text table with columns `Service`, `PID`, `State`, and `Exit`, sorted by full Label in ascending case-sensitive lexical order. Missing PIDs SHALL appear as `—`. Numeric exit values SHALL preserve their sign without implying service health. Each service SHALL occupy one output line, with control characters escaped. Commands and plist paths SHALL NOT be displayed.

#### Scenario: Unsorted service data
- **WHEN** launchctl returns `z.service` with PID `123` and status `0`, followed by `a.service` with PID `-` and status `-15`, and details confirm exit code `0` for `z.service`
- **THEN** the table shows `a.service`, `—`, and exit `-15` before `z.service`, `123`, and exit `0`, with aligned columns

#### Scenario: Empty service list
- **WHEN** launchctl succeeds with a valid header and no service rows
- **THEN** the command prints only the four-column table header and exits successfully

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

## ADDED Requirements

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
