open Service_listing

let response fields = "gui/501/example = {\n" ^ fields ^ "}\n"

let () =
  (* Empty configured paths must not look like absent configuration. *)
  let _, bad = parse_details (response "\tstdout path = \n") in
  assert bad;
  List.iter (fun (fields, out, err) ->
    let details, bad = parse_details (response fields) in
    assert (not bad);
    assert (details.stdout_path = out && details.stderr_path = err)) [
    "\tstdout path = /tmp/a b\n\tstderr path = /tmp/err\n", Some "/tmp/a b", Some "/tmp/err";
    "\tstderr path = /tmp/err\n", None, Some "/tmp/err";
    "\tstate = not running\n", None, None;
    "\tenvironment = {\n\t\tstdout path = /wrong\n\t}\n", None, None
  ];
  List.iter (fun text -> assert (snd (parse_details text)))
    [response "\tstderr path = \n"; "gui/501/example = {\n\tstdout path = /tmp/a\n";
     response "\tstdout path = {\n\t}\n";
     response "\tstdout path =/tmp/a\n";
     response "\tstderr path = /tmp/a\n\tstderr path = /tmp/b\n"]

let () =
  List.iter (fun (euid, manager, domain, label) ->
    let calls = ref [] in
    let runner args =
      calls := !calls @ [args];
      match args with
      | ["managername"] -> Ok manager
      | ["manageruid"] -> Ok "501\n"
      | ["print"; target] when target = domain ^ "/" ^ label ->
          Ok (response "\tstate = not running\n\tstdout path = /tmp/log\n")
      | _ -> failwith "Unexpected query during log discovery" in
    (match discover_logs ~euid ~label runner with
     | Ok details -> assert (details.stdout_path = Some "/tmp/log")
     | Error message -> failwith message);
    let expected = if euid = 0 then [] else [["managername"]; ["manageruid"]] in
    assert (!calls = expected @ [["print"; domain ^ "/" ^ label]]))
    [501, "Aqua\n", "gui/501", "com.apple.hidden";
     501, "Background\n", "user/501", "unknown.triggers";
     0, "System\n", "system", "example"];
  let calls = ref [] in
  let fail_context args = calls := args :: !calls; Error "unavailable" in
  assert (Result.is_error (discover_logs ~euid:501 ~label:"example" fail_context));
  assert (!calls = [["managername"]]);
  List.iter (fun output ->
    let runner = function ["print"; "system/example"] -> output | _ -> assert false in
    assert (Result.is_error (discover_logs ~euid:0 ~label:"example" runner)))
    [Error "service not found"; Ok "unexpected"; Ok (response "\tstderr path = \n")]

let () =
  let path = Filename.temp_file "ldtop log ; " ".txt" in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    List.iter (fun count ->
      let lines = List.init count (fun i -> string_of_int (i + 1)) in
      List.iter (fun terminated ->
        let content = String.concat "\n" lines ^ (if terminated && count > 0 then "\n" else "") in
        Out_channel.with_open_bin path (fun ch -> output_string ch content);
        match read_log path with
        | Error message -> failwith message
        | Ok output ->
            let result = String.split_on_char '\n' output in
            let result = if terminated && count > 0 then List.rev (List.tl (List.rev result)) else result in
            if count = 0 then assert (output = "") else (
              assert (List.length result = min count 200);
              assert (List.hd result = (if count = 250 then "51" else "1"));
              assert (List.hd (List.rev result) = string_of_int count);
              if count <= 200 then assert (output = content))) [false; true]) [0; 3; 200; 250]);
  List.iter (fun path -> assert (Result.is_error (read_log path)))
    ["relative"; "/bad\000path"; path; Filename.get_temp_dir_name (); "/dev/null"];
  let fifo = Filename.temp_file "ldtop-fifo" "" in
  Sys.remove fifo;
  Unix.mkfifo fifo 0o600;
  Fun.protect ~finally:(fun () -> Sys.remove fifo) (fun () ->
    assert (Result.is_error (read_log fifo)))

let () =
  let snapshot out err =
    let calls = ref [] in
    let read_source path =
      calls := !calls @ [path];
      match path with
      | "/out" -> Ok "hello\027[31m\n"
      | "/err" -> Ok "unfinished"
      | "/empty" -> Ok ""
      | "/bad\npath" -> Error "Permission denied\027"
      | _ -> Error "Read failure" in
    let output, errors = log_snapshot ~read_source
      {empty_details with stdout_path = out; stderr_path = err} in
    output, errors, !calls in
  assert (snapshot (Some "/out") (Some "/out") =
    ("==> stdout/stderr: /out <==\nhello\027[31m\n", [], ["/out"]));
  assert (snapshot (Some "/err") (Some "/out") =
    ("==> stdout: /err <==\nunfinished\n==> stderr: /out <==\nhello\027[31m\n", [], ["/err"; "/out"]));
  assert (snapshot None (Some "/err") = ("==> stderr: /err <==\nunfinished", [], ["/err"]));
  assert (snapshot (Some "/empty") None = ("==> stdout: /empty <==\n", [], ["/empty"]));
  assert (snapshot None None = ("File logs are not configured.\n", [], []));
  let output, errors, calls = snapshot (Some "/out") (Some "/bad\npath") in
  assert (output = "==> stdout: /out <==\nhello\027[31m\n");
  assert (calls = ["/out"; "/bad\npath"]);
  assert (List.length errors = 1);
  assert (not (String.contains (List.hd errors) '\n' || String.contains (List.hd errors) '\027'));
  let output, errors, _ = snapshot (Some "/bad") (Some "/out") in
  assert (output = "==> stderr: /out <==\nhello\027[31m\n" && List.length errors = 1);
  let output, errors = log_snapshot ~read_source:(fun _ -> Ok "raw\tcontent")
    {empty_details with stdout_path = Some "/with\nnewline"} in
  assert (output = "==> stdout: /with\\nnewline <==\nraw\tcontent" && errors = [])
