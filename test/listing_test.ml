let compact text =
  String.split_on_char '\n' text
  |> List.map (fun line -> String.split_on_char ' ' line |> List.filter ((<>) "") |> String.concat " ")
  |> String.concat "\n"

let () =
  let open Service_listing in
  let row label triggers = {label; pid = Some 42; status = 0;
    details = {empty_details with triggers; state = Some "running"; reason = Some "timer"}} in
  let hidden = row "org.example" None in
  assert (compact (render [hidden]) = "Service PID State Exit Triggers Reason\n");
  assert (compact (render [hidden; row "com.example" (Some "plist:load,unknown");
    row "idle" (Some "plist:none-known")]) =
    "Service PID State Exit Triggers Reason\nexample 42 running unknown plist:load,unknown timer\nidle 42 running unknown plist:none-known timer\n")

let () =
  let summarize fields = Service_listing.parse_triggers ~label:"example"
    ("{\"Label\":\"example\"" ^ fields ^ "}") in
  List.iter (fun (fields, expected, bad) ->
    assert (summarize fields = (expected, bad))) [
    (",\"RunAtLoad\":true,\"StartInterval\":300", Some "plist:load,every 300s", false);
    (",\"KeepAlive\":true", Some "plist:keepalive", false);
    (",\"KeepAlive\":{\"SuccessfulExit\":false}", Some "plist:keepalive(cond)", false);
    (",\"RunAtLoad\":false,\"KeepAlive\":false,\"WatchPaths\":[],\"Other\":true", Some "plist:none-known", false);
    (",\"StartCalendarInterval\":{\"Hour\":9,\"Minute\":30}", Some "plist:calendar(30 9 * * *)", false);
    (",\"StartCalendarInterval\":[{}, {\"Weekday\":7}]", Some "plist:calendar(* * * * *;* * * * 7)", false);
    (",\"WatchPaths\":[\"/a\",\"/b\"],\"QueueDirectories\":[\"/q\"],\"StartOnMount\":true,\"MachServices\":{\"off\":false,\"on\":{}},\"Sockets\":{\"a\":{},\"b\":[{}]},\"LaunchEvents\":{\"subsystem\":{\"a\":{},\"b\":{},\"c\":{}}}", Some "plist:watch(2),queue(1),mount,mach(1),socket(2),event(3)", false);
    (",\"RunAtLoad\":true,\"StartInterval\":\"300\"", Some "plist:load,unknown", true);
    (",\"WatchPaths\":[\"/a\",false]", Some "plist:watch(1),unknown", true);
    (",\"StartCalendarInterval\":[{\"Hour\":24},{\"Hour\":9}]", Some "plist:calendar(* 9 * * *),unknown", true);
    (",\"KeepAlive\":{\"SuccessfulExit\":\"false\"}", None, true);
    (",\"KeepAlive\":{\"PathState\":{\"/a\":false}}", Some "plist:keepalive(cond)", false);
    (",\"StartInterval\":0", None, true);
    (",\"StartInterval\":-1", None, true);
    (",\"RunAtLoad\":null", None, true);
    (",\"KeepAlive\":{},\"StartCalendarInterval\":[],\"QueueDirectories\":[],\"StartOnMount\":false,\"MachServices\":{},\"Sockets\":{},\"LaunchEvents\":{}", Some "plist:none-known", false);
    (",\"KeepAlive\":{\"PathState\":{\"/a\":false,\"/bad\":null}}", Some "plist:keepalive(cond),unknown", true);
    (",\"MachServices\":{\"good\":true,\"bad\":null},\"Sockets\":{\"good\":[{},false]},\"LaunchEvents\":{\"sys\":{\"good\":{},\"bad\":false}}", Some "plist:mach(1),socket(1),event(1),unknown", true);
    (",\"StartCalendarInterval\":{\"Minute\":59,\"Hour\":23,\"Day\":31,\"Month\":12,\"Weekday\":0}", Some "plist:calendar(59 23 31 12 0)", false);
    (",\"StartCalendarInterval\":{\"Minute\":60}", None, true);
    (",\"RunAtLoad\":true,\"KeepAlive\":[],\"StartCalendarInterval\":false,\"WatchPaths\":true,\"QueueDirectories\":null,\"StartOnMount\":0,\"MachServices\":[],\"Sockets\":false,\"LaunchEvents\":[]", Some "plist:load,unknown", true)
  ];
  List.iter (fun json -> assert (Service_listing.parse_triggers ~label:"example" json = (None, true)))
    ["invalid"; "[]"; "{}"; "{\"Label\":\"other\",\"RunAtLoad\":true}"]

