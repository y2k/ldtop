type exit_info = Code of int | Never | Unknown
type details = {
  state : string option;
  program : string option;
  arguments : string list;
  path : string option;
  exit : exit_info;
  triggers : string option;
  reason : string option;
  stdout_path : string option;
  stderr_path : string option;
}
type service = { label : string; pid : int option; status : int; details : details }

let empty_details = {state = None; program = None; arguments = []; path = None; exit = Unknown; triggers = None; reason = None; stdout_path = None; stderr_path = None}

let last_exit row =
  match row.details.exit with
  | Unknown when row.status <> 0 -> Code row.status
  | exit -> exit

let parse_triggers ~label text =
  try
    match Yojson.Basic.from_string text with
    | `Assoc entries when List.assoc_opt "Label" entries = Some (`String label) ->
        let bad = ref false and tokens = ref [] in
        let invalid () = bad := true; false in
        let add token = tokens := token :: !tokens in
        let check predicate value = if predicate value then true else invalid () in
        let is_bool = function `Bool _ -> true | _ -> false in
        let is_dict = function `Assoc _ -> true | _ -> false in
        let is_path = function `String s -> s <> "" | _ -> false in
        let count name n = if n > 0 then add (Printf.sprintf "%s(%d)" name n) in
        let valid_count predicate values =
          List.fold_left (fun n v -> if check predicate v then n + 1 else n) 0 values in
        let bool token = function `Bool true -> add token | `Bool false -> () | _ -> ignore (invalid ()) in
        let paths token = function
          | `List values -> count token (valid_count is_path values)
          | _ -> ignore (invalid ()) in
        let conditions = function
          | `Assoc values ->
              List.fold_left (fun n (key, value) ->
                let valid = match key, value with
                  | ("SuccessfulExit" | "NetworkState" | "Crashed" | "AfterInitialDemand"), v -> check is_bool v
                  | ("PathState" | "OtherJobEnabled" | "OtherJobActive"), `Assoc pairs ->
                      List.fold_left (fun any (name, v) ->
                        let valid = check (fun v -> name <> "" && is_bool v) v in any || valid) false pairs
                  | _ -> invalid () in
                if valid then n + 1 else n) 0 values > 0
          | _ -> invalid () in
        let calendar = function
          | `Assoc values ->
              let fields = ["Minute", 0, 59; "Hour", 0, 23; "Day", 1, 31; "Month", 1, 12; "Weekday", 0, 7] in
              let valid = ref (List.for_all (fun (k, _) -> List.exists (fun (name, _, _) -> name = k) fields) values) in
              let parts = List.map (fun (key, lo, hi) -> match List.assoc_opt key values with
                | None -> "*"
                | Some (`Int n) when n >= lo && n <= hi -> string_of_int n
                | _ -> valid := false; "*") fields in
              if !valid then Some (String.concat " " parts) else (ignore (invalid ()); None)
          | _ -> ignore (invalid ()); None in
        let handle key f = Option.iter f (List.assoc_opt key entries) in
        handle "RunAtLoad" (bool "load");
        handle "KeepAlive" (function
          | `Bool value -> if value then add "keepalive"
          | value -> if conditions value then add "keepalive(cond)");
        handle "StartInterval" (function
          | `Int n when n > 0 -> add (Printf.sprintf "every %ds" n)
          | _ -> ignore (invalid ()));
        handle "StartCalendarInterval" (fun value ->
          let values = match value with `List vs -> vs | v -> [v] in
          let schedules = List.filter_map calendar values in
          if schedules <> [] then add ("calendar(" ^ String.concat ";" schedules ^ ")"));
        handle "WatchPaths" (paths "watch");
        handle "QueueDirectories" (paths "queue");
        handle "StartOnMount" (bool "mount");
        handle "MachServices" (function
          | `Assoc values -> count "mach" (List.fold_left (fun n (name, v) ->
              match v with
              | `Bool false -> n
              | `Bool true | `Assoc _ when name <> "" -> n + 1
              | _ -> ignore (invalid ()); n) 0 values)
          | _ -> ignore (invalid ()));
        handle "Sockets" (function
          | `Assoc values -> count "socket" (List.fold_left (fun n (name, v) ->
              let valid = match v with
                | `Assoc _ -> true
                | `List vs -> valid_count is_dict vs > 0
                | _ -> invalid () in
              if name = "" then (ignore (invalid ()); n) else if valid then n + 1 else n) 0 values)
          | _ -> ignore (invalid ()));
        handle "LaunchEvents" (function
          | `Assoc systems -> count "event" (List.fold_left (fun n (name, v) -> match v with
              | `Assoc events when name <> "" -> n + valid_count (fun (key, v) -> key <> "" && is_dict v) events
              | _ -> ignore (invalid ()); n) 0 systems)
          | _ -> ignore (invalid ()));
        let summary = match List.rev !tokens, !bad with
          | [], true -> None
          | [], false -> Some "plist:none-known"
          | ts, bad -> Some ("plist:" ^ String.concat "," (if bad then ts @ ["unknown"] else ts)) in
        summary, !bad
    | _ -> None, true
  with Yojson.Json_error _ -> None, true

