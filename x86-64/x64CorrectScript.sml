open HolKernel boolLib bossLib helperLib pairTheory lcsymtacs
open ml_translatorTheory sideTheory replDecsTheory replDecsProofsTheory compileCallReplStepDecTheory

val _ = new_theory "x64Correct"

infix \\ val op \\ = op THEN;

val _ = Globals.max_print_depth := 20

(* --- repl_step --- *)


(*
val DeclAssumExists_SNOC_Dlet_Fun = store_thm("DeclAssumExists_SNOC_Dlet_Fun",
val DeclAssumExists_SNOC_Dlet = store_thm("DeclAssumExists_SNOC_Dlet",
*)

val DeclAssumExists_ml_repl_step_decls = prove(
  ``DeclAssumExists ml_repl_step_decls``,
  MP_TAC ml_repl_stepTheory.ml_repl_step_translator_state_thm
  \\ REWRITE_TAC [markerTheory.Abbrev_def,TAG_def,AND_IMP_INTRO]
  \\ STRIP_TAC
  \\ Q.PAT_ASSUM `pp ==> DeclAssumExists xxx` MP_TAC
  \\ REPEAT (POP_ASSUM (K ALL_TAC))
  \\ REPEAT STRIP_TAC
  \\ POP_ASSUM MATCH_MP_TAC
  \\ FULL_SIMP_TAC std_ss [PRECONDITION_def]
  \\ STRIP_TAC THEN1
   (MP_TAC sideTheory.repl_step_side_thm
    \\ FULL_SIMP_TAC std_ss [ml_repl_stepTheory.repl_step_side_def])
  \\ cheat (* EqualityType (GRAMMAR_PARSETREE_TYPE ...) *) )

val SNOC3 = prove(
   ``xs ++ [x3;x2;x1] = SNOC x1 (SNOC x2 (SNOC x3 xs))``,
  SRW_TAC [] []);

val DeclAssumExists_repl_decs = prove(
  ``DeclAssumExists repl_decs``,
  SIMP_TAC std_ss [replDecsTheory.repl_decs_def,SNOC3]
  \\ MATCH_MP_TAC DeclAssumExists_SNOC_Dlet_Fun
  \\ MATCH_MP_TAC (MP_CANON DeclAssumExists_SNOC_Dlet_ALT)
  \\ SIMP_TAC std_ss [Eval_def]
  \\ SIMP_TAC (srw_ss()) [Once AltBigStepTheory.evaluate'_cases]
  \\ SIMP_TAC (srw_ss()) [Once AltBigStepTheory.evaluate'_cases]
  \\ SIMP_TAC (srw_ss()) [SemanticPrimitivesTheory.do_uapp_def,LET_DEF,
                          SemanticPrimitivesTheory.store_alloc_def]
  \\ MATCH_MP_TAC (MP_CANON DeclAssumExists_SNOC_Dlet_ALT)
  \\ SIMP_TAC std_ss [Eval_def]
  \\ SIMP_TAC (srw_ss()) [Once AltBigStepTheory.evaluate'_cases]
  \\ SIMP_TAC (srw_ss()) [Once AltBigStepTheory.evaluate'_cases]
  \\ SIMP_TAC (srw_ss()) [SemanticPrimitivesTheory.do_uapp_def,LET_DEF,
                          SemanticPrimitivesTheory.store_alloc_def]
  \\ SIMP_TAC (srw_ss()) [Once AltBigStepTheory.evaluate'_cases]
  \\ SIMP_TAC std_ss [DeclAssumExists_ml_repl_step_decls]);

val check_ctors_decs_ml_repl_step_decls = prove(
  ``check_ctors_decs NONE init_envC ml_repl_step_decls``,
  MP_TAC ml_repl_stepTheory.ml_repl_step_translator_state_thm
  \\ REWRITE_TAC [markerTheory.Abbrev_def,TAG_def,AND_IMP_INTRO]
  \\ STRIP_TAC);

val decs_to_cenv_ml_repl_step_decls = let
  val pat = ``decs_to_cenv NONE ml_repl_step_decls = xxx``
  in ml_repl_stepTheory.ml_repl_step_translator_state_thm
     |> RW [markerTheory.Abbrev_def,TAG_def]
     |> CONJUNCTS
     |> filter (fn th => can (match_term pat) (concl th)) |> hd end

val check_ctors_decs_repl_decs = prove(
  ``check_ctors_decs NONE init_envC repl_decs``,
  SIMP_TAC std_ss [replDecsTheory.repl_decs_def,SNOC3]
  \\ MATCH_MP_TAC (MP_CANON IMP_check_ctors_decs_SNOC)
  \\ REVERSE STRIP_TAC THEN1 EVAL_TAC
  \\ MATCH_MP_TAC (MP_CANON IMP_check_ctors_decs_SNOC)
  \\ REVERSE STRIP_TAC THEN1 EVAL_TAC
  \\ MATCH_MP_TAC (MP_CANON IMP_check_ctors_decs_SNOC)
  \\ SIMP_TAC std_ss [check_ctors_decs_ml_repl_step_decls]
  \\ EVAL_TAC
  \\ REWRITE_TAC [decs_to_cenv_ml_repl_step_decls]
  \\ EVAL_TAC);

val repl_decs_lemma = prove(
  ``(FV_decs repl_decs = ∅) ∧
    (decs_cns NONE repl_decs = ∅) ∧
    (∀i tds.
        i < LENGTH repl_decs ∧
        (EL i repl_decs = Dtype tds) ⇒
        check_dup_ctors NONE
          (decs_to_cenv NONE (TAKE i repl_decs) ++ init_envC)
          tds) ∧
    (∀i cn ts.
        i < LENGTH repl_decs ∧
        (EL i repl_decs = Dexn cn ts) ⇒
        mk_id NONE cn ∉
        set
          (MAP FST
             (decs_to_cenv NONE (TAKE i repl_decs) ++
              init_envC)))``,
  cheat (* translator should do this? *));

val evaluate_decs_repl_decs = let
  val th = DeclAssumC_thm
           |> RW [GSYM AND_IMP_INTRO]
  val th = MATCH_MP th check_ctors_decs_repl_decs
  val th = prove(``?cenv env. DeclAssumC repl_decs cenv env``,
                 METIS_TAC [DeclAssumExists_repl_decs,th,DeclAssumExists_def])
           |> RW [DeclAssumC_def,DeclsC_def]
  in th end

val repl_decs_cenv_env_s_def = new_specification("repl_decs_cenv_env_s_def",
  ["repl_decs_cenv","repl_decs_env","repl_decs_s"],
  evaluate_decs_repl_decs)

val compile_term_def = Define `
  compile_term = (compile_decs NONE FEMPTY init_compiler_state.contab
          <|bvars := []; mvars := FEMPTY;
            cnmap := cmap init_compiler_state.contab|> [] 0
          <|out := []; next_label := init_compiler_state.rnext_label|>
          repl_decs)`;

val new_compiler_state_def = Define `
  new_compiler_state =
    (init_compiler_state with
            <|contab := FST compile_term;
              renv :=
                ZIP
                  ((FST (SND compile_term)).bvars,
                   REVERSE (GENLIST I (FST (SND (SND compile_term)))));
              rsz := FST (SND (SND compile_term));
              rnext_label :=
                (SND (SND (SND compile_term))).next_label|>)`;

val compile_decs_bc_eval = let
  val th = replDecsProofsTheory.compile_repl_decs_thm |> GEN_ALL
           |> Q.SPEC `repl_decs`
           |> RW [repl_decs_lemma]
  val th = MATCH_MP th (repl_decs_cenv_env_s_def |> RW [EVAL ``empty_store``])
  in th |> SIMP_RULE std_ss [LET_DEF,GSYM compile_term_def]
        |> CONV_RULE (DEPTH_CONV (PairRules.PBETA_CONV))
        |> SIMP_RULE (srw_ss()) [GSYM new_compiler_state_def] end

val compile_term_out_EQ_bootstrap_lcode = prove(
  ``REVERSE (SND (SND (SND compile_term))).out = REVERSE bootstrap_lcode``,
  SIMP_TAC std_ss [compile_term_def]
  \\ REWRITE_TAC [compileReplDecsTheory.repl_decs_compiled,
       repl_computeTheory.compile_decs_FOLDL,LET_DEF]
  \\ CONV_TAC (DEPTH_CONV PairRules.PBETA_CONV)
  \\ REWRITE_TAC [SND,FST,``<|out := code; next_label := n |>.out``
                          |> SIMP_CONV (srw_ss()) []]
  \\ REWRITE_TAC [compileCallReplStepDecTheory.bootstrap_lcode_def]);

val code_labels_ok_rev_bootstrap_lcode = let
  val lemma1 =
    ``<|out := code; next_label := n |>.out``
    |> SIMP_CONV (srw_ss()) []
  val lemma2 =
    ``<|bvars := names; mvars := FEMPTY; cnmap := internal37|>.bvars``
    |> SIMP_CONV (srw_ss()) []
  val lemma3 = prove(
    ``(?x. (y = x) /\ P x) ==> P y``,
    SIMP_TAC std_ss []);
  val (i,[]) = match_term ``compile_decs mn menv ct m env rsz cs decs`` (rhs(concl compile_term_def))
  val th =
    compilerProofsTheory.compile_decs_append_out
    |> SPEC_ALL |> INST i |> SIMP_RULE (srw_ss()) [LET_DEF,repl_decs_lemma]
    |> RW [compileReplDecsTheory.repl_decs_compiled,repl_computeTheory.compile_decs_FOLDL,LET_DEF]
    |> CONV_RULE (DEPTH_CONV PairRules.PBETA_CONV)
    |> RW [lemma1,lemma2,GSYM miscTheory.SWAP_REVERSE_SYM]
    |> HO_MATCH_MP lemma3 |> CONJUNCTS |> el 2
    |> CONV_RULE ((RAND_CONV o RAND_CONV o REWR_CONV) (GSYM compileCallReplStepDecTheory.bootstrap_lcode_def))
  in th end

val code_labels_bootstrap_lcode =
  PROVE_HYP code_labels_ok_rev_bootstrap_lcode
  compileCallReplStepDecTheory.code_labels_rev_bootstrap_lcode

val next_addr_code_labels = prove(
  ``length_ok l ==>
    (next_addr l (code_labels l code) = next_addr l code)``,
  FULL_SIMP_TAC std_ss [bytecodeLabelsTheory.code_labels_def]
  \\ Q.SPEC_TAC (`all_labels l code`,`labs`)
  \\ Induct_on `code` THEN1 (EVAL_TAC \\ SIMP_TAC std_ss [])
  \\ REPEAT STRIP_TAC \\ Cases_on `h` \\ TRY (Cases_on `l'`)
  \\ FULL_SIMP_TAC (srw_ss()) [bytecodeLabelsTheory.inst_labels_def,
       bytecodeLabelsTheory.length_ok_def]);

val new_compiler_state_renv =
  SIMP_CONV (srw_ss()) [new_compiler_state_def] ``new_compiler_state.renv``
  |> RW [compile_term_def,compileReplDecsTheory.repl_decs_compiled,repl_computeTheory.compile_decs_FOLDL,LET_THM]
  |> CONV_RULE (DEPTH_CONV (PairRules.PBETA_CONV))
  |> RW [SND]
  |> RW [SIMP_CONV (srw_ss()) [] ``<|bvars := X; mvars := Y; cnmap := Z|>.bvars``]

val length_new_compiler_state_renv =
  EVAL (listSyntax.mk_length(
          new_compiler_state_renv |> concl |> rhs |> rand |> rator |> rand))

val MEM_call_repl_step = prove(
  ``env_rs [] (cenv ++ init_envC) (0,s)
      env new_compiler_state 0 rd bs' ==>
    MEM "call_repl_step" (MAP FST env) /\
    ∃cl out inp st.
      (bs'.stack = cl::out::inp::st)
        (* /\ v1 is a pointer to a store cell in bc.refs that
                                holds LAST s *)``,
  simp[compilerProofsTheory.env_rs_def,LET_THM] >> strip_tac >>
  Q.PAT_ASSUM`X = MAP FST env`(ASSUME_TAC o SYM) THEN
  conj_tac >- (
    SRW_TAC[][] THEN
    REWRITE_TAC[new_compiler_state_renv] THEN
    qmatch_abbrev_tac`MEM "call_repl_step" (MAP FST (ZIP (l1,l2)))` >>
    qsuff_tac `MEM "call_repl_step" l1 ∧ (LENGTH l1 = LENGTH l2)` >- simp[listTheory.MAP_ZIP] >>
    mp_tac length_new_compiler_state_renv >> FULL_SIMP_TAC bool_ss [] >>
    strip_tac >>
    conj_tac >- simp[Abbr`l1`] >>
    simp[Abbr`l2`] ) >>
  fs[toBytecodeProofsTheory.Cenv_bs_def] >>
  fs[toBytecodeProofsTheory.env_renv_def] >>
  qpat_assum`EVERY2 P X Y`mp_tac >>
  simp_tac bool_ss [miscTheory.EVERY2_MAP] >>
  simp[CompilerLibTheory.el_check_def] >>
  `∃x y z w. new_compiler_state.renv = x::y::z::w` by (
    REWRITE_TAC[new_compiler_state_renv] >>
    EVAL_TAC >> SRW_TAC[][] ) >>
  strip_tac >>
  `∃Cx Cy Cz Cw. Cenv = Cx::Cy::Cz::Cw` by (
    fs[listTheory.EVERY2_EVERY] >> rfs[] >>
    Cases_on`Cenv`>>fs[]>>
    Cases_on`t`>>fs[]>>
    Cases_on`t'`>>fs[]) >>
  BasicProvers.VAR_EQ_TAC >>
  pop_assum mp_tac >>
  simp[] >>
  Cases_on`SND x < LENGTH bs'.stack` >> simp[] >>
  Cases_on`SND y < LENGTH bs'.stack` >> simp[] >>
  Cases_on`SND z < LENGTH bs'.stack` >> simp[] >>
  qpat_assum`new_compiler_state_renv = X`mp_tac >>
  REWRITE_TAC[new_compiler_state_renv] >>
  EVAL_TAC >>
  strip_tac >>
  rpt BasicProvers.VAR_EQ_TAC >>
  rpt strip_tac >>
  rpt (qpat_assum`X < LENGTH Y`mp_tac) >>
  Cases_on`bs'.stack`>>simp[] >>
  Cases_on`t`>>simp[] >>
  Cases_on`t'`>>simp[] )

val bc_eval_bootstrap_lcode = prove(
  ``∀bs.
       (bs.code = REVERSE bootstrap_lcode) ∧ length_ok bs.inst_length /\
       (bs.pc = 0) ∧ (bs.stack = []) ∧ (bs.clock = NONE) ⇒
       ∃bs' rd.
         (bc_eval (strip_labels bs) = SOME (strip_labels bs')) ∧
         (bs'.pc = next_addr bs.inst_length (strip_labels bs).code) ∧
         env_rs [] (repl_decs_cenv ++ init_envC) (0,repl_decs_s)
           repl_decs_env new_compiler_state 0 rd bs' /\
         MEM "call_repl_step" (MAP FST repl_decs_env)``,
  STRIP_ASSUME_TAC compile_decs_bc_eval
  \\ REPEAT STRIP_TAC
  \\ FIRST_X_ASSUM (MP_TAC o Q.SPEC `bs`)
  \\ FULL_SIMP_TAC std_ss []
  \\ MATCH_MP_TAC set_sepTheory.IMP_IMP
  \\ SIMP_TAC std_ss [compile_term_out_EQ_bootstrap_lcode]
  \\ REPEAT STRIP_TAC
  \\ Q.EXISTS_TAC `bs'`
  \\ Q.EXISTS_TAC `rd` \\ FULL_SIMP_TAC std_ss []
  \\ STRIP_TAC THEN1
   (MATCH_MP_TAC (MP_CANON bytecodeEvalTheory.RTC_bc_next_bc_eval)
    \\ IMP_RES_TAC bytecodeEvalTheory.bc_eval_SOME_RTC_bc_next
    \\ IMP_RES_TAC bytecodeLabelsTheory.bc_next_strip_labels_RTC
    \\ FULL_SIMP_TAC std_ss []
    \\ CCONTR_TAC
    \\ FULL_SIMP_TAC std_ss []
    \\ IMP_RES_TAC bytecodeLabelsTheory.bc_next_strip_IMP
    \\ REVERSE (`length_ok bs'.inst_length` by ALL_TAC)
    \\ FULL_SIMP_TAC std_ss [] THEN1 METIS_TAC []
    \\ IMP_RES_TAC bytecodeExtraTheory.RTC_bc_next_preserves
    \\ FULL_SIMP_TAC std_ss [])
  \\ FULL_SIMP_TAC (srw_ss()) [bytecodeLabelsTheory.strip_labels_def]
  \\ FULL_SIMP_TAC std_ss [next_addr_code_labels]
  \\ IMP_RES_TAC MEM_call_repl_step);

val compile_call_term_def = Define `
  compile_call_term = compile_dec FEMPTY (FST (SND compile_repl_decs))
     (FST (SND (SND compile_repl_decs)))
     (FST (SND (SND (SND compile_repl_decs))))
     <|out := [];
       next_label :=
         (SND (SND (SND (SND compile_repl_decs)))).next_label|>
     call_repl_step_dec`;

val compile_call_term_thm =
  call_repl_step_dec_compiled
  |> SIMP_RULE std_ss [GSYM compileCallReplStepDecTheory.call_lcode_def,
       LET_DEF,GSYM compile_call_term_def]

(*

|- FV_dec call_repl_step_dec = {Short "call_repl_step"}

but to get rid of asumption in

  val th =
    compile_call_repl_step_thm |> GEN_ALL
      |> Q.SPEC `call_repl_step_dec` |> Q.SPEC `NONE`
      |> RW [EVAL ``dec_cns call_repl_step_dec``]
      |> Q.SPECL [`repl_decs_cenv`,`s`,`repl_decs_env`,`s2`]

compile_call_term_def

  print_find "repl_decs_compiled"

we need:

|- FV_dec call_repl_step_dec = {}



*)




(*

val entire_x64_implementation_def = Define `
  entire_x64_implementation p =
    {(p:word64,[0x88w:word8])} UNION bignum_code (p + 999w)`;

val out_def = Define `
  (out (Diverge) = ("",F)) /\
  (out (Terminate) = ("",T)) /\
  (out (Result r rest) =
     let (str,res) = out rest in
       (r ++ str,res))`;



val x64_correct = store_thm("x64_correct",
  ``TEMPORAL X64_MODEL (entire_x64_implementation p)
      (T_IMPLIES (INIT_STATE init)
                 (T_DISJ (EVENTUALLY (SEP_EXISTS output result bools. zHEAP_OUTPUT (first_cs init,output) *
                                         cond (repl bools init.init_input result /\ (out result = (output,T)))))
                 (T_DISJ (ALWAYS (EVENTUALLY (SEP_EXISTS output result bools. zHEAP_OK output *
                                         cond (repl bools init.init_input result /\ (out result = (output,F))))))
                         (EVENTUALLY (SEP_EXISTS output rest result bools success. zHEAP_ERROR output *
                                         cond (repl bools init.init_input result /\ (out result = (output ++ rest,success))))))))``,
  cheat);

*)

val _ = export_theory()
