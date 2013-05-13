open preamble repl_funTheory wordsLib intLib
open AstTheory inferTheory CompilerTheory compilerTerminationTheory bytecodeEvalTheory
(* need wordsLib to make EVAL work on toString - this should be fixed in HOL *)
(* need intLib to EVAL double negation of ints *)
val _ = new_theory"repl_funExamples"

(* stuff for proving the wfs condition on t_unify etc. *)

val t_unify_wfs = prove(
 ``t_wfs s ∧ (t_unify s t1 t2 = SOME sx) ==> t_wfs sx``,
 metis_tac[unifyTheory.t_unify_unifier])

val t_wfs_FEMPTY = prove(
  ``t_wfs FEMPTY``,
  rw[unifyTheory.t_wfs_def])

val _ = computeLib.add_funs
  [unifyTheory.t_walk_eqn
  ,unifyTheory.t_ext_s_check_eqn
  ,computeLib.lazyfy_thm(bytecodeEvalTheory.bc_eval_def)
  ]
val _ = computeLib.add_funs[listTheory.SUM] (* why isn't this in there already !? *)

val db = ref (Net.insert (rand(concl(t_wfs_FEMPTY)),t_wfs_FEMPTY) Net.empty)
fun t_unify_conv tm = let
  val (_,[s,t1,t2]) = strip_comb tm
  val wfs_s = hd(Net.index s (!db))
  val th1 = SPECL [t1,t2] (MATCH_MP unifyTheory.t_unify_eqn wfs_s)
  val th2 = EVAL (rhs(concl th1))
  val th3 = TRANS th1 th2
  val res = rhs(concl th2)
  val _ = if optionSyntax.is_some res then
          db := Net.insert (rand res,PROVE[wfs_s,t_unify_wfs,th3]``^(rator(concl wfs_s)) ^(rand res)``) (!db)
          else ()
  in th3 end
fun t_vwalk_conv tm = let
  val (_,[s,t]) = strip_comb tm
  val wfs_s = hd(Net.index s (!db))
  val th1 = SPEC t (MATCH_MP unifyTheory.t_vwalk_eqn wfs_s)
  val th2 = EVAL (rhs(concl th1))
  in TRANS th1 th2 end
fun t_oc_conv tm = let
  val (_,[s,t1,t2]) = strip_comb tm
  val wfs_s = hd(Net.index s (!db))
  val th1 = SPECL [t1,t2] (MATCH_MP unifyTheory.t_oc_eqn wfs_s)
  val th2 = EVAL (rhs(concl th1))
  in TRANS th1 th2 end
fun t_walkstar_conv tm = let
  val (_,[s,t]) = strip_comb tm
  val wfs_s = hd(Net.index s (!db))
  val th1 = SPEC t (MATCH_MP unifyTheory.t_walkstar_eqn wfs_s)
  val th2 = EVAL (rhs(concl th1))
  in TRANS th1 th2 end

val _ = computeLib.add_convs
[(``t_unify``,3,t_unify_conv)
,(``t_vwalk``,2,t_vwalk_conv)
,(``t_walkstar``,2,t_walkstar_conv)
,(``t_oc``,3,t_oc_conv)
]

(* add repl definitions to the compset *)

val RES_FORALL_set = prove(``RES_FORALL (set ls) P = EVERY P ls``,rw[RES_FORALL_THM,listTheory.EVERY_MEM])

val bc_fetch_aux_zero = prove(
``∀ls n. bc_fetch_aux ls (K 0) n = el_check n (FILTER ($~ o is_Label) ls)``,
Induct >> rw[CompilerLibTheory.el_check_def] >> fs[] >> fsrw_tac[ARITH_ss][] >>
simp[rich_listTheory.EL_CONS,arithmeticTheory.PRE_SUB1])

val _ = computeLib.add_funs
  [ElabTheory.elab_p_def
  ,CompilerLibTheory.find_index_def
  ,CompilerLibTheory.the_def
  ,CompilerLibTheory.lunion_def
  ,CompilerLibTheory.lshift_def
  ,pat_bindings_def
  ,compile_news_def
  ,compile_shadows_def
  ,ToBytecodeTheory.compile_varref_def
  ,CONV_RULE(!Defn.SUC_TO_NUMERAL_DEFN_CONV_hook)compile_def
  ,label_closures_def
  ,remove_mat_var_def
  ,ToIntLangTheory.remove_mat_vp_def
  ,mkshift_def
  ,ToBytecodeTheory.cce_aux_def
  ,exp_to_Cexp_def
  ,ToIntLangTheory.pat_to_Cpat_def
  ,ToIntLangTheory.Cpat_vars_def
  ,generalise_def
  ,RES_FORALL_set
  ,bc_fetch_aux_zero
  ]

val input = ``"val x = true; val y = 2;"``

val ex1 = time EVAL ``repl_fun ^input``
val _ = save_thm("ex1",ex1)

val input = ``"fun f x = x + 3; f 2;"``

val ex2 = time EVAL ``repl_fun ^input``
val _ = save_thm("ex2",ex2)

val input = ``"datatype foo = C of int | D of bool; fun f x = case x of (C i) => i+1 | D _ => 0; f (C (3));"``

val ex3 = time EVAL ``repl_fun ^input``
val _ = save_thm("ex3",ex3)

val input = ``"fun f n = if n = 0 then 1 else n * f (n-1); f 0;"``
val ex4 = time EVAL ``repl_fun ^input``

(* intermediate steps:
  val s = ``init_repl_fun_state``
  val bs = ``init_bc_state``

  val (tokens,rest_of_input) = time EVAL ``lex_next_top ^input`` |> concl |> rhs |> rand |> pairSyntax.dest_pair

    val ast_prog = time EVAL ``mmlParse$parse ^tokens`` |> concl |> rhs |> rand

    val rtypes = EVAL ``^s.rtypes`` |> concl |> rhs
    val rctors = EVAL ``^s.rctors`` |> concl |> rhs
    val rbindings = EVAL ``^s.rbindings`` |> concl |> rhs
    val prog = time EVAL ``elab_prog ^rtypes ^rctors ^rbindings ^ast_prog`` |> concl |> rhs |> rand |> rand |> rand

    val rmenv = EVAL ``^s.rmenv`` |> concl |> rhs
    val rcenv = EVAL ``^s.rcenv`` |> concl |> rhs
    val rtenv = EVAL ``^s.rtenv`` |> concl |> rhs

    val res = time EVAL ``infer_prog ^rmenv ^rcenv ^rtenv ^prog init_infer_state``

  val (code,new_s) = time EVAL ``parse_elaborate_typecheck_compile ^tokens ^s`` |> concl |> rhs |> rand |> pairSyntax.dest_pair

  val bs = EVAL ``install_code ^code ^bs`` |> concl |> rhs

  (*
    val bc_evaln_def = Define`
      (bc_evaln 0 bs = SOME bs) ∧
      (bc_evaln (SUC n) bs = OPTION_BIND (bc_eval1 bs) (bc_evaln n))`
    val bs = time EVAL ``bc_evaln 50 ^bs`` |> concl |> rhs |> rand
  *)

  val new_bs = time EVAL ``bc_eval ^bs`` |> concl |> rhs |> rand

  val (new_bs,res) = time EVAL ``print_result ^new_s ^new_bs`` |> concl |> rhs |> pairSyntax.dest_pair

  val input = rest_of_input
  val s = new_s
  val bs = new_bs
*)

val _ = export_theory()