let table input =
  match Service_listing.parse input with
  | Ok rows -> compact (Service_listing.render (List.map (fun (row : Service_listing.service) ->
      {row with details = {row.details with triggers = Some "plist:load"}}) rows))
  | Error message -> failwith message

let () =
  let file = Filename.temp_file "ldtop source " ".plist" in
  Fun.protect ~finally:(fun () -> Sys.remove file) (fun () ->
    Out_channel.with_open_text file (fun ch -> output_string ch
      {|<?xml version="1.0"?><plist version="1.0"><dict><key>Label</key><string>example</string><key>RunAtLoad</key><true/></dict></plist>|});
    let check () = match Service_listing.read_plist file with
      | Ok json -> assert (Service_listing.parse_triggers ~label:"example" json = (Some "plist:load", false))
      | Error e -> failwith e in
    check ();
    assert (Result.is_ok (Service_listing.execute "/usr/bin/plutil" [|"plutil"; "-convert"; "binary1"; file|]));
    check ();
    Out_channel.with_open_text file (fun ch -> output_string ch "invalid plist");
    assert (Result.is_error (Service_listing.read_plist file)));
  assert (Result.is_error (Service_listing.read_plist "relative.plist"));
  assert (Result.is_error (Service_listing.read_plist "/nonexistent/ldtop.plist"))

let () =
  let open Service_listing in
  let row = { label = "test"; pid = None; status = 0; details = empty_details } in
  assert (last_exit row = Unknown);
  assert (last_exit {row with status = -15} = Code (-15));
  assert (last_exit {row with details = {empty_details with exit = Never}} = Never);
  assert (last_exit {row with details = {empty_details with exit = Code 0}} = Code 0)

let () =
  assert (table "PID\tStatus\tLabel\n123\t0\tz.service\n-\t-15\ta.service\n"
          = "Service PID State Exit Triggers Reason\na.service — unknown -15 plist:load unknown\nz.service 123 unknown unknown plist:load unknown\n");
  assert (table "PID Status Label\n\n" = "Service PID State Exit Triggers Reason\n");
  assert (table "PID Status Label\n  42  +1  a.service  \n"
          = "Service PID State Exit Triggers Reason\na.service 42 unknown 1 plist:load unknown\n");
  List.iter (fun input -> assert (Result.is_error (Service_listing.parse input)))
    [""; "wrong header\n"; "PID Status Label\nbad 0 a\n";
     "PID Status Label\n0 0 a\n"; "PID Status Label\n- x a\n";
     "PID Status Label\n- 0\n"; "PID Status Label\n- 0 a extra\n";
     "PID Status Label\n1_000 0 a\n"; "PID Status Label\n- 0x10 a\n"]

let () =
  let run script =
    Service_listing.execute "/bin/sh" [|"sh"; "-c"; script|]
    |> fun result -> Result.bind result Service_listing.parse
    |> Result.map (fun rows -> compact (Service_listing.render rows)) in
  assert (run "printf 'PID Status Label\n- 0 test.service\n'"
          = Ok "Service PID State Exit Triggers Reason\n");
  assert (Result.is_error (run "printf 'PID Status Label\n'; exit 7"));
  assert (Service_listing.execute "/bin/sh" [|"sh"; "-c"; "exit 7"|] = Error "sh exited with status 7");
  assert (Result.is_error (run "kill -TERM $$"));
  assert (Result.is_error (run "printf 'bad data\n'"));
  assert (Result.is_error (Service_listing.run "/nonexistent/ldtop-test"));
  let file = Filename.temp_file "ldtop-stderr" ".txt" in
  let saved = Unix.dup Unix.stderr in
  let fd = Unix.openfile file [Unix.O_WRONLY; Unix.O_TRUNC] 0o600 in
  let result = Fun.protect
    ~finally:(fun () -> Unix.dup2 saved Unix.stderr; Unix.close saved; Unix.close fd)
    (fun () -> Unix.dup2 fd Unix.stderr; run "echo launchctl-test-error >&2; exit 9") in
  let diagnostic = In_channel.with_open_bin file In_channel.input_all in
  Sys.remove file;
  assert (Result.is_error result);
  assert (diagnostic = "launchctl-test-error\n")