let fields line =
  String.split_on_char ' ' (String.map (function '\t' | '\r' -> ' ' | c -> c) line)
  |> List.filter (fun s -> s <> "")

let decimal text =
  let digits =
    if String.length text > 0 && (text.[0] = '-' || text.[0] = '+') then
      String.sub text 1 (String.length text - 1)
    else text
  in
  if digits <> "" && String.for_all (fun c -> c >= '0' && c <= '9') digits
  then int_of_string_opt text else None

let parse text =
  match String.split_on_char '\n' text with
  | header :: lines when fields header = ["PID"; "Status"; "Label"] ->
      let rec rows number acc = function
        | [] -> Ok (List.rev acc)
        | line :: rest ->
            let invalid () = Error (Printf.sprintf "Invalid launchctl row at line %d" number) in
            match fields line with
            | [] -> rows (number + 1) acc rest
            | [pid; status; label] ->
                let parsed_pid = if pid = "-" then Some None else
                  match decimal pid with Some n when n > 0 -> Some (Some n) | _ -> None in
                (match parsed_pid, decimal status with
                 | Some pid, Some status -> rows (number + 1) ({label; pid; status; details = empty_details} :: acc) rest
                 | _ -> invalid ())
            | _ -> invalid ()
      in
      rows 2 [] lines
  | _ -> Error "Invalid launchctl header"

let parse_details text =
  let details = ref empty_details and malformed = ref false in
  let exit_seen = ref false in
  let log_paths_seen = ref [] in
  let is_log_path key = key = "stdout path" || key = "stderr path" in
  let set_field key value =
    let value_opt () = if value = "" then (malformed := true; None) else Some value in
    match key with
    | "state" -> details := {!details with state = value_opt ()}
    | "program" -> details := {!details with program = value_opt ()}
    | "stdout path" -> details := {!details with stdout_path = value_opt ()}
    | "stderr path" -> details := {!details with stderr_path = value_opt ()}
    | "path" ->
        let path = if String.starts_with ~prefix:"(submitted by " value then None else value_opt () in
        details := {!details with path}
    | "last exit code" ->
        let exit = if !exit_seen then (malformed := true; Unknown)
          else if value = "(never exited)" then Never else
          match decimal value with
          | Some code -> Code code
          | None -> malformed := true; Unknown in
        exit_seen := true;
        details := {!details with exit}
    | _ -> () in
  (* launchctl print uses tab indentation; braces inside argument values are data. *)
  let rec block acc = function
    | "\t}" :: rest -> Some (List.rev acc), rest
    | line :: rest when String.starts_with ~prefix:"\t\t" line ->
        block (String.sub line 2 (String.length line - 2) :: acc) rest
    | "" :: rest -> block acc rest
    | rest -> malformed := true; None, rest in
  let rec body = function
    | [] -> malformed := true
    | "}" :: rest ->
        if List.exists (fun line -> String.trim line <> "") rest then malformed := true
    | "" :: rest -> body rest
    | line :: rest when String.starts_with ~prefix:"\t" line
                        && not (String.starts_with ~prefix:"\t\t" line) ->
        let field = String.sub line 1 (String.length line - 1) in
        let key = match String.index_opt field '=' with
          | Some index -> String.trim (String.sub field 0 index)
          | None -> String.trim field in
        if is_log_path key then (
          if List.mem key !log_paths_seen then malformed := true;
          log_paths_seen := key :: !log_paths_seen);
        (match String.index_opt field '=' with
         | Some index when index + 1 < String.length field && field.[index + 1] = ' ' ->
             let value = String.sub field (index + 2) (String.length field - index - 2) in
             if value = "{" then (
               if is_log_path key then malformed := true;
               let values, rest = block [] rest in
               if key = "arguments" then
                 details := {!details with arguments = Option.value ~default:[] values};
               body rest)
             else (set_field key value; body rest)
         | _ -> if is_log_path key then malformed := true; body rest)
    | _ :: rest -> malformed := true; body rest in
  (match String.split_on_char '\n' text with
   | header :: rest when String.ends_with ~suffix:" = {" header -> body rest
   | _ -> malformed := true);
  !details, !malformed

