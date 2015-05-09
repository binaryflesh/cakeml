open HolKernel Parse boolLib bossLib;

open wordsTheory asmTheory llistTheory ffiTheory;

val _ = new_theory "machine_traces";

val () = Datatype `
  trace_part =
      Internal_step_from 'a
    | FFI_call 'a num (word8 list) (word8 list)`

val _ = temp_type_abbrev("machine_trace",``:('a trace_part) llist``);

val has_array_def = Define `
  (has_array s a [] <=> T) /\
  (has_array s a (b::bs) <=>
     a IN s.mem_domain /\ (s.mem a = b) /\ has_array s (a+1w) bs)`;

val set_pc_def = Define `
  set_pc w s = s with pc := w`;

val write_array_def = Define `
  (write_array a [] s = s) /\
  (write_array a (b::bs) s =
     write_array (a + 1w) bs s with mem := (a =+ b) s.mem)`

val is_FFI_def = Define `
  (is_FFI (FFI_call _ _ _ _) = T) /\
  (is_FFI _ = F)`

val get_state_def = Define `
  (get_state (FFI_call s _ _ _) = s) /\
  (get_state (Internal_step_from s) = s)`;

val () = Datatype `
  ffi_config =
    <| link_reg : num ;
       arg_reg : num ;
       ffi_entry_pc : ('a word) list |>`

val () = Datatype `
  trace_config =
    <| next : 'a -> 'a ;
       proj : 'a -> 'b ;
       ffi_conf : 'c ffi_config ;
       asm_machine_rel : 'd asm_state -> 'a -> bool |>`

val trace_ok_def = Define `
  trace_ok c init_state (t:'a machine_trace) <=>
    (* every machine state relates to some asm_state *)
    (!i p. (LNTH i t = SOME p) ==> ?x. c.asm_machine_rel x (get_state p)) /\
    (* first state must be the init state *)
    (?p. (LNTH 0 t = SOME p) /\ (get_state p = init_state)) /\
    (* consequtive states are related by the machine next-state
       functions, but may differ arbitrarily on non-projected parts *)
    (!n s1 p.
       (LNTH n t = SOME (Internal_step_from s1)) /\
       (LNTH (n+1) t = SOME p) ==>
       (c.proj (c.next s1) = c.proj (get_state p))) /\
    (* entry into FFI passes pointer to array correctly etc. *)
    (!n s1 k w1 w2 x1.
       (LNTH n t = SOME (FFI_call s1 k w1 w2)) /\ c.asm_machine_rel x1 s1 ==>
       k < LENGTH c.ffi_conf.ffi_entry_pc /\
       (x1.pc = EL k c.ffi_conf.ffi_entry_pc) /\
       has_array x1 (x1.regs c.ffi_conf.arg_reg) w1) /\
    (* how returning FFI call updates states *)
    (!n s1 p k w1 w2 x1 x2.
       (LNTH n t = SOME (FFI_call s1 k w1 w2)) /\ c.asm_machine_rel x1 s1 /\
       (LNTH (n+1) t = SOME p) /\ c.asm_machine_rel x2 (get_state p) ==>
       (LENGTH w1 = LENGTH w2) /\
       (x2 = write_array (x1.regs c.ffi_conf.arg_reg) w2
               (set_pc (x1.regs c.ffi_conf.link_reg) x1)))`

val dest_FFI_call_def = Define `
  (dest_FFI_call (FFI_call _ n w1 w2) = SOME (IO_event n (ZIP (w1,w2)))) /\
  (dest_FFI_call _ = NONE)`

val MAP_FILTER_def = Define `
  MAP_FILTER f xs = MAP (THE o f) (FILTER (IS_SOME o f) xs)`;

val toSeq_def = Define `
  toSeq ll i = THE (LNTH i ll)`;

val mc_sem_def = Define `
  (mc_sem c init_state (Terminate fin_io_trace) <=>
     ?t ts.
       trace_ok c init_state t /\
       (!s n w1 w2. ts <> [] ==> LAST ts <> FFI_call s n w1 w2) /\
       (toList t = SOME ts) /\
       (fin_io_trace = MAP_FILTER dest_FFI_call ts)) /\
  (mc_sem c init_state (TerminateExt fin_io_trace n w1) <=>
     ?t ts s w2.
       trace_ok c init_state t /\
       (toList t = SOME ts) /\
       (fin_io_trace = MAP_FILTER dest_FFI_call ts) /\
       ts <> [] /\
       (LAST ts = FFI_call s n w1 w2)) /\
  (mc_sem c init_state (Diverge fin_io_trace) <=>
     ?t ts.
       trace_ok c init_state t /\ ~(LFINITE t) /\
       (toList (LFILTER (IS_SOME o dest_FFI_call) t) = SOME ts) /\
       (fin_io_trace = MAP (THE o dest_FFI_call) ts)) /\
  (mc_sem c init_state (DivergeInf inf_io_trace) <=>
     ?t.
       trace_ok c init_state t /\ ~(LFINITE t) /\
       (toSeq (LMAP (THE o dest_FFI_call)
          (LFILTER (IS_SOME o dest_FFI_call) t)) =
        inf_io_trace))`

val _ = export_theory();