let () =
  assert (table "PID Status Label\n1 0 com.apple.example\n42 0 org.example.running\n- -15 org.example.idle\n"
          = "Service PID State Exit Triggers Reason\nexample.idle — unknown -15 plist:load unknown\nexample.running 42 unknown unknown plist:load unknown\n");
  assert (table "PID Status Label\n- 0 com.apple.example\n"
          = "Service PID State Exit Triggers Reason\n");
  assert (table "PID Status Label\n- 0 com.apple\n- 0 com.appleother.example\n- 0 org.com.apple.example\n- 0 Com.apple.example\n"
          = "Service PID State Exit Triggers Reason\nCom.apple.example — unknown unknown plist:load unknown\napple — unknown unknown plist:load unknown\nappleother.example — unknown unknown plist:load unknown\ncom.apple.example — unknown unknown plist:load unknown\n");
  assert (Result.is_error (Service_listing.parse "PID Status Label\nbad 0 com.apple.example\n"))

let running_details = {|gui/501/example = {
	path = /Library/LaunchAgents/example.plist
	state = running
	program = /usr/bin/example
	arguments = {
		/usr/bin/example
		argument with spaces
		}
	}
	environment = {
		state = fake
		path = /wrong
		last exit code = 99
	}
	resource coalition = {
		state = active
	}
	last exit code = (never exited)
}
|}

let () =
  let open Service_listing in
  let details, malformed = parse_details running_details in
  assert (not malformed);
  assert (details.state = Some "running");
  assert (details.program = Some "/usr/bin/example");
  assert (details.path = Some "/Library/LaunchAgents/example.plist");
  assert (details.arguments = ["/usr/bin/example"; "argument with spaces"; "}"]);
  assert (details.exit = Never);
  let idle, malformed = parse_details "gui/501/example = {\n\tstate = not running\n\tlast exit code = 0\n}\n" in
  assert (not malformed && idle.state = Some "not running" && idle.exit = Code 0);
  let partial, malformed = parse_details "gui/501/example = {\n\tprogram = /bin/test\n\truns = 0\n}\n" in
  assert (not malformed && partial.program = Some "/bin/test" && partial.exit = Unknown);
  assert (partial.path = None && partial.state = None);
  List.iter (fun text -> let _, bad = parse_details text in assert bad)
    [""; "unrecognized output"; "gui/501/example = {\n\tstate = running\n";
     "gui/501/example = {\n\tlast exit code = garbage\n}\n";
     "gui/501/example = {\n\targuments = {\n\t\t/bin/test\n}\n"];
  let partial, bad = parse_details "gui/501/example = {\n\tprogram = /bin/test\n\tlast exit code = invalid\n}\n" in
  assert (bad && partial.program = Some "/bin/test" && partial.exit = Unknown)

let () =
  let open Service_listing in
  let resolve name uid =
    let runner = function
      | ["managername"] -> name
      | ["manageruid"] -> uid
      | _ -> assert false in
    resolve_domain ~euid:501 runner in
  assert (resolve (Ok "Aqua\n") (Ok "501\n") = Ok "gui/501");
  assert (resolve (Ok "Background\n") (Ok "502\n") = Ok "user/502");
  assert (resolve (Ok "System\n") (Ok "0\n") = Ok "system");
  assert (resolve_domain ~euid:0 (fun _ -> assert false) = Ok "system");
  List.iter (fun uid -> assert (Result.is_error (resolve (Ok "Aqua") (Ok uid))))
    [""; "bad"; "-1"; "501/other"; "1_000"];
  assert (Result.is_error (resolve (Ok "LoginWindow") (Ok "501")));
  assert (Result.is_error (resolve (Error "cannot execute") (Ok "501")));
  assert (Result.is_error (resolve (Ok "Aqua") (Error "cannot execute")))