let visible rows =
  List.filter (fun row -> not (String.starts_with ~prefix:"com.apple." row.label)) rows
  |> List.sort (fun a b -> String.compare a.label b.label)

let escape text =
  let buffer = Buffer.create (String.length text) in
  String.iter (function
    | '\n' -> Buffer.add_string buffer "\\n"
    | '\r' -> Buffer.add_string buffer "\\r"
    | '\t' -> Buffer.add_string buffer "\\t"
    | '\\' -> Buffer.add_string buffer "\\\\"
    | '"' -> Buffer.add_string buffer "\\\""
    | c when Char.code c < 32 || Char.code c = 127 -> Printf.bprintf buffer "\\x%02x" (Char.code c)
    | c -> Buffer.add_char buffer c) text;
  Buffer.contents buffer

let text_length text =
  String.fold_left (fun n c -> if Char.code c land 0xc0 = 0x80 then n else n + 1) 0 text

let shorten ~from_left width text =
  let length = text_length text in
  if length <= width then text else
  let rec prefix offset remaining =
    if remaining = 0 then offset else
    prefix (offset + Uchar.utf_decode_length (String.get_utf_8_uchar text offset)) (remaining - 1) in
  if from_left then
    let offset = prefix 0 (length - width + 3) in
    "..." ^ String.sub text offset (String.length text - offset)
  else String.sub text 0 (prefix 0 (width - 3)) ^ "..."

let service_name row =
  if String.starts_with ~prefix:"application." row.label then
    let app = match row.details.program with
      | None -> None
      | Some program ->
          Filename.dirname program |> String.split_on_char '/' |> List.rev
          |> List.find_opt (fun part -> String.length part > 4 && String.ends_with ~suffix:".app" part) in
    match app with
    | Some app -> String.sub app 0 (String.length app - 4)
    | None -> row.label
  else
    match List.find_opt (fun prefix -> String.starts_with ~prefix row.label
      && String.length row.label > String.length prefix) ["com."; "org."; "us."] with
    | None -> row.label
    | Some prefix -> String.sub row.label (String.length prefix) (String.length row.label - String.length prefix)

let named_services rows =
  let names = List.map (fun row -> row, shorten ~from_left:true 40 (escape (service_name row))) rows in
  List.map (fun (row, name) ->
    let others = List.filter (fun (other, other_name) -> other_name = name && other.label <> row.label) names in
    if others = [] then row, name else
    let suffixes = List.fold_right (fun part acc ->
      (match acc with [] -> part | suffix :: _ -> part ^ "." ^ suffix) :: acc)
      (String.split_on_char '.' row.label) [] |> List.rev in
    let suffix = List.find_opt (fun suffix ->
      not (List.exists (fun (other, _) -> other.label = suffix
        || String.ends_with ~suffix:("." ^ suffix) other.label) others)) suffixes
      |> Option.value ~default:row.label in
    row, name ^ " [" ^ escape suffix ^ "]") names

