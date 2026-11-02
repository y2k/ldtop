let () =
  let arguments = ref [] in
  let usage = {|Usage: ldtop ls
       ldtop log <label>

Services with Triggers=unknown are always hidden.
Triggers: plist: marks configuration on disk, which may differ from the loaded job.
  load = RunAtLoad; keepalive = continuous; keepalive(cond) = conditional.
  every Ns = interval; calendar(Minute Hour Day Month Weekday), * = any.
  watch(N), queue(N), mach(N), socket(N), event(N) = configured counts;
  mount = filesystem mount; none-known does not mean manual-only launch.
Reason: diagnostic current launch reason from launchctl blame, not full history.
  For stopped services it is unknown. Queries are not an atomic snapshot.
  unknown = unavailable; ... = shortened information.

log: use the full launchd label in the current context, not a shortened Service name.
  Shows the last 200 lines per distinct stdout/stderr file; no follow mode.
  Unconfigured file logs are reported without error. File errors exit nonzero;
  other readable logs are still shown. Logs are printed as stored.
|} in
  Arg.parse []
    (fun arg -> arguments := arg :: !arguments) usage;
  match List.rev !arguments with
  | ["ls"] ->
      (match Service_listing.run "/bin/launchctl" with
       | Ok table -> print_string table
       | Error message -> prerr_endline ("ldtop: " ^ message); exit 1)
  | ["log"; label] when label <> "" && not (String.contains label '/') ->
      let open Service_listing in
      let warn message = prerr_endline ("ldtop: " ^ message) in
      let runner args = execute ~quiet:true "/bin/launchctl"
        (Array.of_list ("launchctl" :: args)) in
      (match discover_logs ~euid:(Unix.geteuid ()) ~label runner with
       | Error message -> warn (escape (label ^ ": " ^ message)); exit 1
       | Ok details ->
           let output, errors = log_snapshot ~read_source:read_log details in
           print_string output;
           List.iter warn errors;
           if errors <> [] then exit 1)
  | _ -> prerr_endline usage; exit 2