let collect_fixture initial detail =
  let calls = ref [] and warnings = ref [] in
  let runner args =
    calls := args :: !calls;
    match args with
    | ["list"] -> initial
    | ["managername"] -> Ok "Aqua\n"
    | ["manageruid"] -> Ok "501\n"
    | ["print"; "gui/501/example"] -> detail
    | ["blame"; "gui/501/example"] -> Ok "timer fired\n"
    | _ -> failwith ("Unexpected launchctl call: " ^ String.concat " " args) in
  let result = Service_listing.collect ~read_source:(fun _ -> Ok {|{"Label":"example"}|})
    ~euid:501 ~warn:(fun s -> warnings := s :: !warnings) runner in
  result, List.rev !calls, List.rev !warnings

let () =
  let open Service_listing in
  List.iter (fun (euid, manager, domain) ->
    List.iter (fun (pid, blame, expected, warning_count) ->
      let calls = ref [] and warnings = ref [] in
      let result = collect ~euid ~warn:(fun w -> warnings := w :: !warnings)
        ~read_source:(fun _ -> assert false) (fun args ->
          calls := args :: !calls;
          match args with
          | ["list"] -> Ok ("PID Status Label\n" ^ pid ^ " 0 example\n1 0 com.apple.hidden\n")
          | ["managername"] -> Ok manager
          | ["manageruid"] -> Ok "501"
          | ["print"; target] when target = domain ^ "/example" -> Error "print unavailable"
          | ["blame"; target] when target = domain ^ "/example" && pid <> "-" -> blame
          | _ -> assert false) in
      (match result with
       | Ok [row] -> assert (row.details.reason = expected && row.details.state = None);
           assert (row.pid = if pid = "-" then None else Some 42)
       | _ -> assert false);
      assert (List.length !warnings = warning_count);
      assert (List.mem ["blame"; domain ^ "/example"] !calls = (pid <> "-")))
      ["42", Ok " timer fired\n", Some "timer fired", 1;
       "42", Ok "new reason\twith\ncontrols\027", Some "new reason\twith\ncontrols\027", 1;
       "42", Ok " \n\t", None, 2;
       "42", Error "stopped", None, 2;
       "-", Error "must not query", None, 1])
    [0, "", "system"; 501, "Aqua", "gui/501"; 501, "Background", "user/501"]

let () =
  let open Service_listing in
  let run detail source =
    let reads = ref [] and warnings = ref [] in
    let result = collect ~euid:0 ~warn:(fun s -> warnings := s :: !warnings)
      ~read_source:(fun p -> reads := p :: !reads; source) (function
        | ["list"] -> Ok "PID Status Label\n- 0 example\n1 0 com.apple.hidden\n"
        | ["print"; "system/example"] -> Ok detail
        | _ -> assert false) in
    match result with Ok [row] -> row, !reads, !warnings | _ -> assert false in
  let detail = "system/example = {\n\tstate = not running\n\tpath = /a b.plist\n}\n" in
  let row, reads, warnings = run detail (Ok {|{"Label":"example","RunAtLoad":true}|}) in
  assert (row.details.triggers = Some "plist:load" && reads = ["/a b.plist"] && warnings = []);
  assert (compact (render [row]) = "Service PID State Exit Triggers Reason\nexample — not running unknown plist:load unknown\n");
  List.iter (fun source ->
    let row, reads, warnings = run detail source in
    assert (row.details.triggers = None && row.details.state = Some "not running");
    assert (compact (render [row]) = "Service PID State Exit Triggers Reason\n");
    assert (reads = ["/a b.plist"] && List.length warnings = 1))
    [Error "denied"; Ok "not json"; Ok {|{"Label":"other"}|}];
  List.iter (fun path ->
    let detail = "system/example = {\n\tpath = " ^ path ^ "\n}\n" in
    let row, reads, _ = run detail (Error "must not read") in
    assert (row.details.triggers = None && reads = [])) ["relative.plist"; "(submitted by runningboardd.411)"];
  let _, reads, warnings = run "system/example = {\n\tstate = not running\n}\n" (Error "must not read") in
  assert (reads = [] && warnings = [])