let render rows =
  let rows = List.filter (fun row -> Option.is_some row.details.triggers) rows in
  let cells = ["Service"; "PID"; "State"; "Exit"; "Triggers"; "Reason"] ::
    List.map (fun (row, name) ->
      [name;
       (match row.pid with None -> "—" | Some pid -> string_of_int pid);
       shorten ~from_left:false 16 (Option.fold ~none:"unknown" ~some:escape row.details.state);
       (match last_exit row with Code code -> string_of_int code | Never -> "never" | Unknown -> "unknown");
       shorten ~from_left:false 32 (Option.fold ~none:"unknown" ~some:escape row.details.triggers);
       shorten ~from_left:false 40 (Option.fold ~none:"unknown" ~some:escape row.details.reason)])
      (named_services (visible rows)) in
  let widths = Array.make 6 0 in
  List.iter (List.iteri (fun i text -> widths.(i) <- max widths.(i) (text_length text))) cells;
  List.map (fun row ->
    List.mapi (fun i text ->
      let padding = String.make (widths.(i) - text_length text) ' ' in
      if i = 1 then padding ^ text else if i = 5 then text else text ^ padding) row
    |> String.concat "  ") cells
  |> String.concat "\n"
  |> fun text -> text ^ "\n"

let resolve_domain ~euid runner =
  if euid = 0 then Ok "system" else
  match runner ["managername"] with
  | Error message -> Error message
  | Ok name ->
      match String.trim name with
      | "System" -> Ok "system"
      | ("Aqua" | "Background") as name ->
          (match runner ["manageruid"] with
           | Error message -> Error message
           | Ok uid ->
               match decimal (String.trim uid) with
               | Some uid when uid >= 0 ->
                   Ok (Printf.sprintf "%s/%d" (if name = "Aqua" then "gui" else "user") uid)
               | _ -> Error "Invalid launchctl manager UID")
      | _ -> Error "Unsupported launchctl manager"

let discover_logs ~euid ~label runner =
  Result.bind (resolve_domain ~euid runner) (fun domain ->
    Result.bind (runner ["print"; domain ^ "/" ^ label]) (fun output ->
      let details, malformed = parse_details output in
      if malformed then Error "Unrecognized launchctl details" else Ok details))

let collect ?(read_source = fun _ -> Error "Source reader unavailable") ~euid ~warn runner =
  match runner ["list"] with
  | Error message -> Error message
  | Ok output ->
      match parse output with
      | Error message -> Error message
      | Ok rows ->
          let rows = visible rows in
          if rows = [] then Ok [] else
          match resolve_domain ~euid runner with
          | Error message -> warn ("context: " ^ message); Ok rows
          | Ok domain ->
              Ok (List.map (fun row ->
                let details = match runner ["print"; domain ^ "/" ^ row.label] with
                | Error message -> warn (row.label ^ ": " ^ message); empty_details
                | Ok output ->
                    let details, malformed = parse_details output in
                    if malformed then warn (row.label ^ ": Unrecognized launchctl details");
                    let triggers = match details.path with
                      | None -> None
                      | Some path when Filename.is_relative path || String.contains path '\000' ->
                          warn (row.label ^ ": plist: Invalid source path"); None
                      | Some path ->
                          (match read_source path with
                           | Error message -> warn (row.label ^ ": plist: " ^ message); None
                           | Ok json ->
                               let triggers, bad = parse_triggers ~label:row.label json in
                               if bad then warn (row.label ^ ": plist: Invalid source configuration");
                               triggers) in
                    {details with triggers} in
                let reason = match row.pid with
                  | None -> None
                  | Some _ ->
                      (match runner ["blame"; domain ^ "/" ^ row.label] with
                       | Ok output when String.trim output <> "" -> Some (String.trim output)
                       | result ->
                           let message = match result with Error e -> e | Ok _ -> "Empty response" in
                           warn (row.label ^ ": blame: " ^ message); None) in
                {row with details = {details with reason}}) rows)

