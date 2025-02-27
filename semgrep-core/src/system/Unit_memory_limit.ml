(*
   Unit tests for out-of-memory errors and stack overflows.

   System's maximum stack size is assumed to be 8 MiB or greater.
   See mli.
*)

open Printf
open OUnit

let get_stack_size_in_bytes () =
  (Gc.quick_stat ()).stack_size * (Sys.word_size / 8)

let get_heap_size_in_bytes () =
  (Gc.quick_stat ()).heap_words * (Sys.word_size / 8)

(*
   This is to show how often the GC alarms run.
*)
let with_debug_alarm f =
  let alarm = Gc.create_alarm (fun () -> printf "Running GC alarm.\n%!") in
  Fun.protect f ~finally:(fun () -> Gc.delete_alarm alarm)

(*
   Grow the stack until some limit expressed in bytes.
*)
let grow_stack goal_bytes =
  let rec aux () =
    let stack_size = get_stack_size_in_bytes () in
    if stack_size < goal_bytes then
      (* Allocate enough to trigger GC alarms regularly, before making
         the recursive call. *)
      let data = List.init 100 (fun _ -> ()) in
      (* Prevent tail-call optimization *)
      data :: aux ()
    else (
      (* Trigger the hook that will run the GC alarm. This is cheating. *)
      (*Gc.full_major ();*)
      printf "grow_stack: stack reached %i bytes\n%!" stack_size;
      [])
  in
  with_debug_alarm (fun () -> aux () |> ignore)

let grow_heap goal_bytes =
  let rec aux acc =
    let heap_size = get_heap_size_in_bytes () in
    if heap_size < goal_bytes then aux (42 :: acc)
    else printf "grow_heap: heap reached %i bytes\n%!" heap_size
  in
  aux []

(*
   This test should print a warning.
   TODO: capture the output and check that the warning is there.
*)
let test_stack_warning () =
  Memory_limit.run_with_memory_limit ~stack_warning_kb:100 ~mem_limit_mb:0
    (fun () -> grow_stack 3_000_000)

let test_memory_limit_with_heap () =
  try
    Memory_limit.run_with_memory_limit ~mem_limit_mb:10 (fun () ->
        (* note that the GC alarm may not trigger until we allocate
         * significantly more memory than 10MB. *)
        grow_heap 20_000_000);
    assert false
  with Out_of_memory -> (* success *) ()

let test_memory_limit_with_stack () =
  try
    Memory_limit.run_with_memory_limit ~mem_limit_mb:1 (fun () ->
        grow_stack 1_500_000);
    assert false
  with Out_of_memory -> (* success *) ()

let unittest =
  "memory limits"
  >::: [
         "stack warning" >:: test_stack_warning;
         "memory limit (heap)" >:: test_memory_limit_with_heap;
         "memory limit (stack)" >:: test_memory_limit_with_stack;
       ]