let () =
  let open Service_listing in
  let initial = Ok "PID Status Label\n42 0 example\n1 0 com.apple.hidden\n" in
  let result, calls, warnings = collect_fixture initial (Ok running_details) in
  assert (warnings = []);
  assert (calls = [["list"]; ["managername"]; ["manageruid"]; ["print"; "gui/501/example"]; ["blame"; "gui/501/example"]]);
  (match result with
   | Ok [row] -> assert (row.label = "example" && row.pid = Some 42 && row.details.exit = Never)
   | _ -> assert false);
  let result, calls, _ = collect_fixture initial (Error "service disappeared") in
  assert (List.length calls = 5);
  (match result with
   | Ok [row] -> assert (row.pid = Some 42 && row.details.reason = Some "timer fired" && row.details.state = None)
   | _ -> assert false);
  List.iter (fun text ->
    let result, calls, warnings = collect_fixture (Ok text) (Error "must not query") in
    assert (result = Ok [] && calls = [["list"]] && warnings = []))
    ["PID Status Label\n"; "PID Status Label\n1 0 com.apple.hidden\n"];
  let result, calls, _ = collect_fixture (Ok "PID Status Label\nbad 0 com.apple.hidden\n") (Ok running_details) in
  assert (Result.is_error result && calls = [["list"]])

let () =
  let open Service_listing in
  let initial = Ok "PID Status Label\n42 0 example\n" in
  let warnings = ref [] in
  let result = collect ~euid:0 ~warn:(fun w -> warnings := escape w :: !warnings)
    ~read_source:(fun _ -> Ok {|{"Label":"example","RunAtLoad":true}|}) (function
      | ["list"] -> initial
      | ["print"; "system/example"] -> Ok running_details
      | ["blame"; "system/example"] -> Error "stopped\n\027"
      | _ -> assert false) in
  (match result with
   | Ok [row] -> assert (row.pid = Some 42 && row.details.state = Some "running"
       && row.details.exit = Never && row.details.triggers = Some "plist:load" && row.details.reason = None)
   | _ -> assert false);
  assert (!warnings = ["example: blame: stopped\\n\\x1b"]);
  let result, _, warnings = collect_fixture initial (Error "permission denied") in
  assert (Result.is_ok result && warnings = ["example: permission denied"]);
  assert (Result.map (fun rows -> compact (render rows)) result = Ok "Service PID State Exit Triggers Reason\n");
  let result, calls, warnings = collect_fixture (Error "list failed") (Ok running_details) in
  assert (result = Error "list failed" && calls = [["list"]] && warnings = []);
  let result, _, warnings = collect_fixture initial
    (Ok "gui/501/example = {\n\tprogram = /bin/test\n\tlast exit code = invalid\n}\n") in
  assert (List.length warnings = 1);
  (match result with
   | Ok [row] -> assert (row.details.program = Some "/bin/test" && last_exit row = Unknown)
   | _ -> assert false);
  let warnings = ref [] in
  let result = collect ~euid:501 ~warn:(fun s -> warnings := s :: !warnings) (function
    | ["list"] -> initial
    | ["managername"] -> Error "no context"
    | _ -> assert false) in
  assert (!warnings = ["context: no context"]);
  assert (Result.map (fun rows -> compact (render rows)) result = Ok "Service PID State Exit Triggers Reason\n");
  (match result with Ok [row] -> assert (row.pid = Some 42 && row.details = empty_details) | _ -> assert false);
  let file = Filename.temp_file "ldtop-quiet" ".txt" in
  let saved = Unix.dup Unix.stderr in
  let fd = Unix.openfile file [Unix.O_WRONLY; Unix.O_TRUNC] 0o600 in
  let result = Fun.protect
    ~finally:(fun () -> Unix.dup2 saved Unix.stderr; Unix.close saved; Unix.close fd)
    (fun () -> Unix.dup2 fd Unix.stderr;
      execute ~quiet:true "/bin/sh" [|"sh"; "-c"; "echo hidden >&2; exit 3"|]) in
  let diagnostic = In_channel.with_open_bin file In_channel.input_all in
  Sys.remove file;
  assert (Result.is_error result && diagnostic = "")

