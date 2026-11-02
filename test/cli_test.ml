let run args =
  let program = Sys.argv.(1) in
  let channels = Unix.open_process_args_full program
    (Array.of_list (program :: args)) (Unix.environment ()) in
  let stdout, _, stderr = channels in
  let output = In_channel.input_all stdout in
  let error = In_channel.input_all stderr in
  let status = Unix.close_process_full channels in
  status, output, error

let () =
  List.iter (fun option ->
    let status, output, error = run [option] in
    assert (status = Unix.WEXITED 0);
    assert (String.split_on_char '\n' output |> List.exists (fun line -> line = "Usage: ldtop ls"));
    assert (String.split_on_char '\n' output |> List.mem "       ldtop log <label>");
    assert (String.split_on_char '\n' output |> List.mem "Services with Triggers=unknown are always hidden.");
    List.iter (fun word -> assert (String.split_on_char ' ' (String.map (function '\n' -> ' ' | c -> c) output)
      |> List.mem word)) ["Triggers:"; "Reason:"; "plist:"; "diagnostic"; "stopped"];
    assert (error = "")) ["--help"; "-help"];
  List.iter (fun args ->
    let status, output, error = run args in
    assert (status = Unix.WEXITED 2);
    assert (output = "");
    assert (error <> "")) [[]; ["list"]; ["unknown"]; ["ls"; "extra"]; ["--unknown"]; ["ls"; "--all"];
      ["log"]; ["logs"; "example"]; ["log"; ""]; ["log"; "gui/501/example"];
      ["log"; "example"; "extra"]; ["log"; "example"; "-f"]; ["log"; "--unknown"]];
  let status, output, error = run ["log"; "local.ldtop-test.definitely-not-installed"] in
  assert (status = Unix.WEXITED 1 && output = "" && error <> "")