let execute ?(quiet = false) ?(stdin = Unix.stdin) program argv =
  let name = Filename.basename program in
  try
    let read_fd, write_fd = Unix.pipe ~cloexec:true () in
    let channel = Unix.in_channel_of_descr read_fd in
    Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
      let pid = Fun.protect ~finally:(fun () -> Unix.close write_fd) (fun () ->
        if quiet then
          let null = Unix.openfile "/dev/null" [Unix.O_WRONLY; Unix.O_CLOEXEC] 0 in
          Fun.protect ~finally:(fun () -> Unix.close null)
            (fun () -> Unix.create_process program argv stdin write_fd null)
        else Unix.create_process program argv stdin write_fd Unix.stderr) in
      let status = ref (Unix.WEXITED 1) in
      let output = Fun.protect
        ~finally:(fun () -> status := snd (Unix.waitpid [] pid))
        (fun () -> In_channel.input_all channel) in
      match !status with
      | Unix.WEXITED 0 -> Ok output
      | Unix.WEXITED code -> Error (Printf.sprintf "%s exited with status %d" name code)
      | Unix.WSIGNALED signal | Unix.WSTOPPED signal ->
          Error (Printf.sprintf "%s terminated by signal %d" name signal))
  with
  | Unix.Unix_error (error, operation, _) ->
      Error (Printf.sprintf "%s: %s: %s" name operation (Unix.error_message error))
  | Sys_error message -> Error (name ^ ": " ^ message)

let read_log path =
  if Filename.is_relative path || String.contains path '\000' then Error "Invalid log path"
  else try
    let fd = Unix.openfile path [Unix.O_RDONLY; Unix.O_NONBLOCK; Unix.O_CLOEXEC] 0 in
    Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
      if (Unix.fstat fd).Unix.st_kind <> Unix.S_REG then Error "Not a regular file"
      else execute ~quiet:true ~stdin:fd "/usr/bin/tail" [|"tail"; "-n"; "200"|])
  with Unix.Unix_error (error, operation, _) ->
    Error (operation ^ ": " ^ Unix.error_message error)

let log_snapshot ~read_source details =
  let sources = match details.stdout_path, details.stderr_path with
    | Some out, Some err when out = err -> ["stdout/stderr", out]
    | out, err -> List.filter_map Fun.id
        [Option.map (fun path -> "stdout", path) out;
         Option.map (fun path -> "stderr", path) err] in
  if sources = [] then "File logs are not configured.\n", [] else
  let output = Buffer.create 1024 and errors = ref [] in
  List.iter (fun (stream, path) ->
    match read_source path with
    | Error message -> errors := escape (stream ^ ": " ^ path ^ ": " ^ message) :: !errors
    | Ok text ->
        let size = Buffer.length output in
        if size > 0 && Buffer.nth output (size - 1) <> '\n' then Buffer.add_char output '\n';
        Buffer.add_string output ("==> " ^ stream ^ ": " ^ escape path ^ " <==\n");
        Buffer.add_string output text) sources;
  Buffer.contents output, List.rev !errors

let read_plist path =
  if Filename.is_relative path || String.contains path '\000' then Error "Invalid source path"
  else execute ~quiet:true "/usr/bin/plutil" [|"plutil"; "-convert"; "json"; "-o"; "-"; path|]

let run program =
  let runner args = execute ~quiet:(args <> ["list"]) program (Array.of_list ("launchctl" :: args)) in
  collect ~read_source:read_plist ~euid:(Unix.geteuid ()) ~warn:(fun message -> prerr_endline ("ldtop: " ^ escape message)) runner
  |> Result.map render