let () =
  let open Service_listing in
  let details = {empty_details with state = Some "running"; program = Some "/usr/bin/ssh-agent";
    arguments = ["/usr/bin/ssh-agent"; "-l"]; path = Some "/System/Library/LaunchAgents/com.openssh.ssh-agent.plist";
    exit = Never; triggers = Some "plist:load"} in
  let row = {label = "com.openssh.ssh-agent"; pid = Some 42; status = 0; details} in
  assert (compact (render [row]) = "Service PID State Exit Triggers Reason\nopenssh.ssh-agent 42 running never plist:load unknown\n");
  let row = {row with label = "label\027[31m"; pid = None;
    details = {empty_details with state = Some "not running"; exit = Code 0; triggers = Some "plist:load";
      program = Some "/bin/test"; arguments = ["/bin/test"; "line\nbreak\t\027"]; path = Some "/a\rb"}} in
  assert (compact (render [row]) = "Service PID State Exit Triggers Reason\nlabel\\x1b[31m — not running 0 plist:load unknown\n")

let () =
  let details, bad = Service_listing.parse_details
    "gui/501/application.example = {\n\tpath = (submitted by runningboardd.411)\n\tstate = running\n\tsubmitted job. ignore execute allowed\n\tnew optional field = \n}\n" in
  assert (not bad);
  assert (details.state = Some "running" && details.path = None)

let () =
  let details, bad = Service_listing.parse_details
    "gui/501/example = {\n\tlast exit code = (never exited)\n\tlast exit code = 0\n}\n" in
  assert (bad && details.exit = Service_listing.Unknown)

let () =
  let file = Filename.temp_file "ldtop-launchctl" ".sh" in
  Fun.protect ~finally:(fun () -> Sys.remove file) (fun () ->
    Out_channel.with_open_text file (fun channel -> output_string channel {|#!/bin/sh
case "$1:$2" in
  list:) printf 'PID Status Label\n- 0 example\n' ;;
  managername:) echo Aqua ;;
  manageruid:) echo 501 ;;
  print:*/example) printf '%s = {\n\tstate = not running\n\tprogram = /bin/echo\n\targuments = {\n\t\t/bin/echo\n\t\ttwo words\n\t}\n\tlast exit code = 0\n}\n' "$2" ;;
  *) exit 99 ;;
esac
|});
    Unix.chmod file 0o700;
    assert (Result.map compact (Service_listing.run file) = Ok "Service PID State Exit Triggers Reason\n"))

let () =
  let open Service_listing in
  let row label pid state exit = {label; pid; status = 0; details = {empty_details with state = Some state; exit; triggers = Some "plist:load"}} in
  assert (render [row "z.service" (Some 123) "running" Never; row "a.service" None "not running" (Code 0)]
    = "Service    PID  State        Exit   Triggers    Reason\na.service    —  not running  0      plist:load  unknown\nz.service  123  running      never  plist:load  unknown\n");
  let long_label = String.make 60 'a' in
  let result = render [row long_label (Some 12345) "a very long state name" Never] in
  assert (compact result = "Service PID State Exit Triggers Reason\n...aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa 12345 a very long s... never plist:load unknown\n");
  let result = render [row (String.make 50 'a' ^ ".service-end") None "running" Never] in
  assert (compact result = "Service PID State Exit Triggers Reason\n...aaaaaaaaaaaaaaaaaaaaaaaaa.service-end — running never plist:load unknown\n");
  let unicode = String.concat "" (List.init 45 (fun _ -> "я")) in
  assert (String.is_valid_utf_8 (render [row unicode None "running" Unknown]))

let () =
  let open Service_listing in
  let app label program = {label; pid = None; status = 0;
    details = {empty_details with program; state = Some "running"; exit = Never; triggers = Some "plist:load"}} in
  let show rows = compact (render rows) in
  assert (show [app "application.com.apple.Safari.123.456" (Some "/Applications/Safari.app/Contents/MacOS/Safari")]
    = "Service PID State Exit Triggers Reason\nSafari — running never plist:load unknown\n");
  assert (show [app "application.helper" (Some "/Applications/Editor.app/Contents/Helpers/Helper.app/Contents/MacOS/helper")]
    = "Service PID State Exit Triggers Reason\nHelper — running never plist:load unknown\n");
  assert (show [app "application.unknown" None; app "application.tool" (Some "/usr/bin/tool")]
    = "Service PID State Exit Triggers Reason\napplication.tool — running never plist:load unknown\napplication.unknown — running never plist:load unknown\n");
  assert (show [app "local.worker" None; app "us.zoom.updater" None; app "com.openssh.ssh-agent" None]
    = "Service PID State Exit Triggers Reason\nopenssh.ssh-agent — running never plist:load unknown\nlocal.worker — running never plist:load unknown\nzoom.updater — running never plist:load unknown\n");
  let editor = Some "/Applications/Editor.app/Contents/MacOS/Editor" in
  assert (show [app "application.b.2" editor; app "application.a.1" editor]
    = "Service PID State Exit Triggers Reason\nEditor [1] — running never plist:load unknown\nEditor [2] — running never plist:load unknown\n");
  assert (show [app "org.example.worker" None; app "com.example.worker" None]
    = "Service PID State Exit Triggers Reason\nexample.worker [com.example.worker] — running never plist:load unknown\nexample.worker [org.example.worker] — running never plist:load unknown\n");
  assert (show [app "application.z" (Some "/Applications/Alpha.app/Contents/MacOS/Alpha");
               app "application.a" (Some "/Applications/Zulu.app/Contents/MacOS/Zulu")]
    = "Service PID State Exit Triggers Reason\nZulu — running never plist:load unknown\nAlpha — running never plist:load unknown\n");
  assert (show [app "com.service" (Some "/Applications/Editor.app/Contents/MacOS/Editor")]
    = "Service PID State Exit Triggers Reason\nservice — running never plist:load unknown\n");
  assert (show [app "service" None; app "com.service" None]
    = "Service PID State Exit Triggers Reason\nservice [com.service] — running never plist:load unknown\nservice [service] — running never plist:load unknown\n");
  assert (show [app "application.unicode" (Some "/Applications/Редактор.app/Contents/MacOS/editor")]
    = "Service PID State Exit Triggers Reason\nРедактор — running never plist:load unknown\n");
  assert (show [app "application.escape" (Some "/Applications/Bad\027Name.app/Contents/MacOS/bad")]
    = "Service PID State Exit Triggers Reason\nBad\\x1bName — running never plist:load unknown\n")

let () =
  let open Service_listing in
  let row = {label = "example"; pid = Some 42; status = 0;
    details = {empty_details with triggers = Some "plist:load,every 300s";
      reason = Some "timer\n\t\027fired"}} in
  assert (compact (render [row]) = "Service PID State Exit Triggers Reason\nexample 42 unknown unknown plist:load,every 300s timer\\n\\t\\x1bfired\n");
  let row = {row with details = {row.details with triggers = Some ("plist:" ^ String.make 50 't'); reason = Some (String.make 50 'r')}} in
  assert (compact (render [row]) = "Service PID State Exit Triggers Reason\nexample 42 unknown unknown plist:ttttttttttttttttttttttt... rrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr...\n");
  let unicode = String.concat "" (List.init 50 (fun _ -> "я")) in
  assert (String.is_valid_utf_8 (render [{row with details = {row.details with reason = Some unicode}}]))
