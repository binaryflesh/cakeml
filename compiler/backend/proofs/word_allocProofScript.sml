open preamble BasicProvers
     reg_allocTheory reg_allocProofTheory
     wordLangTheory wordPropsTheory word_allocTheory wordSemTheory

val _ = new_theory "word_allocProof";

val _ = bring_to_front_overload"get_vars"{Name="get_vars",Thy="wordSem"};

(*TODO: Fix all the list_insert theorem names to alist_insert*)
(*TODO: refactor lemmas into Props etc. theories as appropriate *)

val list_max_max = Q.store_thm("list_max_max",
  `∀ls.  EVERY (λx. x ≤ list_max ls) ls`,
  Induct>>fs[list_max_def,LET_THM]>>rw[]>>fs[EVERY_MEM]>>rw[]>>
  res_tac >> decide_tac);

val colouring_ok_def = Define`
  (colouring_ok f (Seq s1 s2) live =
    (*Normal live sets*)
    let s2_live = get_live s2 live in
    let s1_live = get_live s1 s2_live in
      INJ f (domain s1_live) UNIV ∧
      (*Internal clash sets*)
      colouring_ok f s2 live ∧ colouring_ok f s1 s2_live) ∧
  (colouring_ok f (If cmp r1 ri e2 e3) live =
    let e2_live = get_live e2 live in
    let e3_live = get_live e3 live in
    let union_live = union e2_live e3_live in
    let merged = case ri of Reg r2 => insert r2 () (insert r1 () union_live)
                      | _ => insert r1 () union_live in
    (*All of them must be live at once*)
      INJ f (domain merged) UNIV ∧
      (*Internal clash sets*)
      colouring_ok f e2 live ∧ colouring_ok f e3 live) ∧
  (colouring_ok f (Call(SOME(v,cutset,ret_handler,l1,l2))dest args h) live =
    let args_set = numset_list_insert args LN in
    INJ f (domain (union cutset args_set)) UNIV ∧
    INJ f (domain (insert v () cutset)) UNIV ∧
    (*returning handler*)
    colouring_ok f ret_handler live ∧
    (*exception handler*)
    (case h of
    | NONE => T
    | SOME(v,prog,l1,l2) =>
        INJ f (domain (insert v () cutset)) UNIV ∧
        colouring_ok f prog live)) ∧
  (colouring_ok f prog live =
    (*live before must be fine, and clash set must be fine*)
    let lset = get_live prog live in
    let iset = union (get_writes prog) live in
      INJ f (domain lset) UNIV ∧ INJ f (domain iset) UNIV)`

(*Alternate liveness*)
val colouring_ok_alt_def = Define`
  colouring_ok_alt f prog live =
    let (hd,ls) = get_clash_sets prog live in
    EVERY (λs. INJ f (domain s) UNIV) ls ∧
    INJ f (domain hd) UNIV`

(*Equivalence on everything except permutation and locals*)
val word_state_eq_rel_def = Define`
  word_state_eq_rel s t ⇔
  t.store = s.store ∧
  t.stack = s.stack ∧
  t.memory = s.memory ∧
  t.mdomain = s.mdomain ∧
  t.gc_fun = s.gc_fun ∧
  t.handler = s.handler ∧
  t.clock = s.clock ∧
  t.code = s.code ∧
  t.ffi = s.ffi ∧
  t.be = s.be`

(*tlocs is a supermap of slocs under f for everything in a given
  live set*)
val strong_locals_rel_def = Define`
  strong_locals_rel f ls slocs tlocs ⇔
  ∀n v.
    n ∈ ls ∧ lookup n slocs = SOME v ⇒
    lookup (f n) tlocs = SOME v`

val domain_numset_list_insert = store_thm("domain_numset_list_insert",``
  ∀ls locs.
  domain (numset_list_insert ls locs) = domain locs UNION set ls``,
  Induct>>fs[numset_list_insert_def]>>rw[]>>
  metis_tac[INSERT_UNION_EQ,UNION_COMM])

val strong_locals_rel_get_var = prove(``
  strong_locals_rel f live st.locals cst.locals ∧
  n ∈ live ∧
  get_var n st = SOME x
  ⇒
  get_var (f n) cst = SOME x``,
  fs[get_var_def,strong_locals_rel_def])

val strong_locals_rel_get_var_imm = prove(``
  strong_locals_rel f live st.locals cst.locals ∧
  (case n of Reg n => n ∈ live | _ => T) ∧
  get_var_imm n st = SOME x
  ⇒
  get_var_imm (apply_colour_imm f n) cst = SOME x``,
  Cases_on`n`>>fs[get_var_imm_def]>>
  metis_tac[strong_locals_rel_get_var])

val strong_locals_rel_get_vars = prove(``
  ∀ls y f live st cst.
  strong_locals_rel f live st.locals cst.locals ∧
  (∀x. MEM x ls ⇒ x ∈ live) ∧
  get_vars ls st = SOME y
  ⇒
  get_vars (MAP f ls) cst = SOME y``,
  Induct>>fs[get_vars_def]>>rw[]>>
  Cases_on`get_var h st`>>fs[]>>
  `h ∈ live` by fs[]>>
  imp_res_tac strong_locals_rel_get_var>>fs[]>>
  Cases_on`get_vars ls st`>>fs[]>>
  res_tac>>
  pop_assum(qspec_then`live` mp_tac)>>discharge_hyps
  >-metis_tac[]>>
  fs[])

val domain_FOLDR_union_subset = prove(``
  !ls a.
  MEM a ls ⇒
  domain (get_live_exp a) ⊆
  domain (FOLDR (λx y.union (get_live_exp x) y) LN ls)``,
  Induct>>rw[]>>fs[domain_union,SUBSET_UNION,SUBSET_DEF]>>
  metis_tac[])

val SUBSET_OF_INSERT = store_thm("SUBSET_OF_INSERT",
``!s x. s ⊆ x INSERT s``,
  rw[SUBSET_DEF])

val INJ_UNION = prove(
``!f A B.
  INJ f (A ∪ B) UNIV ⇒
  INJ f A UNIV ∧
  INJ f B UNIV``,
  rw[]>>
  metis_tac[INJ_SUBSET,SUBSET_DEF,SUBSET_UNION])

val size_tac= (fs[prog_size_def]>>DECIDE_TAC);

val apply_nummap_key_domain = prove(``
  ∀f names.
  domain (apply_nummap_key f names) =
  IMAGE f (domain names)``,
  fs[domain_def,domain_fromAList]>>
  fs[MEM_MAP,MAP_MAP_o,EXTENSION,EXISTS_PROD]>>
  metis_tac[MEM_toAList,domain_lookup])

val cut_env_lemma = store_thm("cut_env_lemma",``
  ∀names sloc tloc x f.
  INJ f (domain names) UNIV ∧
  cut_env names sloc = SOME x ∧
  strong_locals_rel f (domain names) sloc tloc
  ⇒
  ∃y. cut_env (apply_nummap_key f names) tloc = SOME y ∧
      domain y = IMAGE f (domain x) ∧
      strong_locals_rel f (domain names) x y ∧
      INJ f (domain x) UNIV ∧
      domain x = domain names``,
  rpt strip_tac>>
  fs[domain_inter,cut_env_def,apply_nummap_key_domain
    ,strong_locals_rel_def]>>
  CONJ_ASM1_TAC>-
    (fs[SUBSET_DEF,domain_lookup]>>rw[]>>metis_tac[])>>
  CONJ_ASM1_TAC>-
    (Q.ISPECL_THEN[`f`,`names`] assume_tac apply_nummap_key_domain>>
    fs[SUBSET_INTER_ABSORPTION,INTER_COMM]>>
    metis_tac[domain_inter])>>
  rw[]>-
    (rw[]>>fs[lookup_inter]>>
    Cases_on`lookup n sloc`>>fs[]>>
    Cases_on`lookup n names`>>fs[]>>
    res_tac>>
    imp_res_tac MEM_toAList>>
    fs[lookup_fromAList]>>
    EVERY_CASE_TAC>>
    fs[ALOOKUP_NONE,MEM_MAP,FORALL_PROD]>>metis_tac[])
  >>
    fs[domain_inter,SUBSET_INTER_ABSORPTION,INTER_COMM])

val LENGTH_list_rerrange = prove(``
  LENGTH (list_rearrange mover xs) = LENGTH xs``,
  fs[list_rearrange_def]>>
  IF_CASES_TAC>>fs[])

(*For any 2 lists that are permutations of each other,
  We can give a list_rearranger that permutes one to the other*)
val list_rearrange_perm = prove(``
  PERM xs ys
  ⇒
  ∃perm. list_rearrange perm xs = ys``,
  rw[]>>
  imp_res_tac PERM_BIJ>>fs[list_rearrange_def]>>
  qexists_tac`f`>>
  IF_CASES_TAC>>
  fs[BIJ_DEF,INJ_DEF]>>metis_tac[])

val GENLIST_MAP = prove(
  ``!k. (!i. i < LENGTH l ==> m i < LENGTH l) /\ k <= LENGTH l ==>
        GENLIST (\i. EL (m i) (MAP f l)) k =
        MAP f (GENLIST (\i. EL (m i) l) k)``,
  Induct \\ fs [GENLIST] \\ REPEAT STRIP_TAC
  \\ `k < LENGTH l /\ k <= LENGTH l` by DECIDE_TAC
  \\ fs [EL_MAP]);

val list_rearrange_MAP = store_thm ("list_rearrange_MAP",
  ``!l f m. list_rearrange m (MAP f l) = MAP f (list_rearrange m l)``,
  SRW_TAC [] [list_rearrange_def] \\ MATCH_MP_TAC GENLIST_MAP \\
  fs[BIJ_DEF,INJ_DEF]);

val ALL_DISTINCT_FST = ALL_DISTINCT_MAP |> Q.ISPEC `FST`

(*Main theorem for permute oracle usage!
  This shows that we can push locals that are exactly matching using
  any desired permutation
  and we can choose the final permutation to be anything we want
  (In Alloc we choose it to be cst.permute, in Call something
   given by the IH)
*)

val env_to_list_perm = prove(``
  ∀tperm.
  domain y = IMAGE f (domain x) ∧
  INJ f (domain x) UNIV ∧
  strong_locals_rel f (domain x) x y
  ⇒
  let (l,permute) = env_to_list y perm in
  ∃perm'.
    let(l',permute') = env_to_list x perm' in
      permute' = tperm ∧ (*Just change the first permute*)
      MAP (λx,y.f x,y) l' = l``,
  rw[]>>
  fs[env_to_list_def,LET_THM,strong_locals_rel_def]>>
  qabbrev_tac `xls = QSORT key_val_compare (toAList x)`>>
  qabbrev_tac `yls = QSORT key_val_compare (toAList y)`>>
  qabbrev_tac `ls = list_rearrange (perm 0) yls`>>
  fs[(GEN_ALL o SYM o SPEC_ALL) list_rearrange_MAP]>>
  `PERM (MAP (λx,y.f x,y) xls) yls` by
    (match_mp_tac PERM_ALL_DISTINCT >>rw[]
    >-
      (match_mp_tac ALL_DISTINCT_MAP_INJ>>rw[]
      >-
        (fs[INJ_DEF,Abbr`xls`,QSORT_MEM]>>
        Cases_on`x'`>>Cases_on`y'`>>fs[]>>
        imp_res_tac MEM_toAList>>
        fs[domain_lookup])
      >>
      fs[Abbr`xls`]>>
      metis_tac[QSORT_PERM,ALL_DISTINCT_MAP_FST_toAList
               ,ALL_DISTINCT_FST,ALL_DISTINCT_PERM])
    >-
      metis_tac[QSORT_PERM,ALL_DISTINCT_MAP_FST_toAList
               ,ALL_DISTINCT_FST,ALL_DISTINCT_PERM]
    >>
      unabbrev_all_tac>>
      fs[QSORT_MEM,MEM_MAP]>>
      fs[EQ_IMP_THM]>>rw[]
      >-
        (Cases_on`y'`>>fs[MEM_toAList]>>metis_tac[domain_lookup])
      >>
        Cases_on`x'`>>fs[MEM_toAList]>>
        imp_res_tac domain_lookup>>
        fs[EXTENSION]>>res_tac>>
        qexists_tac`x',r`>>fs[]>>
        fs[MEM_toAList,domain_lookup]>>
        first_x_assum(qspecl_then[`x'`,`v'`] assume_tac)>>rfs[])
  >>
  `PERM yls ls` by
    (fs[list_rearrange_def,Abbr`ls`]>>
    qpat_assum`A=l` (SUBST1_TAC o SYM)>>
    IF_CASES_TAC>>fs[]>>
    match_mp_tac PERM_ALL_DISTINCT>>
    CONJ_ASM1_TAC>-
      metis_tac[QSORT_PERM,ALL_DISTINCT_MAP_FST_toAList
               ,ALL_DISTINCT_FST,ALL_DISTINCT_PERM]>>
    CONJ_ASM1_TAC>-
      (fs[ALL_DISTINCT_GENLIST]>>rw[]>>
      fs[EL_ALL_DISTINCT_EL_EQ]>>
      `perm 0 i = perm 0 i'` by
        (fs[BIJ_DEF,INJ_DEF]>>
        metis_tac[])>>
      fs[BIJ_DEF,INJ_DEF])
    >>
      fs[MEM_GENLIST,BIJ_DEF,INJ_DEF,SURJ_DEF]>>
      fs[MEM_EL]>>metis_tac[])>>
  imp_res_tac PERM_TRANS>>
  imp_res_tac list_rearrange_perm>>
  qexists_tac`λn. if n = 0:num then perm' else tperm (n-1)`>>
  fs[FUN_EQ_THM])

(*Proves s_val_eq and some extra conditions on the resulting lists*)
val push_env_s_val_eq = store_thm("push_env_s_val_eq",``
  ∀tperm.
  st.handler = cst.handler ∧
  st.stack = cst.stack ∧
  domain y = IMAGE f (domain x) ∧
  INJ f (domain x) UNIV ∧
  strong_locals_rel f (domain x) x y ∧
  (case b of NONE => b' = NONE
         |  SOME(w,h,l1,l2) =>
            (case b' of NONE => F
            |  SOME(a,b,c,d) => c = l1 ∧ d = l2))
  ⇒
  ?perm.
  (let (l,permute) = env_to_list y cst.permute in
  let(l',permute') = env_to_list x perm in
      permute' = tperm ∧
      MAP (λx,y.f x,y) l' = l ∧
      (∀x y. MEM x (MAP FST l') ∧ MEM y (MAP FST l')
        ∧ f x = f y ⇒ x = y) ) ∧
  s_val_eq (push_env x b (st with permute:=perm)).stack
           (push_env y b' cst).stack``,
  rw[]>>Cases_on`b`>>
  TRY(PairCases_on`x'`>>Cases_on`b'`>>fs[]>>PairCases_on`x'`>>fs[])>>
  (fs[push_env_def]>>
  imp_res_tac env_to_list_perm>>
  pop_assum(qspecl_then[`tperm`,`cst.permute`]assume_tac)>>fs[LET_THM]>>
  Cases_on`env_to_list y cst.permute`>>
  fs[]>>
  qexists_tac`perm'`>>
  Cases_on`env_to_list x perm'`>>
  fs[env_to_list_def,LET_THM]>>
  fs[s_val_eq_def,s_val_eq_refl]>>
  rw[]>-
    (fs[INJ_DEF,MEM_MAP]>>
    imp_res_tac mem_list_rearrange>>
    fs[QSORT_MEM]>>
    Cases_on`y'''`>>Cases_on`y''`>>fs[MEM_toAList]>>
    metis_tac[domain_lookup])>>
  fs[s_frame_val_eq_def]>>
  qpat_abbrev_tac `q = list_rearrange A
    (QSORT key_val_compare (toAList x))`>>
  `MAP SND (MAP (λx,y.f x,y) q) = MAP SND q` by
    (fs[MAP_MAP_o]>>AP_THM_TAC>>AP_TERM_TAC>>fs[FUN_EQ_THM]>>
    rw[]>>Cases_on`x'`>>fs[])>>
  metis_tac[]))

(*TODO: Move?*)
val INJ_less = prove(``
  INJ f s' UNIV ∧ s ⊆ s'
  ⇒
  INJ f s UNIV``,
  metis_tac[INJ_DEF,SUBSET_DEF])

(*TODO: Maybe move to props?
gc doesn't touch other components*)
val gc_frame = store_thm("gc_frame",``
  gc st = SOME st'
  ⇒
  st'.mdomain = st.mdomain ∧
  st'.gc_fun = st.gc_fun ∧
  st'.handler = st.handler ∧
  st'.clock = st.clock ∧
  st'.code = st.code ∧
  st'.locals = st.locals ∧
  st'.be = st.be ∧
  st'.ffi = st.ffi ∧
  st'.permute = st.permute``,
  fs[gc_def,LET_THM]>>EVERY_CASE_TAC>>
  fs[state_component_equality])

val ZIP_MAP_FST_SND_EQ = prove(``
  ∀ls. ZIP (MAP FST ls,MAP SND ls) = ls``,
  Induct>>fs[])

(*Convenient rewrite for pop_env*)
val s_key_eq_val_eq_pop_env = store_thm("s_key_eq_val_eq_pop_env",``
  pop_env s = SOME s' ∧
  s_key_eq s.stack ((StackFrame ls opt)::keys) ∧
  s_val_eq s.stack vals
  ⇒
  ∃ls' rest.
  vals = StackFrame ls' opt :: rest ∧
  s'.locals = fromAList (ZIP (MAP FST ls,MAP SND ls')) ∧
  s_key_eq s'.stack keys ∧
  s_val_eq s'.stack rest ∧
  case opt of NONE => s'.handler = s.handler
            | SOME (h,l1,l2) => s'.handler = h``,
  strip_tac>>
  fs[pop_env_def]>>
  EVERY_CASE_TAC>>
  Cases_on`vals`>>
  fs[s_val_eq_def,s_key_eq_def]>>
  Cases_on`h`>>Cases_on`o'`>>
  fs[s_frame_key_eq_def,s_frame_val_eq_def]>>
  fs[state_component_equality]>>
  metis_tac[ZIP_MAP_FST_SND_EQ])

(*Less powerful form*)
val ALOOKUP_key_remap_2 = store_thm("ALOOKUP_key_remap_2",``
  ∀ls vals f.
    (∀x y. MEM x ls ∧ MEM y ls ∧ f x = f y ⇒ x = y) ∧
    LENGTH ls = LENGTH vals ∧
    ALOOKUP (ZIP (ls,vals)) n = SOME v
    ⇒
    ALOOKUP (ZIP (MAP f ls,vals)) (f n) = SOME v``,
  Induct>>rw[]>>
  Cases_on`vals`>>fs[]>>
  Cases_on`h=n`>>fs[]>>
  `MEM n ls` by
    (imp_res_tac ALOOKUP_MEM>>
    imp_res_tac MEM_ZIP>>
    fs[]>>
    metis_tac[MEM_EL])>>
  first_assum(qspecl_then[`h`,`n`] assume_tac)>>
  IF_CASES_TAC>>fs[])

val lookup_alist_insert = lookup_alist_insert |> INST_TYPE [alpha|->``:'a word_loc``]

val strong_locals_rel_subset = prove(``
  s ⊆ s' ∧
  strong_locals_rel f s' st.locals cst.locals
  ⇒
  strong_locals_rel f s st.locals cst.locals``,
  rw[strong_locals_rel_def]>>
  metis_tac[SUBSET_DEF])

val env_to_list_keys = prove(``
  let (l,permute) = env_to_list x perm in
  set (MAP FST l) = domain x``,
  fs[LET_THM,env_to_list_def,EXTENSION,MEM_MAP,EXISTS_PROD]>>
  rw[EQ_IMP_THM]
  >-
    (imp_res_tac mem_list_rearrange>>
    fs[QSORT_MEM,MEM_toAList,domain_lookup])
  >>
    fs[mem_list_rearrange,QSORT_MEM,MEM_toAList,domain_lookup])

val list_rearrange_keys = store_thm("list_rearrange_keys",``
  list_rearrange perm ls = e ⇒
  set(MAP FST e) = set(MAP FST ls)``,
  fs[LET_THM,EXTENSION]>>rw[EQ_IMP_THM]>>
  metis_tac[MEM_toAList,mem_list_rearrange,MEM_MAP])

val push_env_pop_env_s_key_eq = store_thm("push_env_pop_env_s_key_eq",
  ``∀s t x b. s_key_eq (push_env x b s).stack t.stack ⇒
       ∃l ls opt.
              t.stack = (StackFrame l opt)::ls ∧
              ∃y. (pop_env t = SOME y ∧
                   y.locals = fromAList l ∧
                   domain x = domain y.locals ∧
                   s_key_eq s.stack y.stack)``,
  rw[]>>Cases_on`b`>>TRY(PairCases_on`x'`)>>fs[push_env_def]>>
  fs[LET_THM,env_to_list_def]>>Cases_on`t.stack`>>
  fs[s_key_eq_def,pop_env_def]>>BasicProvers.EVERY_CASE_TAC>>
  fs[domain_fromAList,s_frame_key_eq_def]>>
  qpat_assum `A = MAP FST l` (SUBST1_TAC o SYM)>>
  fs[EXTENSION,mem_list_rearrange,MEM_MAP,QSORT_MEM,MEM_toAList
    ,EXISTS_PROD,domain_lookup])

val pop_env_frame = store_thm("pop_env_frame",
  ``s_val_eq r'.stack st' ∧
    s_key_eq y'.stack y''.stack ∧
    pop_env (r' with stack:= st') = SOME y'' ∧
    pop_env r' = SOME y'
    ⇒
    word_state_eq_rel y' y''``,
    fs[pop_env_def]>>EVERY_CASE_TAC>>
    fs[s_val_eq_def,s_frame_val_eq_def,word_state_eq_rel_def
      ,state_component_equality]>>
    rw[]>>rfs[]>>
    metis_tac[s_val_and_key_eq])

val key_map_implies = store_thm("key_map_implies",
 ``MAP (λx,y.f x,y) l' = l
 ⇒ MAP f (MAP FST l') = MAP FST l``,
 rw[]>>match_mp_tac LIST_EQ>>
 rw[EL_MAP]>>
 Cases_on`EL x l'`>>fs[])

(*Main proof of liveness theorem starts here*)

val apply_colour_exp_lemma = prove(
  ``∀st w cst f res.
    word_exp st w = SOME res ∧
    word_state_eq_rel st cst ∧
    strong_locals_rel f (domain (get_live_exp w)) st.locals cst.locals
    ⇒
    word_exp cst (apply_colour_exp f w) = SOME res``,
  ho_match_mp_tac word_exp_ind>>rw[]>>
  fs[word_exp_def,apply_colour_exp_def,strong_locals_rel_def
    ,get_live_exp_def,word_state_eq_rel_def]
  >-
    (EVERY_CASE_TAC>>fs[])
  >-
    (Cases_on`word_exp st w`>>fs[]>>
    `mem_load x st = mem_load x cst` by
      fs[mem_load_def]>>fs[])
  >-
    (fs[LET_THM]>>
    `MAP (\a.word_exp st a) wexps =
     MAP (\a.word_exp cst a) (MAP (\a. apply_colour_exp f a) wexps)` by
       (simp[MAP_MAP_o] >>
       simp[MAP_EQ_f] >>
       gen_tac >>
       strip_tac >>
       first_assum(fn th => first_x_assum(mp_tac o C MATCH_MP th)) >>
       fs[EVERY_MEM,MEM_MAP,PULL_EXISTS
         ,miscTheory.IS_SOME_EXISTS] >>
       first_assum(fn th => first_x_assum(mp_tac o C MATCH_MP th)) >>
       strip_tac >>
       disch_then(qspecl_then[`cst`,`f`,`x`]mp_tac) >>
       discharge_hyps
       >-
         (fs[]>>
         imp_res_tac domain_FOLDR_union_subset>>
         rw[]>>
         metis_tac[SUBSET_DEF])>>
       fs[]) >>
     pop_assum(SUBST1_TAC o SYM) >>
     simp[EQ_SYM_EQ])
  >>
    EVERY_CASE_TAC>>fs[]>>res_tac>>fs[]>>
    metis_tac[])

(*Frequently used tactics*)
val exists_tac = qexists_tac`cst.permute`>>
    fs[evaluate_def,LET_THM,word_state_eq_rel_def
      ,get_live_def,colouring_ok_def];

val exists_tac_2 =
    Cases_on`word_exp st e`>>fs[word_exp_perm]>>
    imp_res_tac apply_colour_exp_lemma>>
    pop_assum (qspecl_then[`f`,`cst`] mp_tac)>>
    discharge_hyps
    >-
      metis_tac[SUBSET_OF_INSERT,domain_union,SUBSET_UNION
               ,strong_locals_rel_subset];

val setup_tac = Cases_on`word_exp st exp`>>fs[]>>
      imp_res_tac apply_colour_exp_lemma>>
      pop_assum(qspecl_then[`f`,`cst`]mp_tac)>>unabbrev_all_tac;

val LAST_N_LENGTH2 = prove(``
  LAST_N (LENGTH xs +1) (x::xs) = x::xs``,
  `LENGTH (x::xs) = LENGTH xs +1` by simp[]>>
  metis_tac[LAST_N_LENGTH])

val toAList_not_empty = prove(``
  domain t ≠ {} ⇒
  toAList t ≠ []``,
  CCONTR_TAC>>fs[GSYM MEMBER_NOT_EMPTY]>>
  fs[GSYM toAList_domain])

(*liveness theorem*)
val evaluate_apply_colour = store_thm("evaluate_apply_colour",
``∀prog st cst f live.
  colouring_ok f prog live ∧
  word_state_eq_rel st cst ∧
  strong_locals_rel f (domain (get_live prog live)) st.locals cst.locals
  ⇒
  ∃perm'.
  let (res,rst) = evaluate(prog,st with permute:=perm') in
  if (res = SOME Error) then T else
  let (res',rcst) = evaluate(apply_colour f prog,cst) in
    res = res' ∧
    word_state_eq_rel rst rcst ∧
    (case res of
      NONE => strong_locals_rel f (domain live)
              rst.locals rcst.locals
    | SOME _ => rst.locals = rcst.locals )``,
  (*Induct on size of program*)
  completeInduct_on`prog_size (K 0) prog`>>
  rpt strip_tac>>
  fs[PULL_FORALL,evaluate_def]>>
  Cases_on`prog`
  >- (*Skip*)
    exists_tac
  >- (*Move*)
    (exists_tac>>
    fs[MAP_ZIP,get_writes_def,domain_union,domain_numset_list_insert]>>
    Cases_on`ALL_DISTINCT (MAP FST l)`>>fs[]>>
    `ALL_DISTINCT (MAP f (MAP FST l))` by
      (match_mp_tac ALL_DISTINCT_MAP_INJ>>rw[]>>
      FULL_SIMP_TAC bool_ss [INJ_DEF]>>
      first_x_assum(qspecl_then[`x`,`y`] assume_tac)>>
      simp[])>>
    fs[MAP_MAP_o,get_vars_perm] >>
    Cases_on`get_vars (MAP SND l) st`>>fs[]>>
    `get_vars (MAP f (MAP SND l)) cst = SOME x` by
      (imp_res_tac strong_locals_rel_get_vars>>
      first_x_assum(qspec_then `MAP SND ls` mp_tac)>>fs[])>>
    fs[set_vars_def,MAP_MAP_o]>>
    fs[strong_locals_rel_def]>>rw[]>>
    `LENGTH l = LENGTH x` by
      metis_tac[LENGTH_MAP,get_vars_length_lemma]>>
    fs[lookup_alist_insert]>>
    Cases_on`ALOOKUP (ZIP (MAP FST l,x)) n'`>>fs[]
    >-
    (*NONE:
      Therefore n is not in l but it is in live and so it is not deleted
     *)
      (`n' ∈ domain (FOLDR delete live (MAP FST l))` by
        (fs[domain_FOLDR_delete]>>
        fs[ALOOKUP_NONE]>>rfs[MAP_ZIP])>>
      EVERY_CASE_TAC>>fs[]>>
      imp_res_tac ALOOKUP_MEM>>
      pop_assum mp_tac>>
      fs[MEM_ZIP]>>strip_tac>>
      rfs[EL_MAP,ALOOKUP_NONE]>>
      rfs[MAP_ZIP]>>
      `n' = FST (EL n'' l)` by
        (FULL_SIMP_TAC bool_ss [INJ_DEF]>>
        first_assum(qspecl_then[`n'`,`FST (EL n'' l)`] mp_tac)>>
        discharge_hyps>-
          (rw[]>>DISJ1_TAC>>
          metis_tac[MEM_MAP,MEM_EL])>>
        metis_tac[])>>
      metis_tac[MEM_EL,MEM_MAP])
    >>
      imp_res_tac ALOOKUP_MEM>>
      `ALOOKUP (ZIP (MAP (f o FST) l ,x)) (f n') = SOME v'` by
        (match_mp_tac ALOOKUP_ALL_DISTINCT_MEM>>
        pop_assum mp_tac>>
        fs[MAP_ZIP,MEM_ZIP,LENGTH_MAP]>>strip_tac>>fs[]>>
        HINT_EXISTS_TAC>>fs[EL_MAP])>>
      fs[])
  >- (*Inst*)
    (exists_tac>>
    Cases_on`i`>> (TRY (Cases_on`a`))>> (TRY(Cases_on`m`))>>
    fs[get_live_def,get_live_inst_def,inst_def,assign_def
      ,word_exp_perm]
    >-
      (Cases_on`word_exp st (Const c)`>>
      fs[word_exp_def,set_var_def,strong_locals_rel_def,get_writes_def
        ,get_writes_inst_def,domain_union,lookup_insert]>>
      rw[]>>
      FULL_SIMP_TAC bool_ss [INJ_DEF]>>
      first_x_assum(qspecl_then [`n'`,`n`] assume_tac)>>fs[])
    >-
      (Cases_on`r`>>fs[]>>
      qpat_abbrev_tac `exp = (Op b [Var n0;B])`>>setup_tac>>
      (discharge_hyps
      >-
        (fs[get_live_exp_def,domain_union]>>
        `{n0} ⊆ (n0 INSERT domain live DELETE n)` by fs[SUBSET_DEF]>>
        TRY(`{n0} ∪ {n'} ⊆ (n0 INSERT n' INSERT domain live DELETE n)` by
          fs[SUBSET_DEF])>>
        metis_tac[strong_locals_rel_subset])
      >>
      fs[apply_colour_exp_def,word_state_eq_rel_def]>>
      fs[set_var_def,strong_locals_rel_def,lookup_insert,get_writes_def
        ,get_writes_inst_def]>>
      rw[]>>
      TRY(qpat_abbrev_tac `n''=n'`)>>
      Cases_on`n''=n`>>fs[]>>
      `f n'' ≠ f n` by
        (fs[domain_union]>>
        FULL_SIMP_TAC bool_ss [INJ_DEF]>>
        first_x_assum(qspecl_then[`n''`,`n`] mp_tac)>>
        discharge_hyps>-
          rw[]>>
        metis_tac[])>>
      fs[]))
    >-
      (qpat_abbrev_tac`exp = (Shift s (Var n0) B)`>>
      setup_tac>>
      discharge_hyps>-
        (fs[get_live_exp_def]>>
        `{n0} ⊆ n0 INSERT domain live DELETE n` by fs[SUBSET_DEF]>>
        metis_tac[SUBSET_OF_INSERT,strong_locals_rel_subset])>>
      fs[word_exp_def,word_state_eq_rel_def,set_var_def]>>
      Cases_on`lookup n0 st.locals`>>fs[strong_locals_rel_def]>>
      res_tac>>
      fs[lookup_insert]>>
      rw[]>>
      Cases_on`n=n'`>>fs[]>>
      `f n' ≠ f n` by
        (fs[domain_union,get_writes_inst_def,get_writes_def]>>
        FULL_SIMP_TAC bool_ss [INJ_DEF]>>
        first_x_assum(qspecl_then[`n'`,`n`]mp_tac)>>
        discharge_hyps>-rw[]>>
        metis_tac[])>>
      fs[])
    >-
      (fs [mem_load_def]>> fs [GSYM mem_load_def]>>
      qpat_abbrev_tac`exp=((Op Add [Var n';A]))`>>
      setup_tac>>
      discharge_hyps>-
        (fs[get_live_exp_def]>>
        `{n'} ⊆ n' INSERT domain live DELETE n` by fs[SUBSET_DEF]>>
        metis_tac[strong_locals_rel_subset])>>
      fs[word_state_eq_rel_def,LET_THM,set_var_def]>>
      rw[strong_locals_rel_def]>>
      BasicProvers.CASE_TAC >> fs []>>
      fs[lookup_insert]>>
      rpt strip_tac >>
      Cases_on`n''=n`>>fs[]>>
      `f n'' ≠ f n` by
        (fs[domain_union,get_writes_def,get_writes_inst_def]>>
        FULL_SIMP_TAC bool_ss [INJ_DEF]>>
        first_x_assum(qspecl_then[`n''`,`n`]mp_tac)>>
        discharge_hyps>-rw[]>>
        metis_tac[])>>
      fs[strong_locals_rel_def])
    >>
      (qpat_abbrev_tac`exp=Op Add [Var n';A]`>>
      setup_tac>>
      discharge_hyps>-
        (fs[get_live_exp_def]>>
        `{n'} ⊆ n' INSERT n INSERT domain live` by fs[SUBSET_DEF]>>
        metis_tac[strong_locals_rel_subset])>>
      fs[word_state_eq_rel_def,LET_THM,set_var_def]>>
      rw[get_var_perm]>>
      Cases_on`get_var n st`>>fs[]>>
      imp_res_tac strong_locals_rel_get_var>>
      Cases_on`mem_store x x' st`>>fs[mem_store_def,strong_locals_rel_def]))
  >- (*Assign*)
    (exists_tac>>exists_tac_2>>
    rw[word_state_eq_rel_def,set_var_perm,set_var_def]>>
    fs[strong_locals_rel_def]>>rw[]>>
    fs[lookup_insert]>>Cases_on`n=n'`>>fs[get_writes_def]>>
    `f n' ≠ f n` by
      (FULL_SIMP_TAC bool_ss [INJ_DEF]>>
      first_x_assum(qspecl_then [`n`,`n'`] mp_tac)>>
      rw[domain_union,domain_delete])>>
    fs[domain_union])
  >- (*Get*)
    (exists_tac>>
    EVERY_CASE_TAC>>
    fs[colouring_ok_def,set_var_def,strong_locals_rel_def,get_live_def]>>
    fs[LET_THM,get_writes_def]>>rw[]>>
    fs[lookup_insert]>>Cases_on`n'=n`>>fs[]>>
    `f n' ≠ f n` by
      (FULL_SIMP_TAC bool_ss [INJ_DEF,domain_union,domain_insert]>>
      first_x_assum(qspecl_then[`n`,`n'`] assume_tac)>>
      rfs[])>>
    fs[])
  >- (*Set*)
    (exists_tac>>exists_tac_2>>
    rw[]>>
    rfs[set_store_def,word_state_eq_rel_def,get_var_perm]>>
    metis_tac[SUBSET_OF_INSERT,strong_locals_rel_subset
             ,domain_union,SUBSET_UNION])
  >- (*Store*)
    (exists_tac>>exists_tac_2>>
    rw[]>>
    rfs[set_store_def,word_state_eq_rel_def,get_var_perm]>>
    Cases_on`get_var n st`>>fs[]>>
    imp_res_tac strong_locals_rel_get_var>>
    fs[mem_store_def]>>
    EVERY_CASE_TAC>>fs[]>>
    metis_tac[SUBSET_OF_INSERT,strong_locals_rel_subset
             ,domain_union,SUBSET_UNION])
  >- (*Call*)
    (fs[evaluate_def,LET_THM,colouring_ok_def,get_live_def,get_vars_perm]>>
    Cases_on`get_vars l st`>>fs[]>>
    Cases_on`bad_dest_args o1 l`>- fs[bad_dest_args_def]>>
    `¬bad_dest_args o1 (MAP f l)` by fs[bad_dest_args_def]>>
    imp_res_tac strong_locals_rel_get_vars>>
    pop_assum kall_tac>>
    pop_assum mp_tac>>discharge_hyps>-
      (rw[domain_numset_list_insert]>>
      EVERY_CASE_TAC>>fs[domain_numset_list_insert,domain_union])>>
    pop_assum kall_tac>>rw[]>>
    Cases_on`find_code o1 (add_ret_loc o' x) st.code`>>
    fs[word_state_eq_rel_def]>>
    Cases_on`x'`>>fs[]>>
    FULL_CASE_TAC
    >-
    (*Tail call*)
      (Cases_on`o0`>>fs[]>>
      qexists_tac`cst.permute`>>fs[]>>
      Cases_on`st.clock=0`>-fs[call_env_def]>>
      fs[]>>
      `call_env q (dec_clock cst) =
       call_env q (dec_clock(st with permute:= cst.permute))` by
        rfs[call_env_def,dec_clock_def,state_component_equality]>>
      rfs[]>>EVERY_CASE_TAC>>
      fs[])
    >>
    (*Returning calls*)
    PairCases_on`x'`>>fs[]>>
    Cases_on`domain x'1 = {}`>>fs[]>>
    Cases_on`cut_env x'1 st.locals`>>fs[]>>
    imp_res_tac cut_env_lemma>>
    pop_assum kall_tac>>
    pop_assum (qspecl_then [`cst.locals`,`f`] mp_tac)>>
    discharge_hyps>-
      fs[strong_locals_rel_def,domain_union]>>
    discharge_hyps>-
      (fs[colouring_ok_def,LET_THM,domain_union]>>
      `domain x'1 ⊆ x'0 INSERT domain x'1` by fs[SUBSET_DEF]>>
      metis_tac[SUBSET_UNION,INJ_less,INSERT_UNION_EQ])>>
    rw[]>>
    fs[domain_fromAList,toAList_not_empty]>>
    Cases_on`st.clock=0`>>fs[call_env_def,add_ret_loc_def]>>
    qpat_abbrev_tac`f_o0=
      case o0 of NONE => NONE
      | SOME (v,prog,l1,l2) => SOME (f v,apply_colour f prog,l1,l2)`>>
    Q.ISPECL_THEN[
      `y`,`x'`,`st with clock := st.clock-1`,
      `f`,`cst with clock := st.clock-1`,`f_o0`,`o0`,`λn. cst.permute (n+1)`]
      mp_tac (GEN_ALL push_env_s_val_eq)>>
    discharge_hyps>-
      (rfs[LET_THM,Abbr`f_o0`]>>EVERY_CASE_TAC>>fs[])>>
    rw[]>>
    rfs[LET_THM,env_to_list_def,dec_clock_def]>>
    qabbrev_tac `envx = push_env x' o0
            (st with <|permute := perm; clock := st.clock − 1|>) with
          locals := fromList2 (q)`>>
    qpat_abbrev_tac `envy = (push_env y A B) with <| locals := C; clock := _ |>`>>
    assume_tac evaluate_stack_swap>>
    pop_assum(qspecl_then [`r`,`envx`] mp_tac)>>
    ntac 2 FULL_CASE_TAC>-
      (rw[]>>qexists_tac`perm`>>fs[dec_clock_def])>>
    `envx with stack := envy.stack = envy` by
      (unabbrev_all_tac>>
      Cases_on`o0`>>TRY(PairCases_on`x'''`)>>
      fs[push_env_def,state_component_equality]>>
      fs[LET_THM,env_to_list_def,dec_clock_def])>>
    `s_val_eq envx.stack envy.stack` by
      (unabbrev_all_tac>>
       fs[state_component_equality])>>
    FULL_CASE_TAC
    >-
    (*Result*)
    (strip_tac>>pop_assum(qspec_then`envy.stack` mp_tac)>>
    discharge_hyps>-
      (unabbrev_all_tac>>
       fs[state_component_equality,dec_clock_def])>>
    strip_tac>>fs[]>>
    rfs[]>>
    IF_CASES_TAC>>fs[]>-
      (qexists_tac`perm`>>fs[])>>
    (*Backwards chaining*)
    fs[Abbr`envy`,Abbr`envx`,state_component_equality]>>
    Q.ISPECL_THEN [`(cst with clock := st.clock-1)`,
                  `r' with stack := st'`,`y`,`f_o0`]
                  mp_tac push_env_pop_env_s_key_eq>>
    discharge_hyps>-
      (unabbrev_all_tac>>fs[])>>
    Q.ISPECL_THEN [`(st with <|permute:=perm;clock := st.clock-1|>)`,
                  `r'`,`x'`,`o0`]
                  mp_tac push_env_pop_env_s_key_eq>>
    discharge_hyps>-
      (unabbrev_all_tac>>fs[])>>
    ntac 2 strip_tac>>
    rfs[]>>
    (*Now we can finally use the IH*)
    last_x_assum(qspecl_then[`x'2`,`set_var x'0 w0 y'`
                            ,`set_var (f x'0) w0 y''`,`f`,`live`]mp_tac)>>
    discharge_hyps>-size_tac>>
    fs[colouring_ok_def]>>
    discharge_hyps>-
      (Cases_on`o0`>>TRY(PairCases_on`x''`)>>fs[]>>
      unabbrev_all_tac>>
      fs[set_var_def,state_component_equality]>>
      `s_key_eq y'.stack y''.stack` by
        metis_tac[s_key_eq_trans,s_key_eq_sym]>>
      assume_tac pop_env_frame>>rfs[word_state_eq_rel_def]>>
      fs[colouring_ok_def,LET_THM,strong_locals_rel_def]>>
      rw[]>>
      fs[push_env_def,LET_THM,env_to_list_def]>>
      fs[s_key_eq_def,s_val_eq_def]>>
      Cases_on`opt`>>TRY(PairCases_on`x''`)>>
      Cases_on`opt'`>>TRY(PairCases_on`x''`)>>
      fs[s_frame_key_eq_def,s_frame_val_eq_def]>>
      Cases_on`n=x'0`>>
      fs[lookup_insert]>>
      `f n ≠ f x'0` by
        (imp_res_tac domain_lookup>>
        fs[domain_fromAList]>>
        (*some assumption movements to make this faster*)
        qpat_assum `INJ f (x'0 INSERT A) B` mp_tac>>
        rpt (qpat_assum `INJ f A B` kall_tac)>>
        strip_tac>>
        FULL_SIMP_TAC bool_ss [INJ_DEF]>>
        pop_assum(qspecl_then [`n`,`x'0`] mp_tac)>>
        rw[domain_union])>>
      fs[lookup_fromAList]>>
      imp_res_tac key_map_implies>>
      rfs[]>>
      `l'' = ZIP(MAP FST l'',MAP SND l'')` by fs[ZIP_MAP_FST_SND_EQ]>>
      pop_assum SUBST1_TAC>>
      pop_assum (SUBST1_TAC o SYM)>>
      match_mp_tac ALOOKUP_key_remap_2>>
      fs[]>>CONJ_TAC>>
      metis_tac[LENGTH_MAP,ZIP_MAP_FST_SND_EQ])>>
    strip_tac>>
    qspecl_then[`r`,`push_env x' o0
            (st with <|permute := perm; clock := st.clock − 1|>) with
          locals := fromList2 (q)`,`perm'`]
      assume_tac permute_swap_lemma>>
    rfs[LET_THM]>>
    (*"Hot-swap" the suffix of perm, maybe move into lemma*)
    qexists_tac`λn. if n = 0:num then perm 0 else perm'' (n-1)`>>
    qpat_abbrev_tac `env1 = push_env A B C with locals := D`>>
    qpat_assum `A = (SOME B,C)` mp_tac>>
    qpat_abbrev_tac `env2 = push_env A B C with
                    <|locals:=D; permute:=E|>`>>
    strip_tac>>
    Cases_on`o0`>>TRY(PairCases_on`x''`)>>fs[]>>
    `env1 = env2` by
      (unabbrev_all_tac>>
      rpt (pop_assum kall_tac)>>
      simp[push_env_def,LET_THM,env_to_list_def
        ,state_component_equality,ETA_AX])>>
    fs[pop_env_perm,set_var_perm]>>
    EVERY_CASE_TAC>>fs[])
    >-
    (*Exceptions*)
    (fs[]>>strip_tac>>
    imp_res_tac s_val_eq_LAST_N_exists>>
    first_x_assum(qspecl_then[`envy.stack`,`e'`,`ls'`] assume_tac)>>
    rfs[]>>
    Cases_on`o0`
    >-
      (*No handler*)
      (fs[Abbr`f_o0`]>>
      qexists_tac`perm`>>
      `ls=ls'` by
        (unabbrev_all_tac>>
        fs[push_env_def,env_to_list_def,LET_THM]>>
        Cases_on`st.handler < LENGTH st.stack`
        >-
          (imp_res_tac LAST_N_TL>>
          rfs[]>>fs[])
        >>
          `st.handler = LENGTH st.stack` by DECIDE_TAC>>
          rpt (qpat_assum `LAST_N A B = C` mp_tac)>-
          simp[LAST_N_LENGTH_cond])>>
      rfs[]>>
      `lss = lss'` by
        (match_mp_tac LIST_EQ_MAP_PAIR>>fs[]>>
        qsuff_tac `e = e''`>-metis_tac[]>>
        unabbrev_all_tac>>
        fs[push_env_def,LET_THM,env_to_list_def]>>
        `st.handler < LENGTH st.stack` by
          (SPOSE_NOT_THEN assume_tac>>
          `st.handler = LENGTH st.stack` by DECIDE_TAC>>
          ntac 2 (qpat_assum`LAST_N A B = C` mp_tac)>>
          simp[LAST_N_LENGTH2])>>
        ntac 2 (qpat_assum`LAST_N A B = C` mp_tac)>>
        fs[LAST_N_TL])>>
      metis_tac[s_val_and_key_eq,s_key_eq_sym,s_key_eq_trans])
    >>
      (*Handler*)
      PairCases_on`x''`>>fs[]>>
      unabbrev_all_tac>>
      fs[push_env_def,LET_THM,env_to_list_def]>>
      IF_CASES_TAC>-
        (qexists_tac`perm`>>fs[])>>
      rpt (qpat_assum `LAST_N A B = C` mp_tac)>>
      simp[LAST_N_LENGTH_cond]>>
      rpt strip_tac>>
      fs[domain_fromAList]>>
      imp_res_tac list_rearrange_keys>>
      `set (MAP FST lss') = domain y` by
        (qpat_assum`A=MAP FST lss'` (SUBST1_TAC o SYM)>>
        fs[EXTENSION]>>rw[EXISTS_PROD]>>
        simp[MEM_MAP,QSORT_MEM]>>rw[EQ_IMP_THM]
        >-
          (Cases_on`y'`>>
          fs[MEM_toAList]>>
          imp_res_tac domain_lookup>>
          metis_tac[])
        >>
          fs[EXISTS_PROD,MEM_toAList]>>
          metis_tac[domain_lookup])>>
      `domain x' = set (MAP FST lss)` by
        (qpat_assum `A = MAP FST lss` (SUBST1_TAC o SYM)>>
          fs[EXTENSION,MEM_MAP,QSORT_MEM,MEM_toAList
            ,EXISTS_PROD,domain_lookup])>>
      fs[]>>
      qpat_abbrev_tac `cr'=r' with<|locals:= A;stack:=B;handler:=C|>`>>
      (*Use the IH*)
      last_x_assum(qspecl_then[`x''1`,`set_var x''0 w0 r'`
                            ,`set_var (f x''0) w0 cr'`,`f`,`live`]mp_tac)>>
      discharge_hyps>-size_tac>>
      fs[colouring_ok_def]>>
      discharge_hyps>-
      (fs[set_var_def,state_component_equality,Abbr`cr'`]>>
      fs[colouring_ok_def,LET_THM,strong_locals_rel_def]>>
      rw[]>-metis_tac[s_key_eq_trans,s_val_and_key_eq]>>
      Cases_on`n' = x''0`>>fs[lookup_insert]>>
      `f n' ≠ f x''0` by
        (imp_res_tac domain_lookup>>
        fs[domain_fromAList]>>
        qpat_assum `INJ f (q' INSERT A) B` mp_tac>>
        qpat_assum `INJ f A B` kall_tac>>
        `n' ∈ set (MAP FST lss)` by fs[]>>
        `n' ∈ domain x'1` by
          (fs[domain_union]>>metis_tac[])>>
        ntac 4 (pop_assum mp_tac)>>
        rpt (pop_assum kall_tac)>>
        rw[]>>
        CCONTR_TAC>>
        FULL_SIMP_TAC bool_ss [INJ_DEF]>>
        first_x_assum(qspecl_then[`n'`,`x''0`] mp_tac)>>
        fs[])>>
      fs[lookup_fromAList]>>
      imp_res_tac key_map_implies>>
      rfs[]>>
      `lss' = ZIP(MAP FST lss',MAP SND lss')` by fs[ZIP_MAP_FST_SND_EQ]>>
      pop_assum SUBST1_TAC>>
      pop_assum (SUBST1_TAC o SYM)>>
      match_mp_tac ALOOKUP_key_remap_2>>
      fs[]>>CONJ_TAC>>
      metis_tac[LENGTH_MAP,ZIP_MAP_FST_SND_EQ])>>
      rw[]>>
      qspecl_then[`r`,`st with <|locals := fromList2 (q);
            stack :=
            StackFrame (list_rearrange (perm 0)
              (QSORT key_val_compare ( (toAList x'))))
              (SOME (r'.handler,x''2,x''3))::st.stack;
            permute := (λn. perm (n + 1)); handler := LENGTH st.stack;
            clock := st.clock − 1|>`,`perm'`]
        assume_tac permute_swap_lemma>>
      rfs[LET_THM]>>
      (*"Hot-swap" the suffix of perm, maybe move into lemma*)
      qexists_tac`λn. if n = 0:num then perm 0 else perm'' (n-1)`>>
      `(λn. perm'' n) = perm''` by fs[FUN_EQ_THM]>>
      `domain (fromAList lss) = domain x'1` by
        metis_tac[domain_fromAList]>>
      fs[set_var_perm])
    >>
    (*The rest*)
    rw[]>>qexists_tac`perm`>>fs[]>>
    pop_assum(qspec_then`envy.stack` mp_tac)>>
    discharge_hyps>-
      (unabbrev_all_tac>>fs[state_component_equality])>>
    rw[]>>fs[]>>NO_TAC)
   >- (*Seq*)
    (rw[]>>fs[evaluate_def,colouring_ok_def,LET_THM,get_live_def]>>
    last_assum(qspecl_then[`p`,`st`,`cst`,`f`,`get_live p0 live`]
      mp_tac)>>
    discharge_hyps>-size_tac>>
    rw[]>>
    Cases_on`evaluate(p,st with permute:=perm')`>>fs[]
    >- (qexists_tac`perm'`>>fs[]) >>
    Cases_on`evaluate(apply_colour f p,cst)`>>fs[]>>
    reverse (Cases_on`q`)>>fs[]
    >-
      (qexists_tac`perm'`>>rw[])
    >>
    first_assum(qspecl_then[`p0`,`r`,`r'`,`f`,`live`] mp_tac)>>
    discharge_hyps>- size_tac>>
    rw[]>>
    qspecl_then[`p`,`st with permute:=perm'`,`perm''`]
      assume_tac permute_swap_lemma>>
    rfs[LET_THM]>>
    qexists_tac`perm'''`>>rw[]>>fs[])
  >- (*If*)
    (fs[evaluate_def,colouring_ok_def,LET_THM,get_live_def]>>
    fs[get_var_perm]>>
    Cases_on`get_var n st`>>fs[]>>imp_res_tac strong_locals_rel_get_var>>
    pop_assum kall_tac>>pop_assum mp_tac>>discharge_hyps>-
      (FULL_CASE_TAC>>fs[])
    >>
    rw[]>>
    Cases_on`x`>>fs[]>>
    fs[get_var_imm_perm]>>
    Cases_on`get_var_imm r st`>>fs[]>>
    imp_res_tac strong_locals_rel_get_var_imm>>
    pop_assum kall_tac>>pop_assum mp_tac>>discharge_hyps>-
      (Cases_on`r`>>fs[])>>
    Cases_on`x`>>rw[]>>fs[]
    >-
     (first_assum(qspecl_then[`p`,`st`,`cst`,`f`,`live`] mp_tac)>>
      discharge_hyps>- size_tac>>
      discharge_hyps>-
        (Cases_on`r`>>
        fs[domain_insert,domain_union]>>
        metis_tac[SUBSET_OF_INSERT,SUBSET_UNION,strong_locals_rel_subset])>>
      rw[]>>
      qspecl_then[`w`,`st with permute:=perm'`,`perm''`]
        assume_tac permute_swap_lemma>>
      rfs[LET_THM]>>
      qexists_tac`perm'''`>>rw[get_var_perm]>>fs[])
    >>
      (first_assum(qspecl_then[`p0`,`st`,`cst`,`f`,`live`] mp_tac)>>
      discharge_hyps>- size_tac>>
      discharge_hyps>-
        (Cases_on`r`>>fs[domain_insert,domain_union]>>
        metis_tac[SUBSET_OF_INSERT,SUBSET_UNION,strong_locals_rel_subset])>>
      rw[]>>
      qspecl_then[`p`,`st with permute:=perm'`,`perm''`]
        assume_tac permute_swap_lemma>>
      rfs[LET_THM]>>
      qexists_tac`perm'''`>>rw[get_var_perm]>>fs[]))
  >- (*Alloc*)
    (fs[evaluate_def,colouring_ok_def,get_var_perm,get_live_def]>>
    Cases_on`get_var n st`>>fs[LET_THM]>>
    imp_res_tac strong_locals_rel_get_var>>fs[]>>
    Cases_on`x`>>fs[alloc_def]>>
    Cases_on`cut_env s st.locals`>>fs[]>>
    `domain s ⊆ (n INSERT domain s)` by fs[SUBSET_DEF]>>
    imp_res_tac strong_locals_rel_subset>>
    imp_res_tac cut_env_lemma>>
    pop_assum mp_tac>>discharge_hyps
    >-
      (match_mp_tac (GEN_ALL INJ_less)>>metis_tac[])
    >>
    rw[]>>fs[set_store_def]>>
    qpat_abbrev_tac`non = NONE`>>
    Q.ISPECL_THEN [`y`,`x`,`st with store:= st.store |+ (AllocSize,Word c)`,
    `f`,`cst with store:= cst.store |+ (AllocSize,Word c)`,`non`,`non`,`cst.permute`] assume_tac  (GEN_ALL push_env_s_val_eq)>>
    rfs[word_state_eq_rel_def,Abbr`non`]>>
    qexists_tac`perm`>>fs[]>>
    qpat_abbrev_tac `st' = push_env x NONE A`>>
    qpat_abbrev_tac `cst' = push_env y NONE B`>>
    Cases_on`gc st'`>>fs[]>>
    Q.ISPECL_THEN [`st'`,`cst'`,`x'`] mp_tac gc_s_val_eq_gen>>
    discharge_hyps_keep>-
      (unabbrev_all_tac>>
      fs[push_env_def,LET_THM,env_to_list_def,word_state_eq_rel_def]>>
      rfs[])
    >>
    rw[]>>simp[]>>
    unabbrev_all_tac>>
    imp_res_tac gc_frame>>
    imp_res_tac push_env_pop_env_s_key_eq>>
    Cases_on`pop_env x'`>>fs[]>>
    `strong_locals_rel f (domain live) x''.locals y'.locals ∧
     word_state_eq_rel x'' y'` by
      (imp_res_tac gc_s_key_eq>>
      fs[push_env_def,LET_THM,env_to_list_def]>>
      ntac 2(pop_assum mp_tac>>simp[Once s_key_eq_sym])>>
      ntac 2 strip_tac>>
      rpt (qpat_assum `s_key_eq A B` mp_tac)>>
      qpat_abbrev_tac `lsA = list_rearrange (cst.permute 0)
        (QSORT key_val_compare ( (toAList y)))`>>
      qpat_abbrev_tac `lsB = list_rearrange (perm 0)
        (QSORT key_val_compare ( (toAList x)))`>>
      ntac 4 strip_tac>>
      Q.ISPECL_THEN [`x'.stack`,`y'`,`t'`,`NONE:(num#num#num) option`
        ,`lsA`,`cst.stack`] mp_tac (GEN_ALL s_key_eq_val_eq_pop_env)>>
      discharge_hyps
      >-
        (fs[]>>metis_tac[s_key_eq_sym,s_val_eq_sym])
      >>
      Q.ISPECL_THEN [`t'.stack`,`x''`,`x'`,`NONE:(num#num#num) option`
        ,`lsB`,`st.stack`] mp_tac (GEN_ALL s_key_eq_val_eq_pop_env)>>
      discharge_hyps
      >-
        (fs[]>>metis_tac[s_key_eq_sym,s_val_eq_sym])
      >>
      rw[]
      >-
        (simp[]>>
        fs[strong_locals_rel_def,lookup_fromAList]>>
        `MAP SND l = MAP SND ls'` by
          fs[s_val_eq_def,s_frame_val_eq_def]>>
        rw[]>>
        `MAP FST (MAP (λ(x,y). (f x,y)) lsB) =
         MAP f (MAP FST lsB)` by
          fs[MAP_MAP_o,MAP_EQ_f,FORALL_PROD]>>
        fs[]>>
        match_mp_tac ALOOKUP_key_remap_2>>rw[]>>
        metis_tac[s_key_eq_def,s_frame_key_eq_def,LENGTH_MAP])
      >>
        fs[word_state_eq_rel_def,pop_env_def]>>
        rfs[state_component_equality]>>
        metis_tac[s_val_and_key_eq,s_key_eq_sym
          ,s_val_eq_sym,s_key_eq_trans])>>
    fs[word_state_eq_rel_def]>>FULL_CASE_TAC>>fs[has_space_def]>>
    Cases_on`x'''`>>
    EVERY_CASE_TAC>>fs[call_env_def])
    >- (* Raise *)
      (exists_tac>>
      Cases_on`get_var n st`>>fs[get_var_perm]>>
      imp_res_tac strong_locals_rel_get_var>>fs[jump_exc_def]>>
      EVERY_CASE_TAC>>fs[])
    >- (* Return *)
      (exists_tac>>
      Cases_on`get_var n st`>>fs[get_var_perm]>>
      Cases_on`get_var n0 st`>>fs[get_var_perm]>>
      imp_res_tac strong_locals_rel_get_var>>
      fs[call_env_def]>>
      TOP_CASE_TAC>>fs [])
    >- (* Tick *)
      (exists_tac>>IF_CASES_TAC>>fs[call_env_def,dec_clock_def])
    >> (* FFI *)
      (exists_tac>>Cases_on`get_var n0 st`>>Cases_on`get_var n1 st`>>
      fs[get_writes_def,LET_THM,get_var_perm]>>
      Cases_on`x`>>fs[]>>Cases_on`x'`>>fs[]>>
      imp_res_tac strong_locals_rel_get_var>>fs[]>>
      Cases_on`cut_env s st.locals`>>fs[]>>
      `domain s ⊆ (n0 INSERT n1 INSERT domain s)` by fs[SUBSET_DEF]>>
      imp_res_tac strong_locals_rel_subset>>
      imp_res_tac cut_env_lemma>>
      pop_assum mp_tac >> discharge_hyps>-
        (match_mp_tac (GEN_ALL INJ_less)>>metis_tac[])>>
      rw[]>>FULL_CASE_TAC>>fs[]>>
      Cases_on`call_FFI st.ffi n x'`>>fs[strong_locals_rel_def]>>
      rw[]>>
      metis_tac[domain_lookup]));

(*Prove that we can substitute get_clash_sets for get_live*)

(*hd element is just get_live*)
val get_clash_sets_hd = prove(
``∀prog live hd ls.
  get_clash_sets prog live = (hd,ls) ⇒
  get_live prog live = hd``,
  Induct>>rw[get_clash_sets_def]>>fs[LET_THM]
  >-
    (Cases_on`o'`>>fs[get_clash_sets_def,LET_THM]>>
    PairCases_on`x`>>fs[get_clash_sets_def,get_live_def]>>
    fs[LET_THM,UNCURRY]>>
    EVERY_CASE_TAC>>fs[])
  >-
    (Cases_on`get_clash_sets prog' live`>>fs[]>>
    Cases_on`get_clash_sets prog q`>>fs[]>>
    metis_tac[get_live_def])
  >>
    Cases_on`get_clash_sets prog live`>>
    Cases_on`get_clash_sets prog' live`>>
    fs[get_live_def,LET_THM]>>metis_tac[])

(*The liveset passed in at the back is always satisfied*)
val get_clash_sets_tl = prove(
``∀prog live f.
  let (hd,ls) = get_clash_sets prog live in
  EVERY (λs. INJ f (domain s) UNIV) ls ⇒
  INJ f (domain live) UNIV``,
  completeInduct_on`prog_size (K 0) prog`>>
  fs[PULL_FORALL]>>
  rpt strip_tac>>
  Cases_on`prog`>>
  fs[colouring_ok_alt_def,LET_THM,get_clash_sets_def,get_live_def]>>
  fs[get_writes_def]
  >- metis_tac[INJ_UNION,domain_union,INJ_SUBSET,SUBSET_UNION]
  >- metis_tac[INJ_UNION,domain_union,INJ_SUBSET,SUBSET_UNION]
  >- metis_tac[INJ_UNION,domain_union,INJ_SUBSET,SUBSET_UNION]
  >- metis_tac[INJ_UNION,domain_union,INJ_SUBSET,SUBSET_UNION]
  >-
    (Cases_on`o'`>>fs[UNCURRY,get_clash_sets_def,LET_THM]
    >- metis_tac[INJ_UNION,domain_union,INJ_SUBSET,SUBSET_UNION]
    >>
    PairCases_on`x`>>fs[]>>
    first_x_assum(qspecl_then[`x2`,`live`,`f`] mp_tac)>>
    discharge_hyps >- size_tac>>rw[]>>
    fs[get_clash_sets_def,UNCURRY,LET_THM]>>
    Cases_on`o0`>>TRY (PairCases_on`x`)>>fs[])
  >>
    (first_x_assum(qspecl_then[`p0`,`live`,`f`]mp_tac)>>
    discharge_hyps>-size_tac>>rw[]>>
    fs[UNCURRY]))

val colouring_ok_alt_thm = store_thm("colouring_ok_alt_thm",
``∀f prog live.
  colouring_ok_alt f prog live
  ⇒
  colouring_ok f prog live``,
  ho_match_mp_tac (fetch "-" "colouring_ok_ind")>>
  rw[]>>
  fs[get_clash_sets_def,colouring_ok_alt_def,colouring_ok_def,LET_THM]
  >-
    (Cases_on`get_clash_sets prog' live`>>
    Cases_on`get_clash_sets prog q`>>fs[]>>
    imp_res_tac get_clash_sets_hd>>
    fs[]>>
    Q.ISPECL_THEN [`prog`,`q`,`f`] assume_tac get_clash_sets_tl>>
    rfs[LET_THM])
  >-
    (
    Cases_on`get_clash_sets prog live`>>
    Cases_on`get_clash_sets prog' live`>>
    FULL_CASE_TAC>>fs[]>>
    imp_res_tac get_clash_sets_hd>>
    fs[]>>
    metis_tac[INJ_SUBSET,SUBSET_DEF,SUBSET_OF_INSERT,domain_union,SUBSET_UNION])
  >>
    Cases_on`h`>>fs[LET_THM]
    >-
      (Cases_on`get_clash_sets prog live`>>fs[])
    >>
    PairCases_on`x`>>fs[]>>
    Cases_on`get_clash_sets prog live`>>fs[]>>
    Cases_on`get_clash_sets x1 live`>>fs[]>>
    EVERY_CASE_TAC>>
    fs[LET_THM]>>
    Cases_on`get_clash_sets prog live`>>
    fs[UNCURRY])

val fs1 = fs[LET_THM,get_clash_sets_def,every_var_def,get_live_def,domain_numset_list_insert,domain_union,EVERY_MEM,get_writes_def,every_var_inst_def,get_live_inst_def,in_clash_sets_def,every_name_def,toAList_domain]

val every_var_exp_get_live_exp = prove(
``∀exp.
  every_var_exp (λx. x ∈ domain (get_live_exp exp)) exp``,
  ho_match_mp_tac get_live_exp_ind>>
  rw[]>>fs[get_live_exp_def,every_var_exp_def]>>
  fs[EVERY_MEM]>>rw[]>>res_tac>>
  match_mp_tac every_var_exp_mono>>
  HINT_EXISTS_TAC>>fs[]>>
  metis_tac[SUBSET_DEF,domain_FOLDR_union_subset])

(*Every variable is in some clash set*)
val every_var_in_get_clash_set = store_thm("every_var_in_get_clash_set",
``∀prog live.
  let (hd,clash_sets) = get_clash_sets prog live in
  let ls = hd::clash_sets in
  (∀x. x ∈ domain live ⇒ in_clash_sets ls x) ∧
  (every_var (in_clash_sets ls) prog)``,
  completeInduct_on`prog_size (K 0) prog`>>
  ntac 2 (fs[Once PULL_FORALL])>>
  rpt strip_tac>>
  Cases_on`prog`>>fs1
  >-
    (*Move*)
    (qpat_abbrev_tac`s1 = numset_list_insert A B`>>
    qpat_abbrev_tac`s2 = union A live`>>
    rw[]
    >-
      (qexists_tac`s2`>>fs[Abbr`s2`,domain_union])
    >-
      (qexists_tac`s2`>>fs[Abbr`s2`,domain_numset_list_insert,domain_union])
    >>
      qexists_tac`s1`>>fs[Abbr`s1`,domain_numset_list_insert,domain_union])
  >-
    (Cases_on`i`>>fs1>>fs[get_writes_inst_def]
    >-
      (rw[]>>qexists_tac`union (insert n () LN) live`>>fs[domain_union])
    >-
      (Cases_on`a`>>fs1>>fs[get_writes_inst_def]>>
      EVERY_CASE_TAC>>rw[]>>
      fs[every_var_imm_def,in_clash_sets_def]>>
      TRY(qexists_tac`union (insert n () LN) live`>>fs[domain_union]>>
          NO_TAC)>>
      TRY(qexists_tac`insert n0 () (insert n' () (delete n live))`>>fs[]>>
          NO_TAC)>>
      qexists_tac`insert n0 () (delete n live)`>>fs[])
    >>
      Cases_on`m`>>Cases_on`a`>>fs1>>fs[get_writes_inst_def]>>rw[]>>
      TRY(qexists_tac`union (insert n () LN) live`>>fs[domain_union]>>
          NO_TAC)>>
      TRY(qexists_tac`insert n' () (delete n live)`>>fs[]>>NO_TAC)>>
      TRY(qexists_tac`insert n' () (insert n () live)`>>fs[]>>NO_TAC)>>
      HINT_EXISTS_TAC>>fs[])
  >-
    (rw[]>>
    TRY(qexists_tac`union (insert n () LN) live`>>fs[domain_union])>>
    Q.ISPEC_THEN `e` assume_tac every_var_exp_get_live_exp>>
    match_mp_tac every_var_exp_mono>>
    HINT_EXISTS_TAC>>rw[in_clash_sets_def]>>
    Cases_on`x=n`
    >-
      (qexists_tac`union (insert n () LN) live`>>fs[domain_union])
    >>
      (qexists_tac`union (get_live_exp e) (delete n live)`>>
      fs[domain_union]))
  >-
    (rw[]>>
    qexists_tac`union(insert n () LN) live`>>fs[domain_union])
  >-
    (rw[]>-(HINT_EXISTS_TAC>>fs[])>>
    Q.ISPEC_THEN `e` assume_tac every_var_exp_get_live_exp>>
    match_mp_tac every_var_exp_mono>>
    HINT_EXISTS_TAC>>rw[in_clash_sets_def]>>
    qexists_tac`union (get_live_exp e) live`>>
    fs[domain_union])
  >-
    (rw[]
    >-
      (HINT_EXISTS_TAC>>fs[])
    >-
      (qexists_tac `insert n () (union (get_live_exp e) live)`>>fs[])
    >>
    Q.ISPEC_THEN `e` assume_tac every_var_exp_get_live_exp>>
    match_mp_tac every_var_exp_mono>>
    HINT_EXISTS_TAC>>rw[in_clash_sets_def]>>
    qexists_tac`insert n () (union (get_live_exp e) live)`>>
    fs[domain_union])
  >-
    (*Call*)
    (Cases_on`o'`>>fs1
    >-
      (rw[]>-(HINT_EXISTS_TAC>>fs[])>>
      qexists_tac`numset_list_insert l LN`>>fs[domain_numset_list_insert])
    >>
      PairCases_on`x`>>Cases_on`o0`>>fs1
      >-
        (first_x_assum(qspecl_then[`x2`,`live`] mp_tac)>>
        discharge_hyps>- (fs[prog_size_def]>>DECIDE_TAC)>>
        Cases_on`get_clash_sets x2 live`>>rw[]
        >-
          (first_x_assum(qspec_then`x'`assume_tac)>>rfs[]>>
          HINT_EXISTS_TAC>>fs[])
        >>
        TRY(fs[every_name_def,EVERY_MEM]>>
          fs[toAList_domain])>>
        qpat_abbrev_tac`A = union x1 X`>>
        qpat_abbrev_tac`B = insert x0 () x1`>>
        TRY(qexists_tac`A`>>
          fs[Abbr`A`,domain_union,domain_numset_list_insert]>>NO_TAC)>>
        TRY(qexists_tac`B`>>fs[Abbr`B`]) >>
        match_mp_tac every_var_mono>>
        HINT_EXISTS_TAC>>fs[]>>rw[in_clash_sets_def]>>
        HINT_EXISTS_TAC>>fs[])
      >>
        PairCases_on`x`>>fs[]>>
        first_assum(qspecl_then[`x2`,`live`] mp_tac)>>
        discharge_hyps>- (fs[prog_size_def]>>DECIDE_TAC)>>
        first_x_assum(qspecl_then[`x1'`,`live`] mp_tac)>>
        discharge_hyps>- (fs[prog_size_def]>>DECIDE_TAC)>>
        Cases_on`get_clash_sets x2 live`>>
        Cases_on`get_clash_sets x1' live`>>rw[]
        >-
          (first_x_assum(qspec_then`x'`assume_tac)>>rfs[]>>
          HINT_EXISTS_TAC>>fs[])
        >>
        qpat_abbrev_tac`A = union x1 X`>>
        qpat_abbrev_tac`B = insert x0 () x1`>>
        qpat_abbrev_tac`D = insert x0' () x1`>>
        TRY(qexists_tac`A`>>
          fs[Abbr`A`,domain_union,domain_numset_list_insert]>>NO_TAC)>>
        TRY(qexists_tac`B`>>fs[Abbr`B`]>>NO_TAC) >>
        TRY(qexists_tac`D`>>fs[Abbr`D`]) >>
        match_mp_tac every_var_mono>>
        TRY(HINT_EXISTS_TAC)>>
        TRY(qexists_tac`in_clash_sets (q'::r')`)>>
        fs[]>>rw[in_clash_sets_def]>>
        HINT_EXISTS_TAC>>fs[])
  >-
    (first_assum(qspecl_then[`p0`,`live`] mp_tac)>>discharge_hyps
    >-
      (fs[prog_size_def]>>DECIDE_TAC)
    >>
    Cases_on`get_clash_sets p0 live`>>rw[]>>
    first_x_assum(qspecl_then[`p`,`q`] mp_tac)>>discharge_hyps
    >-
      (fs[prog_size_def]>>DECIDE_TAC)
    >>
    Cases_on`get_clash_sets p q`>>rw[]>>
    TRY (metis_tac[every_var_mono])>>
    match_mp_tac every_var_mono>>
    TRY(pop_assum kall_tac>>HINT_EXISTS_TAC)>>
    TRY HINT_EXISTS_TAC>>
    fs[in_clash_sets_def]>>
    metis_tac[])
  >-
    (first_assum(qspecl_then[`p0`,`live`] mp_tac)>>discharge_hyps
    >-
      (fs[prog_size_def]>>DECIDE_TAC)
    >>
    Cases_on`get_clash_sets p0 live`>>rw[]>>
    first_assum(qspecl_then[`p`,`live`] mp_tac)>>discharge_hyps
    >-
      (fs[prog_size_def]>>DECIDE_TAC)
    >>
    Cases_on`get_clash_sets p live`>>rw[]>>
    Cases_on`r`>>fs[every_var_imm_def]>>
    fs[in_clash_sets_def,domain_union]>>
    TRY(match_mp_tac every_var_mono>>fs[in_clash_sets_def]>>
      HINT_EXISTS_TAC>>rw[]>>fs[in_clash_sets_def])>>
    TRY( match_mp_tac every_var_mono>>fs[in_clash_sets_def]>>
    fs[CONJ_COMM]>>
    first_assum (match_exists_tac o concl)>>rw[]>>fs[in_clash_sets_def])>>
    res_tac>>
    TRY(qexists_tac`insert n' () (insert n () (union q' q))`>>
        fs[domain_union]>>metis_tac[domain_union])>>
    TRY(HINT_EXISTS_TAC>>metis_tac[domain_union])>>
    TRY(qexists_tac`insert n () (union q' q)`>>
        fs[domain_union]>>metis_tac[domain_union]))
  >-
    (rw[]
    >-
      (HINT_EXISTS_TAC>>fs[])
    >>
      qexists_tac`insert n () s`>>fs[])
  >-
    (rw[]>-(HINT_EXISTS_TAC>>fs[])>>
    qexists_tac`insert n () live`>>fs[])
  >-
    (rw[]>-(HINT_EXISTS_TAC>>fs[])>>
    qexists_tac`insert n () (insert n0 () live)`>>fs[])
  >-
    (rw[]>-(HINT_EXISTS_TAC>>fs[])>>
    qexists_tac`insert n0 () (insert n1 () s)`>>fs[]))

(*DONE Liveness Proof*)

(*SSA Proof*)

val size_tac = discharge_hyps>- (fs[prog_size_def]>>DECIDE_TAC)

(*This might not be the optimal invariant.. because it is very
  restrictive on the ssa_mapping*)
val ssa_locals_rel_def = Define`
  ssa_locals_rel na ssa st_locs cst_locs =
  ((∀x y. lookup x ssa = SOME y ⇒ y ∈ domain cst_locs) ∧
  (∀x y. lookup x st_locs = SOME y ⇒
    x ∈ domain ssa ∧
    lookup (THE (lookup x ssa)) cst_locs = SOME y ∧
    (is_alloc_var x ⇒ x < na)))`

(*ssa_map_ok specifies the form of ssa_maps we care about
  1) The remapped keys are ALL_DISTINCT
  2) The remap keyset is bounded, and no phy vars
*)
val ssa_map_ok_def = Define`
  ssa_map_ok na ssa =
  (∀x y. lookup x ssa = SOME y ⇒
    ¬is_phy_var y ∧ y < na ∧
    (∀z. z ≠ x ⇒ lookup z ssa ≠ SOME y))`

val list_next_var_rename_lemma_1 = prove(``
  ∀ls ssa na ls' ssa' na'.
  list_next_var_rename ls ssa na = (ls',ssa',na') ⇒
  let len = LENGTH ls in
  ALL_DISTINCT ls' ∧
  ls' = (MAP (λx. 4*x+na) (COUNT_LIST len)) ∧
  na' = na + 4* len``,
  Induct>>
  fs[list_next_var_rename_def,LET_THM,next_var_rename_def,COUNT_LIST_def]>>
  ntac 7 strip_tac>>
  rw[]>>
  Cases_on`list_next_var_rename ls (insert h na ssa) (na+4)`>>
  Cases_on`r`>>fs[]>>
  res_tac
  >-
    (`∀x. MEM x q ⇒ na < x` by
      (rw[MEM_MAP]>>DECIDE_TAC)>>
    qpat_assum`A = ls'` (sym_sub_tac)>>
    `¬ MEM na q` by
      (SPOSE_NOT_THEN assume_tac>>
      res_tac>>DECIDE_TAC)>>
    fs[ALL_DISTINCT])
  >-
    (fs[MAP_MAP_o]>>
    qpat_assum`A = ls'` sym_sub_tac>>
    fs[MAP_EQ_f]>>rw[]>>
    DECIDE_TAC)
  >>
    DECIDE_TAC)

val list_next_var_rename_lemma_2 = prove(``
  ∀ls ssa na.
  ALL_DISTINCT ls ⇒
  let (ls',ssa',na') = list_next_var_rename ls ssa na in
  ls' = MAP (λx. THE(lookup x ssa')) ls ∧
  domain ssa' = domain ssa ∪ set ls ∧
  (∀x. ¬MEM x ls ⇒ lookup x ssa' = lookup x ssa) ∧
  (∀x. MEM x ls ⇒ ∃y. lookup x ssa' = SOME y)``,
  Induct>>fs[list_next_var_rename_def,LET_THM,next_var_rename_def]>>
  rw[]>>
  first_x_assum(qspecl_then[`insert h na ssa`,`na+4`] assume_tac)>>
  rfs[]>>
  Cases_on`list_next_var_rename ls (insert h na ssa) (na+4)`>>Cases_on`r`>>
  fs[lookup_insert,EXTENSION]>>rw[]>>
  metis_tac[])

val exists_tac = qexists_tac`cst.permute`>>
    fs[evaluate_def,LET_THM,word_state_eq_rel_def
      ,ssa_cc_trans_def];

val ssa_locals_rel_get_var = prove(``
  ssa_locals_rel na ssa st.locals cst.locals ∧
  get_var n st = SOME x
  ⇒
  get_var (option_lookup ssa n) cst = SOME x``,
  fs[get_var_def,ssa_locals_rel_def,strong_locals_rel_def,option_lookup_def]>>
  rw[]>>
  FULL_CASE_TAC>>fs[domain_lookup]>>
  first_x_assum(qspecl_then[`n`,`x`] assume_tac)>>rfs[])

val ssa_locals_rel_get_vars = prove(``
  ∀ls y na ssa st cst.
  ssa_locals_rel na ssa st.locals cst.locals ∧
  get_vars ls st = SOME y
  ⇒
  get_vars (MAP (option_lookup ssa) ls) cst = SOME y``,
  Induct>>fs[get_vars_def]>>rw[]>>
  Cases_on`get_var h st`>>fs[]>>
  imp_res_tac ssa_locals_rel_get_var>>fs[]>>
  Cases_on`get_vars ls st`>>fs[]>>
  res_tac>>fs[])

val ssa_map_ok_extend = prove(``
  ssa_map_ok na ssa ∧
  ¬is_phy_var na ⇒
  ssa_map_ok (na+4) (insert h na ssa)``,
  fs[ssa_map_ok_def]>>
  rw[]>>fs[lookup_insert]>>
  Cases_on`x=h`>>fs[]>>
  res_tac>-
    DECIDE_TAC
  >-
    (SPOSE_NOT_THEN assume_tac>>res_tac>>
    DECIDE_TAC)
  >>
    Cases_on`z=h`>>fs[]>>DECIDE_TAC)

val merge_moves_frame = prove(``
  ∀ls na ssaL ssaR.
  is_alloc_var na
  ⇒
  let(moveL,moveR,na',ssaL',ssaR') = merge_moves ls ssaL ssaR na in
  is_alloc_var na' ∧
  na ≤ na' ∧
  (ssa_map_ok na ssaL ⇒ ssa_map_ok na' ssaL') ∧
  (ssa_map_ok na ssaR ⇒ ssa_map_ok na' ssaR')``,
  Induct>>fs[merge_moves_def]>-
    (rw[]>>fs[])
  >>
  rpt strip_tac>>
  fs[LET_THM]>>
  last_x_assum(qspecl_then[`na`,`ssaL`,`ssaR`] assume_tac)>>
  rfs[]>>
  Cases_on`merge_moves ls ssaL ssaR na`>>PairCases_on`r`>>rfs[]>>
  EVERY_CASE_TAC>>fs[]>>
  (CONJ_TAC>-
    (fs[is_alloc_var_def]>>
    (qspec_then `4` assume_tac arithmeticTheory.MOD_PLUS>>fs[]>>
    pop_assum (qspecl_then [`r1`,`4`] assume_tac)>>
    rfs[]))
  >>
  CONJ_TAC>-
    DECIDE_TAC)
  >>
  metis_tac[ssa_map_ok_extend,convention_partitions])

val merge_moves_fst = prove(``
  ∀ls na ssaL ssaR.
  let(moveL,moveR,na',ssaL',ssaR') = merge_moves ls ssaL ssaR na in
  na ≤ na' ∧
  EVERY (λx. x < na' ∧ x ≥ na) (MAP FST moveL) ∧
  EVERY (λx. x < na' ∧ x ≥ na) (MAP FST moveR) ``,
  Induct>>fs[merge_moves_def]>>rw[]>>
  fs[EVERY_MAP]>>
  first_x_assum(qspecl_then[`na`,`ssaL`,`ssaR`]assume_tac)>>
  rfs[LET_THM]>>
  EVERY_CASE_TAC>>fs[]>>
  qpat_assum`A = moveL` (sym_sub_tac)>>
  qpat_assum`A = moveR` (sym_sub_tac)>>
  fs[EVERY_MEM]>>rw[]>>
  res_tac>>
  DECIDE_TAC)

(*Characterize result of merge_moves*)
val merge_moves_frame2 = prove(``
  ∀ls na ssaL ssaR.
  let(moveL,moveR,na',ssaL',ssaR') = merge_moves ls ssaL ssaR na in
  domain ssaL' = domain ssaL ∧
  domain ssaR' = domain ssaR ∧
  ∀x. MEM x ls ∧ x ∈ domain (inter ssaL ssaR) ⇒
    lookup x ssaL' = lookup x ssaR'``,
  Induct>>fs[merge_moves_def]>-
    (rw[]>>fs[])
  >>
  rpt strip_tac>>
  fs[LET_THM]>>
  last_x_assum(qspecl_then[`na`,`ssaL`,`ssaR`] assume_tac)>>
  rfs[LET_THM]>>
  Cases_on`merge_moves ls ssaL ssaR na`>>PairCases_on`r`>>rfs[]>>
  EVERY_CASE_TAC>>fs[]
  >-
    metis_tac[]
  >> TRY
    (fs[domain_inter]>>rw[]>>
    qpat_assum`A=domain ssaL` (sym_sub_tac)>>
    qpat_assum`A=domain ssaR` (sym_sub_tac)>>
    fs[domain_lookup]>>
    fs[optionTheory.SOME_11]>>
    res_tac>>
    rfs[])
  >>
    fs[EXTENSION]>>rw[]>>
    metis_tac[domain_lookup,lookup_insert])

(*Another frame proof about unchanged lookups*)
val merge_moves_frame3 = prove(``
  ∀ls na ssaL ssaR.
  let(moveL,moveR,na',ssaL',ssaR') = merge_moves ls ssaL ssaR na in
  ∀x. ¬MEM x ls ∨ x ∉ domain (inter ssaL ssaR) ⇒
    lookup x ssaL' = lookup x ssaL ∧
    lookup x ssaR' = lookup x ssaR``,
  Induct>>fs[merge_moves_def]>-
    (rw[]>>fs[])>>
  rpt strip_tac>>
  fs[LET_THM]>>
  last_x_assum(qspecl_then[`na`,`ssaL`,`ssaR`] assume_tac)>>
  rfs[LET_THM]>>
  Cases_on`merge_moves ls ssaL ssaR na`>>PairCases_on`r`>>rfs[]>>
  EVERY_CASE_TAC>>fs[]>>
  TRY(metis_tac[])>>
  rw[]>>fs[lookup_insert]>>
  IF_CASES_TAC>>fs[]>>
  Q.ISPECL_THEN [`ls`,`na`,`ssaL`,`ssaR`] assume_tac merge_moves_frame2>>
  rfs[LET_THM]>>
  `h ∈ domain r3 ∧ h ∈ domain r2` by fs[domain_lookup]>>
  fs[domain_inter]>>
  metis_tac[])

(*Don't know a neat way to prove this for both sides at once neatly,
Also, the cases are basically copy pasted... *)

val mov_eval_head = prove(``
  evaluate(Move p moves,st) = (NONE,rst) ∧
  y ∈ domain st.locals ∧
  ¬MEM y (MAP FST moves) ∧
  ¬MEM x (MAP FST moves)
  ⇒
  evaluate(Move p ((x,y)::moves),st) = (NONE, rst with locals:=insert x (THE (lookup y st.locals)) rst.locals)``,
  fs[evaluate_def,get_vars_def,get_var_def,domain_lookup]>>
  EVERY_CASE_TAC>>fs[]>>
  strip_tac>>
  fs[set_vars_def,alist_insert_def]>>
  qpat_assum `A=rst` (sym_sub_tac)>>fs[])

val merge_moves_correctL = prove(``
  ∀ls na ssaL ssaR stL cstL pri.
  is_alloc_var na ∧
  ALL_DISTINCT ls ∧
  ssa_map_ok na ssaL
  ⇒
  let(moveL,moveR,na',ssaL',ssaR') = merge_moves ls ssaL ssaR na in
  (ssa_locals_rel na ssaL stL.locals cstL.locals ⇒
  let (resL,rcstL) = evaluate(Move pri moveL,cstL) in
    resL = NONE ∧
    (∀x. ¬MEM x ls ⇒ lookup x ssaL' = lookup x ssaL) ∧
    (∀x y. (x < na ∧ lookup x cstL.locals = SOME y)
    ⇒  lookup x rcstL.locals = SOME y) ∧
    ssa_locals_rel na' ssaL' stL.locals rcstL.locals ∧
    word_state_eq_rel cstL rcstL)``,
  Induct>>fs[merge_moves_def]>-
  (rw[]>>
  fs[evaluate_def,word_state_eq_rel_def,get_vars_def,set_vars_def,alist_insert_def]>>
  rfs[]>>rw[])>>
  rpt strip_tac>>
  first_x_assum(qspecl_then[`na`,`ssaL`,`ssaR`,`stL`,`cstL`,`pri`]mp_tac)>>
  discharge_hyps>-
    (rfs[LET_THM]>>
    metis_tac[])>>
  strip_tac>>
  rfs[LET_THM]>>
  Cases_on`merge_moves ls ssaL ssaR na`>>PairCases_on`r`>>fs[]>>
  EVERY_CASE_TAC>>fs[]>>
  strip_tac>>fs[]>>
  Cases_on`evaluate(Move pri q,cstL)`>>fs[]>>
  imp_res_tac merge_moves_frame>>
  pop_assum(qspecl_then[`ssaR`,`ssaL`,`ls`]assume_tac)>>
  Q.ISPECL_THEN [`ls`,`na`,`ssaL`,`ssaR`] assume_tac merge_moves_fst>>
  rfs[LET_THM]>>
  imp_res_tac mov_eval_head>>
  pop_assum(qspec_then`r1` mp_tac)>>discharge_hyps>-
    (SPOSE_NOT_THEN assume_tac>>fs[EVERY_MEM]>>
    res_tac>>
    DECIDE_TAC)>>
  strip_tac>>
  pop_assum(qspec_then`x'` mp_tac)>>discharge_hyps>-
    (SPOSE_NOT_THEN assume_tac>>fs[EVERY_MEM,ssa_map_ok_def]>>
    res_tac>>
    DECIDE_TAC)>>
  discharge_hyps>-
    (fs[ssa_locals_rel_def]>>
    metis_tac[])>>
  strip_tac>>
  rw[]>>fs[lookup_insert]
  >-
    (`x'' ≠ r1` by DECIDE_TAC>>
    fs[lookup_insert])
  >-
    (fs[ssa_locals_rel_def]>>
    rw[]>>fs[lookup_insert]
    >-
      (Cases_on`x''=h`>>fs[]>>
      metis_tac[])
    >-
      (Cases_on`x''=h`>>fs[]>-
      (res_tac>>fs[]>>
      qpat_assum`lookup h ssaL = SOME x'` (SUBST_ALL_TAC)>>
      fs[])>>
      res_tac>>
      fs[domain_lookup]>>
       `v'' < r1` by
        (fs[ssa_map_ok_def]>>
        metis_tac[])>>
      `v'' ≠ r1` by DECIDE_TAC>>
      fs[])
    >-
      (res_tac>>DECIDE_TAC))
  >>
      fs[word_state_eq_rel_def])

val merge_moves_correctR = prove(``
  ∀ls na ssaL ssaR stR cstR pri.
  is_alloc_var na ∧
  ALL_DISTINCT ls ∧
  ssa_map_ok na ssaR
  ⇒
  let(moveL,moveR,na',ssaL',ssaR') = merge_moves ls ssaL ssaR na in
  (ssa_locals_rel na ssaR stR.locals cstR.locals ⇒
  let (resR,rcstR) = evaluate(Move pri moveR,cstR) in
    resR = NONE ∧
    (∀x. ¬MEM x ls ⇒ lookup x ssaR' = lookup x ssaR) ∧
    (∀x y. (x < na ∧ lookup x cstR.locals = SOME y)
    ⇒  lookup x rcstR.locals = SOME y) ∧
    ssa_locals_rel na' ssaR' stR.locals rcstR.locals ∧
    word_state_eq_rel cstR rcstR)``,
  Induct>>fs[merge_moves_def]>-
  (rw[]>>
  fs[evaluate_def,word_state_eq_rel_def,get_vars_def,set_vars_def,alist_insert_def]>>
  rfs[]>>rw[])>>
  rpt strip_tac>>
  first_x_assum(qspecl_then[`na`,`ssaL`,`ssaR`,`stR`,`cstR`,`pri`]mp_tac)>>
  discharge_hyps>-
    (rfs[LET_THM]>>
    metis_tac[])>>
  strip_tac>>
  rfs[LET_THM]>>
  Cases_on`merge_moves ls ssaL ssaR na`>>PairCases_on`r`>>fs[]>>
  EVERY_CASE_TAC>>fs[]>>
  strip_tac>>fs[]>>
  Cases_on`evaluate(Move pri r0,cstR)`>>fs[]>>
  imp_res_tac merge_moves_frame>>
  pop_assum(qspecl_then[`ssaR`,`ssaL`,`ls`]assume_tac)>>
  Q.ISPECL_THEN [`ls`,`na`,`ssaL`,`ssaR`] assume_tac merge_moves_fst>>
  rfs[LET_THM]>>
  imp_res_tac mov_eval_head>>
  pop_assum(qspec_then`r1` mp_tac)>>discharge_hyps>-
    (SPOSE_NOT_THEN assume_tac>>fs[EVERY_MEM]>>
    res_tac>>
    DECIDE_TAC)>>
  strip_tac>>
  pop_assum(qspec_then`x` mp_tac)>>discharge_hyps>-
    (SPOSE_NOT_THEN assume_tac>>fs[EVERY_MEM,ssa_map_ok_def]>>
    res_tac>>
    DECIDE_TAC)>>
  discharge_hyps>-
    (fs[ssa_locals_rel_def]>>
    metis_tac[])>>
  strip_tac>>
  rw[]>>fs[lookup_insert]
  >-
    (`x'' ≠ r1` by DECIDE_TAC>>
    fs[lookup_insert])
  >-
    (fs[ssa_locals_rel_def]>>
    rw[]>>fs[lookup_insert]
    >-
      (Cases_on`x''=h`>>fs[]>>
      metis_tac[])
    >-
      (Cases_on`x''=h`>>fs[]>-
      (res_tac>>fs[]>>
      qpat_assum`lookup h ssaR = SOME x` (SUBST_ALL_TAC)>>
      fs[])>>
      res_tac>>
      fs[domain_lookup]>>
       `v'' < r1` by
        (fs[ssa_map_ok_def]>>
        metis_tac[])>>
      `v'' ≠ r1` by DECIDE_TAC>>
      fs[])
    >-
      (res_tac>>DECIDE_TAC))
  >>
      fs[word_state_eq_rel_def])

val fake_moves_frame = prove(``
  ∀ls na ssaL ssaR.
  is_alloc_var na
  ⇒
  let(moveL,moveR,na',ssaL',ssaR') = fake_moves ls ssaL ssaR na in
  is_alloc_var na' ∧
  na ≤ na' ∧
  (ssa_map_ok na ssaL ⇒ ssa_map_ok na' ssaL') ∧
  (ssa_map_ok na ssaR ⇒ ssa_map_ok na' ssaR')``,
  Induct>>fs[fake_moves_def]>-
    (rw[]>>fs[])
  >>
  rpt strip_tac>>
  fs[LET_THM]>>
  last_x_assum(qspecl_then[`na`,`ssaL`,`ssaR`] assume_tac)>>
  rfs[]>>
  Cases_on`fake_moves ls ssaL ssaR na`>>PairCases_on`r`>>rfs[]>>
  EVERY_CASE_TAC>>fs[]>>
  (CONJ_TAC>-
    (fs[is_alloc_var_def]>>
    (qspec_then `4` assume_tac arithmeticTheory.MOD_PLUS>>fs[]>>
    pop_assum (qspecl_then [`r1`,`4`] assume_tac)>>
    rfs[]))
  >>
  CONJ_TAC>-
    DECIDE_TAC)
  >>
  metis_tac[ssa_map_ok_extend,convention_partitions])

val fake_moves_frame2 = prove(``
  ∀ls na ssaL ssaR.
  let(moveL,moveR,na',ssaL',ssaR') = fake_moves ls ssaL ssaR na in
  domain ssaL' = domain ssaL ∪ (set ls ∩ (domain ssaR ∪ domain ssaL)) ∧
  domain ssaR' = domain ssaR ∪ (set ls ∩ (domain ssaR ∪ domain ssaL)) ∧
  ∀x. MEM x ls ∧ x ∉ domain(inter ssaL ssaR) ⇒ lookup x ssaL' = lookup x ssaR'``,
  Induct>>fs[fake_moves_def]>-
    (rw[]>>fs[])
  >>
  rpt strip_tac>>
  fs[LET_THM]>>
  last_x_assum(qspecl_then[`na`,`ssaL`,`ssaR`] assume_tac)>>
  rfs[LET_THM]>>
  Cases_on`fake_moves ls ssaL ssaR na`>>PairCases_on`r`>>rfs[]>>
  EVERY_CASE_TAC>>
  fs[EXTENSION,domain_inter]>>rw[]>>
  metis_tac[domain_lookup,lookup_insert])

val fake_moves_frame3 = prove(``
  ∀ls na ssaL ssaR.
  let(moveL,moveR,na',ssaL',ssaR') = fake_moves ls ssaL ssaR na in
  ∀x. ¬ MEM x ls ∨ x ∈ domain(inter ssaL ssaR) ⇒
    lookup x ssaL' = lookup x ssaL ∧
    lookup x ssaR' = lookup x ssaR``,
  Induct>>fs[fake_moves_def]>-
    (rw[]>>fs[])
  >>
  rpt strip_tac>>
  fs[LET_THM]>>
  last_x_assum(qspecl_then[`na`,`ssaL`,`ssaR`] assume_tac)>>
  rfs[LET_THM]>>
  Cases_on`fake_moves ls ssaL ssaR na`>>PairCases_on`r`>>rfs[]>>
  Q.ISPECL_THEN[`ls`,`na`,`ssaL`,`ssaR`] assume_tac fake_moves_frame2>>
  rfs[LET_THM]>>
  EVERY_CASE_TAC>>
  fs[EXTENSION,domain_inter]>>rw[]>>
  fs[lookup_insert]>>
  IF_CASES_TAC>>fs[]>>
  `h ∈ domain r2` by fs[domain_lookup]>>
  res_tac>>
  fs[lookup_NONE_domain])

val fake_moves_correctL = prove(``
  ∀ls na ssaL ssaR stL cstL.
  is_alloc_var na ∧
  ALL_DISTINCT ls ∧
  ssa_map_ok na ssaL
  ⇒
  let(moveL,moveR,na',ssaL',ssaR') = fake_moves ls ssaL ssaR na in
  (ssa_locals_rel na ssaL stL.locals cstL.locals ⇒
  let (resL,rcstL) = evaluate(moveL,cstL) in
    resL = NONE ∧
    (∀x. ¬MEM x ls ⇒ lookup x ssaL' = lookup x ssaL) ∧
    (∀x y. (x < na ∧ lookup x cstL.locals = SOME y)
    ⇒  lookup x rcstL.locals = SOME y) ∧
    ssa_locals_rel na' ssaL' stL.locals rcstL.locals ∧
    word_state_eq_rel cstL rcstL)``,
  Induct>>fs[fake_moves_def]>-
    (rw[]>>
    fs[evaluate_def,word_state_eq_rel_def,get_vars_def,set_vars_def,alist_insert_def]>>
    rfs[]>>rw[])>>
  rpt strip_tac>>
  first_x_assum(qspecl_then[`na`,`ssaL`,`ssaR`,`stL`,`cstL`]mp_tac)>>
  discharge_hyps>-
    (rfs[LET_THM]>>
    metis_tac[])>>
  strip_tac>>
  rfs[LET_THM]>>
  Cases_on`fake_moves ls ssaL ssaR na`>>PairCases_on`r`>>fs[]>>
  EVERY_CASE_TAC>>fs[]>>
  strip_tac>>fs[]>>
  fs[evaluate_def,LET_THM,evaluate_def,fake_move_def,word_exp_def,inst_def,assign_def]>>
  Cases_on`evaluate(q,cstL)`>>fs[]>>
  `na ≤ r1 ∧ ssa_map_ok r1 r2` by
    (imp_res_tac fake_moves_frame>>
    fs[LET_THM]>>
    pop_assum(qspecl_then[`ssaR`,`ssaL`,`ls`]assume_tac)>>rfs[])
  >-
    (fs[ssa_locals_rel_def]>>
    res_tac>>
    fs[domain_lookup,get_vars_def,get_var_def,set_vars_def,alist_insert_def]>>
    rw[]>>fs[lookup_insert]
    >-
      (`x' ≠ r1` by DECIDE_TAC>>
      fs[lookup_insert])
    >-
      (IF_CASES_TAC>>fs[]>>
      Cases_on`x'=h`>>fs[]>>
      metis_tac[])
    >-
      (Cases_on`x'=h`>>fs[]>-
      (res_tac>>fs[]>>
      qpat_assum`lookup h r2 = SOME v'''` SUBST_ALL_TAC>>
      fs[]>>
      rfs[])
      >>
      res_tac>>fs[]>>
      `v''' < r1` by
        (fs[ssa_map_ok_def]>>
        metis_tac[])>>
      `v''' ≠ r1` by DECIDE_TAC>>
      fs[])
    >-
      (res_tac>>
      DECIDE_TAC)
    >>
      fs[word_state_eq_rel_def])
  >-
    (fs[ssa_locals_rel_def]>>
    res_tac>>
    fs[domain_lookup,set_var_def]>>
    rw[]>>fs[lookup_insert]
    >-
      (`x' ≠ r1` by DECIDE_TAC>>
      fs[lookup_insert])
    >-
      (IF_CASES_TAC>>fs[]>>
      Cases_on`x'=h`>>fs[]>>
      metis_tac[])
    >-
      (Cases_on`x'=h`>>fs[]>-
        (res_tac>>fs[])
      >>
      res_tac>>fs[]>>
      `v' < r1` by
        (fs[ssa_map_ok_def]>>
        metis_tac[])>>
      `v' ≠ r1` by DECIDE_TAC>>
      fs[])
    >-
      (res_tac>>
      DECIDE_TAC)
    >>
      fs[word_state_eq_rel_def]))

val fake_moves_correctR = prove(``
  ∀ls na ssaL ssaR stR cstR.
  is_alloc_var na ∧
  ALL_DISTINCT ls ∧
  ssa_map_ok na ssaR
  ⇒
  let(moveL,moveR,na',ssaL',ssaR') = fake_moves ls ssaL ssaR na in
  (ssa_locals_rel na ssaR stR.locals cstR.locals ⇒
  let (resR,rcstR) = evaluate(moveR,cstR) in
    resR = NONE ∧
    (∀x. ¬MEM x ls ⇒ lookup x ssaR' = lookup x ssaR) ∧
    (∀x y. (x < na ∧ lookup x cstR.locals = SOME y)
    ⇒  lookup x rcstR.locals = SOME y) ∧
    ssa_locals_rel na' ssaR' stR.locals rcstR.locals ∧
    word_state_eq_rel cstR rcstR)``,
  Induct>>fs[fake_moves_def]>-
  (rw[]>>
  fs[evaluate_def,word_state_eq_rel_def,get_vars_def,set_vars_def,alist_insert_def]>>
  rfs[]>>rw[])>>
  rpt strip_tac>>
  first_x_assum(qspecl_then[`na`,`ssaL`,`ssaR`,`stR`,`cstR`]mp_tac)>>
  discharge_hyps>-
    (rfs[LET_THM]>>
    metis_tac[])>>
  strip_tac>>
  rfs[LET_THM]>>
  Cases_on`fake_moves ls ssaL ssaR na`>>PairCases_on`r`>>fs[]>>
  EVERY_CASE_TAC>>fs[]>>
  strip_tac>>fs[]>>
  fs[evaluate_def,LET_THM,evaluate_def,fake_move_def,word_exp_def,inst_def,assign_def]>>
  Cases_on`evaluate(r0,cstR)`>>fs[]>>
  `na ≤ r1 ∧ ssa_map_ok r1 r3` by
    (imp_res_tac fake_moves_frame>>
    fs[LET_THM]>>
    pop_assum(qspecl_then[`ssaR`,`ssaL`,`ls`]assume_tac)>>rfs[])
  >-
    (fs[ssa_locals_rel_def]>>
    res_tac>>
    fs[domain_lookup,set_var_def]>>
    rw[]>>fs[lookup_insert]
    >-
      (`x' ≠ r1` by DECIDE_TAC>>
      fs[lookup_insert])
    >-
      (IF_CASES_TAC>>fs[]>>
      Cases_on`x'=h`>>fs[]>>
      metis_tac[])
    >-
      (Cases_on`x'=h`>>fs[]>-
        (res_tac>>fs[])
      >>
      res_tac>>fs[]>>
      `v' < r1` by
        (fs[ssa_map_ok_def]>>
        metis_tac[])>>
      `v' ≠ r1` by DECIDE_TAC>>
      fs[])
    >-
      (res_tac>>
      DECIDE_TAC)
    >>
      fs[word_state_eq_rel_def])
  >-
    (fs[ssa_locals_rel_def]>>
    res_tac>>
    fs[domain_lookup,get_vars_def,get_var_def,set_vars_def,alist_insert_def]>>
    rw[]>>fs[lookup_insert]
    >-
      (`x' ≠ r1` by DECIDE_TAC>>
      fs[lookup_insert])
    >-
      (IF_CASES_TAC>>fs[]>>
      Cases_on`x'=h`>>fs[]>>
      metis_tac[])
    >-
      (Cases_on`x'=h`>>fs[]>-
      (res_tac>>fs[]>>
      qpat_assum`lookup h r3 = SOME v'''` SUBST_ALL_TAC>>
      fs[]>>
      rfs[])
      >>
      res_tac>>fs[]>>
      `v''' < r1` by
        (fs[ssa_map_ok_def]>>
        metis_tac[])>>
      `v''' ≠ r1` by DECIDE_TAC>>
      fs[])
    >-
      (res_tac>>
      DECIDE_TAC)
    >>
      fs[word_state_eq_rel_def]))

(*Swapping lemma that allows us to swap in ssaL for ssaR
  after we are done fixing them*)
val ssa_eq_rel_swap = prove(``
  ssa_locals_rel na ssaR st.locals cst.locals ∧
  domain ssaL = domain ssaR ∧
  (∀x. lookup x ssaL = lookup x ssaR) ⇒
  ssa_locals_rel na ssaL st.locals cst.locals``,
  rw[ssa_locals_rel_def])

val ssa_locals_rel_more = prove(``
  ssa_locals_rel na ssa stlocs cstlocs ∧ na ≤ na' ⇒
  ssa_locals_rel na' ssa stlocs cstlocs``,
  rw[ssa_locals_rel_def]>>fs[]
  >- metis_tac[]>>
  res_tac>>fs[]>>
  DECIDE_TAC)

val ssa_map_ok_more = prove(``
  ssa_map_ok na ssa ∧ na ≤ na' ⇒
  ssa_map_ok na' ssa``,
  fs[ssa_map_ok_def]>>rw[]
  >-
    metis_tac[]>>
  res_tac>>fs[]>>DECIDE_TAC)

val get_vars_eq = prove(
  ``(set ls) SUBSET domain st.locals ==> ?z. get_vars ls st = SOME z /\
                                             z = MAP (\x. THE (lookup x st.locals)) ls``,
  Induct_on`ls`>>fs[get_vars_def,get_var_def]>>rw[]>>
  fs[domain_lookup])

val get_var_ignore = prove(``
  ∀ls a.
  get_var x cst = SOME y ∧
  ¬MEM x ls ∧
  LENGTH ls = LENGTH a ⇒
  get_var x (set_vars ls a cst) = SOME y``,
  Induct>>fs[get_var_def,set_vars_def,alist_insert_def]>>
  rw[]>>
  Cases_on`a`>>fs[alist_insert_def,lookup_insert])

val fix_inconsistencies_correctL = prove(``
  ∀na ssaL ssaR.
  is_alloc_var na ∧
  ssa_map_ok na ssaL
  ⇒
  let(moveL,moveR,na',ssaU) = fix_inconsistencies ssaL ssaR na in
  (∀stL cstL.
  ssa_locals_rel na ssaL stL.locals cstL.locals ⇒
  let (resL,rcstL) = evaluate(moveL,cstL) in
    resL = NONE ∧
    ssa_locals_rel na' ssaU stL.locals rcstL.locals ∧
    word_state_eq_rel cstL rcstL)``,
  fs[fix_inconsistencies_def]>>LET_ELIM_TAC>>
  Q.SPECL_THEN [`var_union`,`na`,`ssaL`,`ssaR`,`stL`,`cstL`,`1`] mp_tac
      merge_moves_correctL>>
  fs[]>>
  (discharge_hyps_keep>-
    (fs[Abbr`var_union`,ALL_DISTINCT_MAP_FST_toAList]))>>
  LET_ELIM_TAC>>
  Q.SPECL_THEN [`var_union`,`na'`,`ssaL'`,`ssaR'`,`stL`,`rcstL'`]mp_tac
      fake_moves_correctL>>
  (discharge_hyps>-
      (Q.ISPECL_THEN [`var_union`,`na`,`ssaL`,`ssaR`] assume_tac merge_moves_frame>>rfs[LET_THM]))>>
  LET_ELIM_TAC>>
  rfs[]>>
  qpat_assum`A=moveL` sym_sub_tac>>
  qpat_assum`A=(resL,B)` mp_tac>>
  simp[Once evaluate_def]>>
  fs[]>>
  rpt VAR_EQ_TAC>>fs[]>>
  rw[]>>fs[word_state_eq_rel_def]) |> INST_TYPE [gamma |-> beta]

val fix_inconsistencies_correctR = prove(``
  ∀na ssaL ssaR.
  is_alloc_var na ∧
  ssa_map_ok na ssaR
  ⇒
  let(moveL,moveR,na',ssaU) = fix_inconsistencies ssaL ssaR na in
  (∀stR cstR.
  ssa_locals_rel na ssaR stR.locals cstR.locals ⇒
  let (resR,rcstR) = evaluate(moveR,cstR) in
    resR = NONE ∧
    ssa_locals_rel na' ssaU stR.locals rcstR.locals ∧
    word_state_eq_rel cstR rcstR)``,
  fs[fix_inconsistencies_def]>>LET_ELIM_TAC>>
  Q.SPECL_THEN [`var_union`,`na`,`ssaL`,`ssaR`,`stR`,`cstR`,`1`] mp_tac
      merge_moves_correctR>>
  fs[]>>
  (discharge_hyps_keep>-
    (fs[Abbr`var_union`,ALL_DISTINCT_MAP_FST_toAList]))>>
  LET_ELIM_TAC>>
  Q.SPECL_THEN [`var_union`,`na'`,`ssaL'`,`ssaR'`,`stR`,`rcstR'`]mp_tac
        fake_moves_correctR>>
  (discharge_hyps>-
      (Q.ISPECL_THEN [`var_union`,`na`,`ssaL`,`ssaR`] assume_tac merge_moves_frame>>rfs[LET_THM]))>>
  LET_ELIM_TAC>>
  rfs[]>>
  qpat_assum`A=moveR` sym_sub_tac>>
  qpat_assum`A=(resR,B)` mp_tac>>
  simp[Once evaluate_def]>>
  fs[]>>
  rpt VAR_EQ_TAC>>fs[]>>
  rw[]>>fs[word_state_eq_rel_def]>>
  Q.ISPECL_THEN[`var_union`,`na`,`ssaL`,`ssaR`] assume_tac
    merge_moves_frame2>>
  Q.ISPECL_THEN[`var_union`,`na'`,`ssaL'`,`ssaR'`] assume_tac
    fake_moves_frame2>>
  Q.ISPECL_THEN[`var_union`,`na`,`ssaL`,`ssaR`] assume_tac
    merge_moves_frame3>>
  Q.ISPECL_THEN[`var_union`,`na'`,`ssaL'`,`ssaR'`] assume_tac
    fake_moves_frame3>>
  rfs[LET_THM]>>
  match_mp_tac (GEN_ALL ssa_eq_rel_swap)>>
  HINT_EXISTS_TAC>>rfs[]>>
  fs[Abbr`var_union`,EXTENSION]>>CONJ_ASM1_TAC>-
    (fs[toAList_domain,domain_union]>>
    metis_tac[])>>
  fs[toAList_domain]>>rw[]>>
  reverse(Cases_on`x ∈ domain (union ssaL ssaR)`)
  >-
    (fs[domain_union]>>
    metis_tac[lookup_NONE_domain])
  >>
    fs[domain_inter]>>
    metis_tac[]) |> INST_TYPE [gamma|->beta]

fun use_ALOOKUP_ALL_DISTINCT_MEM (g as (asl,w)) =
  let
    val tm = find_term(can(match_term(lhs(snd(dest_imp(concl
      ALOOKUP_ALL_DISTINCT_MEM)))))) w
    val (_,[al,k]) = strip_comb tm
  in
    mp_tac(ISPECL [al,k] (Q.GENL[`v`,`k`,`al`] ALOOKUP_ALL_DISTINCT_MEM))
  end g

val get_vars_exists = prove(``
  ∀ls.
  set ls ⊆ domain st.locals ⇒
  ∃z. get_vars ls st = SOME z``,
  Induct>>fs[get_var_def,get_vars_def]>>rw[]>>
  fs[domain_lookup])

val list_next_var_rename_move_preserve = prove(``
  ∀st ssa na ls cst.
  ssa_locals_rel na ssa st.locals cst.locals ∧
  set ls ⊆ domain st.locals ∧
  ALL_DISTINCT ls ∧
  ssa_map_ok na ssa ∧
  word_state_eq_rel st cst
  ⇒
  let (mov,ssa',na') = list_next_var_rename_move ssa na ls in
  let (res,rcst) = evaluate (mov,cst) in
    res = NONE ∧
    ssa_locals_rel na' ssa' st.locals rcst.locals ∧
    word_state_eq_rel st rcst ∧
    (¬is_phy_var na ⇒ ∀w. is_phy_var w ⇒ lookup w rcst.locals = lookup w cst.locals)``,
  fs[list_next_var_rename_move_def,ssa_locals_rel_def]>>
  rw[]>>
  imp_res_tac list_next_var_rename_lemma_1>>
  `ALL_DISTINCT cur_ls` by
    (fs[Abbr`cur_ls`]>>
    match_mp_tac ALL_DISTINCT_MAP_INJ>>
    rw[option_lookup_def]>>
    TRY(`x ∈ domain st.locals ∧ y ∈ domain st.locals` by
      (fs[SUBSET_DEF]>>NO_TAC))>>
    TRY(`x' ∈ domain st.locals ∧ y' ∈ domain st.locals` by
      (fs[SUBSET_DEF]>>NO_TAC))>>
    fs[domain_lookup]>>res_tac>>
    fs[ssa_map_ok_def]>>
    metis_tac[])>>
  imp_res_tac list_next_var_rename_lemma_2>>
  first_x_assum(qspecl_then[`ssa`,`na`] assume_tac)>>
  fs[LET_THM,evaluate_def]>>rfs[]>>
  rfs[MAP_ZIP,LENGTH_COUNT_LIST,Abbr`cur_ls`]>>fs[]>>
  imp_res_tac get_vars_eq>>
  qpat_assum`A=(res,rcst)` mp_tac>>
  qabbrev_tac`v=get_vars ls st`>>
  qpat_abbrev_tac`cls = MAP (option_lookup ssa) ls`>>
  `get_vars cls cst = v` by
    (fs[Abbr`cls`]>>
    match_mp_tac ssa_locals_rel_get_vars>>
    fs[ssa_locals_rel_def]>>
    qexists_tac`na`>>
    qexists_tac`st`>>fs[]>>
    metis_tac[])>>
  fs[Abbr`v`]>>rw[]
  >-
    (fs[set_vars_def,domain_alist_insert]>>
    Cases_on`MEM x ls`>>res_tac>>fs[]
    >-
      (DISJ2_TAC>>fs[MEM_MAP]>>
      HINT_EXISTS_TAC>>fs[])
    >>
      (res_tac>>
      fs[]))
  >-
    (fs[set_vars_def,lookup_alist_insert]>>
    res_tac>>
    Cases_on`MEM x ls`>>fs[]
    >-
      (res_tac>>
      use_ALOOKUP_ALL_DISTINCT_MEM >>
      simp[ZIP_MAP,MAP_MAP_o,combinTheory.o_DEF,MEM_MAP,PULL_EXISTS] >>
      strip_tac>>
      pop_assum(qspec_then`x` assume_tac)>>
      rfs[])
    >>
      (fs[domain_lookup]>>
      qpat_abbrev_tac `opt:'a word_loc option = ALOOKUP (ZIP A) v`>>
      qsuff_tac `opt = NONE` >>fs[Abbr`opt`]>>
      match_mp_tac (SPEC_ALL ALOOKUP_NONE|>REWRITE_RULE[EQ_IMP_THM]|>CONJ_PAIR|>snd)>>
      SPOSE_NOT_THEN assume_tac>>
      fs[MAP_ZIP]>>
      fs[domain_lookup]>>
      `v < na` by
        metis_tac[ssa_map_ok_def]>>
      rfs[]>>
      rpt (qpat_assum`A = B` sym_sub_tac)>>
      fs[MEM_MAP]>>DECIDE_TAC))
  >-
    (res_tac>>DECIDE_TAC)
  >-
    fs[word_state_eq_rel_def,set_vars_def]
  >>
    fs[lookup_alist_insert,set_vars_def]>>
    FULL_CASE_TAC>>
    imp_res_tac ALOOKUP_MEM>>
    fs[MEM_ZIP]>>
    qpat_assum`MAP A B = MAP C D` sym_sub_tac>>
    rfs[EL_MAP,LENGTH_MAP,LENGTH_COUNT_LIST,EL_COUNT_LIST]>>
    `is_stack_var na ∨ is_alloc_var na` by
      metis_tac[convention_partitions]>>
    `is_stack_var w ∨ is_alloc_var w` by
      (qspec_then `4` mp_tac arithmeticTheory.MOD_PLUS >>
      discharge_hyps>>
      fs[is_phy_var_def,is_alloc_var_def,is_stack_var_def]>>
      disch_then(qspecl_then[`4*n`,`na`](SUBST1_TAC o SYM)) >>
      `(4*n) MOD 4 =0 ` by
        (`0<4:num` by DECIDE_TAC>>
        `∀k.(4:num)*k=k*4` by DECIDE_TAC>>
        metis_tac[arithmeticTheory.MOD_EQ_0])>>
      fs[])>>
    metis_tac[convention_partitions])

val get_vars_list_insert_eq_gen= prove(
``!ls x locs a b. (LENGTH ls = LENGTH x /\ ALL_DISTINCT ls /\
                  LENGTH a = LENGTH b /\ !e. MEM e ls ==> ~MEM e a)
  ==> get_vars ls (st with locals := alist_insert (a++ls) (b++x) locs) = SOME x``,
  ho_match_mp_tac alist_insert_ind>>
  rw[]>-
    (Cases_on`x`>>fs[get_vars_def])>>
  fs[get_vars_def,get_var_def,lookup_alist_insert]>>
  `LENGTH (ls::ls') = LENGTH (x::x')` by fs[]>>
  IMP_RES_TAC rich_listTheory.ZIP_APPEND>>
  ntac 9 (pop_assum (SUBST1_TAC o SYM))>>
  fs[ALOOKUP_APPEND]>>
  first_assum(qspec_then `ls` assume_tac)>>fs[]>>
  `ALOOKUP (ZIP (a,b)) ls = NONE` by metis_tac[ALOOKUP_NONE,MEM_MAP,MAP_ZIP]>>
  fs[]>>
  first_x_assum(qspecl_then [`a++[ls]`,`b++[x]`] assume_tac)>>
  `LENGTH (a++[ls]) = LENGTH (b++[x])` by fs[]>> rfs[]>>
  `a++[ls]++ls' = a++ls::ls' /\ b++[x]++x' = b++x::x'` by fs[]>>
  ntac 2 (pop_assum SUBST_ALL_TAC)>> fs[])

val get_vars_set_vars_eq = prove(``
  ∀ls x.
  ALL_DISTINCT ls ∧ LENGTH x = LENGTH ls ⇒
  get_vars ls (set_vars ls x cst) = SOME x``,
  fs[get_vars_def,set_vars_def]>>rw[]>>
  Q.ISPECL_THEN [`cst`,`ls`,`x`,`cst.locals`,`[]:num list`
    ,`[]:'a word_loc list`] mp_tac (GEN_ALL get_vars_list_insert_eq_gen)>>
  discharge_hyps>>fs[])

val ssa_locals_rel_ignore_set_var = prove(``
  ssa_map_ok na ssa ∧
  ssa_locals_rel na ssa st.locals cst.locals ∧
  is_phy_var v
  ⇒
  ssa_locals_rel na ssa st.locals (set_var v a cst).locals``,
  rw[ssa_locals_rel_def,ssa_map_ok_def,set_var_def]>>
  fs[lookup_insert]>-
    metis_tac[]
  >>
  res_tac>>
  fs[domain_lookup]>>
  metis_tac[])

val ssa_locals_rel_ignore_list_insert = prove(``
  ssa_map_ok na ssa ∧
  ssa_locals_rel na ssa st.locals cst.locals ∧
  EVERY is_phy_var ls ∧
  LENGTH ls = LENGTH x
  ⇒
  ssa_locals_rel na ssa st.locals (alist_insert ls x cst.locals)``,
  rw[ssa_locals_rel_def,ssa_map_ok_def]>>
  fs[domain_alist_insert,lookup_alist_insert]>-
    metis_tac[]
  >>
  res_tac>>
  fs[domain_lookup]>>
  res_tac>>
  `ALOOKUP (ZIP(ls,x)) v = NONE` by
    (rw[ALOOKUP_FAILS,MEM_ZIP]>>
    metis_tac[EVERY_EL])>>
  fs[])

val ssa_locals_rel_set_var = prove(``
  ssa_locals_rel na ssa st.locals cst.locals ∧
  ssa_map_ok na ssa ∧
  n < na ⇒
  ssa_locals_rel (na+4) (insert n na ssa) (insert n w st.locals) (insert na w cst.locals)``,
  rw[ssa_locals_rel_def]>>
  fs[lookup_insert]>>Cases_on`x=n`>>fs[]
  >-
    metis_tac[]
  >-
    (res_tac>>
    fs[domain_lookup,ssa_map_ok_def]>>
    first_x_assum(qspecl_then[`x`,`v`]assume_tac)>>
    (*Next part is a key reasoning step --
      We only have alloc_vars < na in the range of ssa
      Otherwise, the new one may overwrite an old mapping
    *)
    rfs[]>>
    `v ≠ na` by DECIDE_TAC >>
    fs[])
  >-
    DECIDE_TAC
  >>
    (*Finally, this illustrates need for <na assumption on st.locals*)
    fs[ssa_map_ok_def]>>res_tac>>fs[]>>DECIDE_TAC)

val is_alloc_var_add = prove(``
  is_alloc_var na ⇒ is_alloc_var (na+4)``,
  fs[is_alloc_var_def]>>
  (qspec_then `4` assume_tac arithmeticTheory.MOD_PLUS>>fs[]>>
    pop_assum (qspecl_then [`na`,`4`] assume_tac)>>
    rfs[]))

val is_stack_var_add= prove(``
  is_stack_var na ⇒ is_stack_var (na+4)``,
  fs[is_stack_var_def]>>
  (qspec_then `4` assume_tac arithmeticTheory.MOD_PLUS>>fs[]>>
    pop_assum (qspecl_then [`na`,`4`] assume_tac)>>
    rfs[]))

val is_alloc_var_flip = prove(``
  is_alloc_var na ⇒ is_stack_var (na+2)``,
  fs[is_alloc_var_def,is_stack_var_def]>>
  (qspec_then `4` assume_tac arithmeticTheory.MOD_PLUS>>fs[]>>
    pop_assum (qspecl_then [`na`,`2`] assume_tac)>>
    rw[]>>fs[]))

val is_stack_var_flip = prove(``
  is_stack_var na ⇒ is_alloc_var (na+2)``,
  fs[is_alloc_var_def,is_stack_var_def]>>
  (qspec_then `4` assume_tac arithmeticTheory.MOD_PLUS>>fs[]>>
    pop_assum (qspecl_then [`na`,`2`] assume_tac)>>
    rw[]>>fs[]))

val list_next_var_rename_props = prove(``
  ∀ls ssa na ls' ssa' na'.
  (is_alloc_var na ∨ is_stack_var na) ∧
  ssa_map_ok na ssa ∧
  list_next_var_rename ls ssa na = (ls',ssa',na')
  ⇒
  na ≤ na' ∧
  (is_alloc_var na ⇒ is_alloc_var na') ∧
  (is_stack_var na ⇒ is_stack_var na') ∧
  ssa_map_ok na' ssa'``,
  Induct>>fs[list_next_var_rename_def,next_var_rename_def]>>
  LET_ELIM_TAC>>
  first_x_assum(qspecl_then[`ssa''`,`na''`,`ys`,`ssa'''`,`na'''`]
    mp_tac)>>
  (discharge_hyps>-
    (fs[ssa_map_ok_def]>>rw[]
    >-
      metis_tac[is_alloc_var_add,is_stack_var_add]
    >-
      (fs[lookup_insert]>>Cases_on`x=h`>>fs[]>>
      metis_tac[convention_partitions])
    >-
      (fs[lookup_insert]>>Cases_on`x=h`>>fs[]>>
      res_tac>>DECIDE_TAC)
    >>
      fs[lookup_insert]>>Cases_on`x=h`>>Cases_on`z=h`>>fs[]
      >-
        (SPOSE_NOT_THEN assume_tac>>res_tac>>fs[])
      >>
        res_tac>>DECIDE_TAC))>>
  rw[]>> TRY(DECIDE_TAC)>> fs[]>>
  metis_tac[is_alloc_var_add,is_stack_var_add])

val list_next_var_rename_move_props = prove(``
  ∀ls ssa na ls' ssa' na'.
  (is_alloc_var na ∨ is_stack_var na) ∧
  ssa_map_ok na ssa ∧
  list_next_var_rename_move ssa na ls = (ls',ssa',na')
  ⇒
  na ≤ na' ∧
  (is_alloc_var na ⇒ is_alloc_var na') ∧
  (is_stack_var na ⇒ is_stack_var na') ∧
  ssa_map_ok na' ssa'``,
  fs[list_next_var_rename_move_def]>>LET_ELIM_TAC>>
  fs[]>>
  imp_res_tac list_next_var_rename_props)

val ssa_cc_trans_inst_props = prove(``
  ∀i ssa na i' ssa' na'.
  ssa_cc_trans_inst i ssa na = (i',ssa',na') ∧
  ssa_map_ok na ssa ∧
  is_alloc_var na
  ⇒
  na ≤ na' ∧
  is_alloc_var na' ∧
  ssa_map_ok na' ssa'``,
  Induct>>rw[]>>
  TRY(Cases_on`a`)>>
  TRY(Cases_on`r`)>>
  TRY(Cases_on`m`)>>
  fs[ssa_cc_trans_inst_def,next_var_rename_def]>>rw[]>>
  fs[LET_THM]>>
  TRY(DECIDE_TAC)>>
  metis_tac[ssa_map_ok_extend,convention_partitions,is_alloc_var_add])

val exp_tac = (LET_ELIM_TAC>>fs[next_var_rename_def]>>
    TRY(DECIDE_TAC)>>
    metis_tac[ssa_map_ok_extend,convention_partitions,is_alloc_var_add])

val fix_inconsistencies_props = prove(``
  ∀ssaL ssaR na a b na' ssaU.
  fix_inconsistencies ssaL ssaR na = (a,b,na',ssaU) ∧
  is_alloc_var na ∧
  ssa_map_ok na ssaL ∧
  ssa_map_ok na ssaR
  ⇒
  na ≤ na' ∧
  is_alloc_var na' ∧
  ssa_map_ok na' ssaU``,
  fs[fix_inconsistencies_def]>>LET_ELIM_TAC>>
  imp_res_tac merge_moves_frame>>
  pop_assum(qspecl_then[`ssaR`,`ssaL`,`var_union`] assume_tac)>>
  Q.ISPECL_THEN [`var_union`,`na''`,`ssa_L'`,`ssa_R'`] assume_tac fake_moves_frame>>
  rfs[LET_THM]>>
  DECIDE_TAC)

val th =
  (MATCH_MP
    (PROVE[]``((a ⇒ b) ∧ (c ⇒ d)) ⇒ ((a ∨ c) ⇒ b ∨ d)``)
    (CONJ is_stack_var_flip is_alloc_var_flip))

val flip_rw = prove(
  ``is_stack_var(na+2) = is_alloc_var na ∧
    is_alloc_var(na+2) = is_stack_var na``,
  conj_tac >> (reverse EQ_TAC >-
    metis_tac[is_alloc_var_flip,is_stack_var_flip]) >>
  fs[is_alloc_var_def,is_stack_var_def]>>
  qspec_then `4` mp_tac arithmeticTheory.MOD_PLUS >>
  (discharge_hyps >- fs[]>>
  disch_then(qspecl_then[`na`,`2`](SUBST1_TAC o SYM)) >>
  `na MOD 4 < 4` by fs []>>
  imp_res_tac (DECIDE ``n:num<4⇒(n=0)∨(n=1)∨(n=2)∨(n=3)``)>>
  fs[]))

val list_next_var_rename_props_2 =
  list_next_var_rename_props
  |> CONV_RULE(RESORT_FORALL_CONV(sort_vars["na","na'"]))
  |> Q.SPECL[`na+2`] |> SPEC_ALL
  |> REWRITE_RULE[GSYM AND_IMP_INTRO]
  |> C MATCH_MP (UNDISCH th)
  |> DISCH_ALL
  |> REWRITE_RULE[flip_rw]

val ssa_map_ok_lem = prove(``
  ssa_map_ok na ssa ⇒ ssa_map_ok (na+2) ssa``,
  metis_tac[ssa_map_ok_more, DECIDE``na:num ≤ na+2``])

val list_next_var_rename_move_props_2 = prove(``
  ∀ls ssa na ls' ssa' na'.
  (is_alloc_var na ∨ is_stack_var na) ∧ ssa_map_ok na ssa ∧
  list_next_var_rename_move ssa (na+2) ls = (ls',ssa',na') ⇒
  (na+2) ≤ na' ∧
  (is_alloc_var na ⇒ is_stack_var na') ∧
  (is_stack_var na ⇒ is_alloc_var na') ∧
  ssa_map_ok na' ssa'``,
  ntac 7 strip_tac>>imp_res_tac list_next_var_rename_move_props>>
  fs[]>>
  metis_tac[is_stack_var_flip,is_alloc_var_flip,ssa_map_ok_lem])

(*Prove the properties that hold of ssa_cc_trans independent of semantics*)
val ssa_cc_trans_props = prove(``
  ∀prog ssa na prog' ssa' na'.
  ssa_cc_trans prog ssa na = (prog',ssa',na') ∧
  ssa_map_ok na ssa ∧
  is_alloc_var na
  ⇒
  na ≤ na' ∧
  is_alloc_var na' ∧
  ssa_map_ok na' ssa'``,
  ho_match_mp_tac ssa_cc_trans_ind>>
  fs[ssa_cc_trans_def]>>
  strip_tac >-
    (LET_ELIM_TAC>>
    fs[]>>
    metis_tac[list_next_var_rename_props])>>
  strip_tac >-
    (LET_ELIM_TAC>>
    fs[]>>
    metis_tac[ssa_cc_trans_inst_props])>>
  strip_tac >-
    exp_tac>>
  strip_tac >-
    exp_tac>>
  strip_tac >-
    exp_tac>>
  strip_tac >-
    (LET_ELIM_TAC>>fs[]>>
    DECIDE_TAC)>>
  strip_tac >-
    (LET_ELIM_TAC>>fs[]>>
    imp_res_tac ssa_map_ok_more>>
    first_x_assum(qspec_then`na3` assume_tac)>>rfs[]>>
    fs[]>>
    imp_res_tac fix_inconsistencies_props>>DECIDE_TAC)>>
  strip_tac >-
    (fs[list_next_var_rename_move_def]>>LET_ELIM_TAC>>fs[]>>
    `∀naa. ssa_map_ok naa ssa''' ⇒ ssa_map_ok naa ssa_cut` by
      (rw[Abbr`ssa_cut`,ssa_map_ok_def,lookup_inter]>>
      EVERY_CASE_TAC>>fs[]>>
      metis_tac[])>>
    `na ≤ na+2 ∧ na'' ≤ na''+2` by DECIDE_TAC>>
    imp_res_tac ssa_map_ok_more>>
    imp_res_tac list_next_var_rename_props_2>>
    imp_res_tac ssa_map_ok_more>>
    res_tac>>
    imp_res_tac list_next_var_rename_props_2>>
    DECIDE_TAC)>>
  strip_tac >-
    exp_tac>>
  strip_tac >-
    exp_tac>>
  strip_tac >-
    exp_tac>>
  strip_tac >-
    (fs[list_next_var_rename_move_def]>>LET_ELIM_TAC>>fs[]>>
    `∀naa. ssa_map_ok naa ssa''' ⇒ ssa_map_ok naa ssa_cut` by
      (rw[Abbr`ssa_cut`,ssa_map_ok_def,lookup_inter]>>
      EVERY_CASE_TAC>>fs[]>>
      metis_tac[])>>
    `na ≤ na+2 ∧ na'' ≤ na''+2` by DECIDE_TAC>>
    imp_res_tac ssa_map_ok_more>>
    imp_res_tac list_next_var_rename_props_2>>
    imp_res_tac ssa_map_ok_more>>
    res_tac>>
    imp_res_tac list_next_var_rename_props_2>>
    DECIDE_TAC)>>
  strip_tac >-
    (LET_ELIM_TAC>>fs[]>>
    rfs[])>>
  (*Calls*)
  Cases_on`h`>-
    (fs[list_next_var_rename_move_def]>>
    rw[]>>
    ntac 3 (pop_assum mp_tac)>>LET_ELIM_TAC>>
    `∀naa. ssa_map_ok naa ssa''' ⇒ ssa_map_ok naa ssa_cut` by
      (rw[Abbr`ssa_cut`,ssa_map_ok_def,lookup_inter]>>
      EVERY_CASE_TAC>>fs[]>>
      metis_tac[])>>
    fs[PULL_FORALL,LET_THM]>>
     `na ≤ na+2 ∧ na'' ≤ na''+2` by DECIDE_TAC>>
    imp_res_tac ssa_map_ok_more>>
    imp_res_tac list_next_var_rename_props_2>>
    imp_res_tac ssa_map_ok_more>>
    res_tac>>
    imp_res_tac list_next_var_rename_props_2>>
    (last_assum mp_tac>>discharge_hyps>-
      (fs[next_var_rename_def]>>
      CONJ_ASM2_TAC>-
        metis_tac[ssa_map_ok_extend,convention_partitions]
      >>
      metis_tac[is_alloc_var_add]))>>
    rw[]>>
    fs[next_var_rename_def]>>
    DECIDE_TAC)
  >>
    PairCases_on`x`>>fs[list_next_var_rename_move_def]>>
    rw[]>>
    ntac 3 (pop_assum mp_tac)>>LET_ELIM_TAC>>
    `∀naa. ssa_map_ok naa ssa'' ⇒ ssa_map_ok naa ssa_cut` by
      (rw[Abbr`ssa_cut`,ssa_map_ok_def,lookup_inter]>>
      EVERY_CASE_TAC>>fs[]>>
      metis_tac[])>>
    fs[PULL_FORALL,LET_THM]>>
    `na ≤ na+2 ∧ na'' ≤ na''+2` by DECIDE_TAC>>
    imp_res_tac ssa_map_ok_more>>
    imp_res_tac list_next_var_rename_props_2>>
    imp_res_tac ssa_map_ok_more>>
    rpt VAR_EQ_TAC>>
    res_tac>>
    imp_res_tac list_next_var_rename_props_2>>
    (ntac 2 (last_x_assum mp_tac)>>
    discharge_hyps_keep>-
      (fs[next_var_rename_def]>>
      CONJ_ASM2_TAC>-
        metis_tac[ssa_map_ok_extend,convention_partitions]
      >>
      metis_tac[is_alloc_var_add])>>
    strip_tac>>
    discharge_hyps_keep>-
      (fs[next_var_rename_def]>>
      CONJ_ASM2_TAC>-
        (qpat_assum`A=na_3_p` sym_sub_tac>>
        qpat_assum `A=ssa_3_p` sym_sub_tac>>
        match_mp_tac ssa_map_ok_extend>>
        `n'' ≤ na_2_p` by DECIDE_TAC>>
        metis_tac[ssa_map_ok_more,ssa_map_ok_extend,convention_partitions])
      >>
      metis_tac[is_alloc_var_add]))>>
    rw[]>>
    fs[next_var_rename_def]>>
    rpt VAR_EQ_TAC>>
    `ssa_map_ok na_3 ssa_2` by
      (match_mp_tac (GEN_ALL ssa_map_ok_more)>>
      qexists_tac`n'''`>>
      fs[next_var_rename_def]>>
      DECIDE_TAC)>>
    imp_res_tac fix_inconsistencies_props>>
    DECIDE_TAC)

val PAIR_ZIP_MEM = prove(``
  LENGTH c = LENGTH d ∧
  MEM (a,b) (ZIP (c,d)) ⇒
  MEM a c ∧ MEM b d``,
  rw[]>>imp_res_tac MEM_ZIP>>
  fs[MEM_EL]>>
  metis_tac[])

val ALOOKUP_ZIP_MEM = prove(``
  LENGTH a = LENGTH b ∧
  ALOOKUP (ZIP (a,b)) x = SOME y
  ⇒
  MEM x a ∧ MEM y b``,
  rw[]>>imp_res_tac ALOOKUP_MEM>>
  metis_tac[PAIR_ZIP_MEM])

val ALOOKUP_ALL_DISTINCT_REMAP = prove(``
  ∀ls x f y n.
  LENGTH ls = LENGTH x ∧
  ALL_DISTINCT (MAP f ls) ∧
  n < LENGTH ls ∧
  ALOOKUP (ZIP (ls,x)) (EL n ls) = SOME y
  ⇒
  ALOOKUP (ZIP (MAP f ls,x)) (f (EL n ls)) = SOME y``,
  Induct>>rw[]>>
  Cases_on`x`>>fs[]>>
  imp_res_tac ALL_DISTINCT_MAP>>
  Cases_on`n`>>fs[]>>
  `¬MEM h ls` by metis_tac[MEM_MAP]>>
  fs[MEM_EL]>>
  pop_assum(qspec_then`n'` assume_tac)>>rfs[]>>
  fs[]>>
  `f h ≠ f (EL n' ls)` by
    (SPOSE_NOT_THEN assume_tac>>
    first_x_assum(qspec_then`n'` assume_tac)>>rfs[]>>
    metis_tac[EL_MAP])>>
  metis_tac[])

val set_toAList_keys = prove(``
  set (MAP FST (toAList t)) = domain t``,
  fs[toAList_domain,EXTENSION])

fun fcs t r = Cases_on t>>Cases_on r>>fs[]

val is_phy_var_tac =
    fs[is_phy_var_def]>>
    `0<2:num` by DECIDE_TAC>>
    `∀k.(2:num)*k=k*2` by DECIDE_TAC>>
    metis_tac[arithmeticTheory.MOD_EQ_0];

val ssa_map_ok_inter = prove(``
  ssa_map_ok na ssa ⇒
  ssa_map_ok na (inter ssa ssa')``,
  fs[ssa_map_ok_def,lookup_inter]>>rw[]>>EVERY_CASE_TAC>>
  fs[]>>
  metis_tac[])

val ssa_cc_trans_exp_correct = prove(
``∀st w cst ssa na res.
  word_exp st w = SOME res ∧
  word_state_eq_rel st cst ∧
  ssa_locals_rel na ssa st.locals cst.locals
  ⇒
  word_exp cst (ssa_cc_trans_exp ssa w) = SOME res``,
  ho_match_mp_tac word_exp_ind>>rw[]>>
  fs[word_exp_def,ssa_cc_trans_exp_def]>>
  qpat_assum`A=SOME res` mp_tac
  >-
    (EVERY_CASE_TAC>>fs[ssa_locals_rel_def,word_state_eq_rel_def]>>
    res_tac>>
    fs[domain_lookup]>>
    qpat_assum`A = SOME v` SUBST_ALL_TAC>>
    rfs[])
  >-
    fs[word_state_eq_rel_def]
  >-
    (Cases_on`word_exp st w`>>
    res_tac>>fs[word_state_eq_rel_def,mem_load_def])
  >-
    (LET_ELIM_TAC>>
    qpat_assum`A=SOME res` mp_tac>>
    IF_CASES_TAC>>fs[]>>
    `ws = ws'` by
      (unabbrev_all_tac>>
      simp[MAP_MAP_o,MAP_EQ_f]>>
      rw[]>>
      fs[EVERY_MEM,MEM_MAP,PULL_EXISTS]>>
      res_tac>>
      fs[IS_SOME_EXISTS])>>
    fs[])
  >-
    (Cases_on`word_exp st w`>>
    res_tac>>fs[word_state_eq_rel_def,mem_load_def]))

val exp_tac =
    (last_x_assum kall_tac>>
    exists_tac>>
    EVERY_CASE_TAC>>fs[next_var_rename_def,word_exp_perm,get_var_perm]>>
    imp_res_tac ssa_locals_rel_get_var>>
    imp_res_tac ssa_cc_trans_exp_correct>>fs[word_state_eq_rel_def]>>
    rfs[word_exp_perm,evaluate_def]>>
    res_tac>>fs[set_var_def,set_store_def]>>
    match_mp_tac ssa_locals_rel_set_var>>
    fs[every_var_def])

val setup_tac = Cases_on`word_exp st exp`>>fs[]>>
                imp_res_tac ssa_cc_trans_exp_correct>>
                rfs[word_state_eq_rel_def]>>
                fs[Abbr`exp`,ssa_cc_trans_exp_def,option_lookup_def,set_var_def];

val ssa_cc_trans_correct = store_thm("ssa_cc_trans_correct",
``∀prog st cst ssa na.
  word_state_eq_rel st cst ∧
  ssa_locals_rel na ssa st.locals cst.locals ∧
  (*The following 3 assumptions are from the transform properties and
    are independent of semantics*)
  is_alloc_var na ∧
  every_var (λx. x < na) prog ∧
  ssa_map_ok na ssa
  ⇒
  ∃perm'.
  let (res,rst) = evaluate(prog,st with permute:=perm') in
  if (res = SOME Error) then T else
  let (prog',ssa',na') = ssa_cc_trans prog ssa na in
  let (res',rcst) = evaluate(prog',cst) in
    res = res' ∧
    word_state_eq_rel rst rcst ∧
    (case res of
      NONE =>
        ssa_locals_rel na' ssa' rst.locals rcst.locals
    | SOME _    => rst.locals = rcst.locals )``,
  completeInduct_on`prog_size (K 0) prog`>>
  rpt strip_tac>>
  fs[PULL_FORALL,evaluate_def]>>
  Cases_on`prog`
  >-
    exists_tac
  >-
    (exists_tac>>EVERY_CASE_TAC>>fs[set_vars_def]>>
    Cases_on`list_next_var_rename (MAP FST l) ssa na`>>
    Cases_on`r`>>
    fs[evaluate_def]>>
    imp_res_tac list_next_var_rename_lemma_1>>
    imp_res_tac list_next_var_rename_lemma_2>>
    fs[LET_THM]>>
    fs[MAP_ZIP,LENGTH_COUNT_LIST]>>
    imp_res_tac (INST_TYPE [gamma |-> beta] ssa_locals_rel_get_vars)>>
    pop_assum(Q.ISPECL_THEN[`ssa`,`na`,`cst`]assume_tac )>>
    rfs[set_vars_def]>>
    fs[ssa_locals_rel_def]>>
    first_x_assum(qspecl_then[`ssa`,`na`] assume_tac)>>
    rfs[]>>
    imp_res_tac get_vars_length_lemma>>
    CONJ_ASM1_TAC
    >-
      (rw[domain_lookup]>>
      fs[lookup_alist_insert]>>
      EVERY_CASE_TAC>>
      rfs[ALOOKUP_NONE,MAP_ZIP]>>
      `¬ (MEM x' (MAP FST l))` by
        (CCONTR_TAC>>
        fs[MEM_MAP]>>
        first_x_assum(qspec_then`x'` assume_tac)>>
        rfs[]>>
        metis_tac[])>>
      `x' ∈ domain q' ∧ x' ∈ domain ssa` by
        (CONJ_ASM1_TAC>-
          fs[domain_lookup]
        >>
        fs[EXTENSION]>>metis_tac[])>>
      metis_tac[domain_lookup])
    >>
    fs[strong_locals_rel_def]>>rw[]>>rfs[lookup_alist_insert]
    >-
      (Cases_on`MEM x' (MAP FST l)`>>
      fs[]>>
      Q.ISPECL_THEN [`MAP FST l`,`x`,`x'`] assume_tac ALOOKUP_ZIP_FAIL>>
      rfs[]>>fs[])
    >-
      (Cases_on`MEM x' (MAP FST l)`>>
      fs[]
      >-
        (`ALL_DISTINCT (MAP FST (ZIP (MAP FST l,x)))` by fs[MAP_ZIP]>>
        fs[MEM_EL]>>
        imp_res_tac ALOOKUP_ALL_DISTINCT_EL>>
        pop_assum(qspec_then `n'` mp_tac)>>
        discharge_hyps>>
        fs[LENGTH_ZIP]>>rw[]>>
        rfs[EL_ZIP]>>fs[]>>
        imp_res_tac ALOOKUP_ALL_DISTINCT_REMAP>>
        fs[LENGTH_MAP])
      >>
      Q.ISPECL_THEN [`MAP FST l`,`x`,`x'`] assume_tac ALOOKUP_ZIP_FAIL>>
      rfs[ssa_map_ok_def]>>fs[]>>
      ntac 11 (last_x_assum kall_tac)>>
      res_tac>>
      fs[domain_lookup]>>res_tac>>
      qabbrev_tac `ls = MAP (\x. THE (lookup x q')) (MAP FST l)`>>
      qsuff_tac `ALOOKUP (ZIP (ls,x)) v = NONE` >>
      fs[]>>fs[ALOOKUP_NONE]>>
      qpat_assum`A = ls` (sym_sub_tac)>>
      fs[MAP_ZIP,LENGTH_COUNT_LIST]>>
      fs[MEM_MAP]>>rw[]>>
      DECIDE_TAC)
    >>
      EVERY_CASE_TAC>>rfs[every_var_def]
      >-
        metis_tac[DECIDE``x'<na ⇒ x' < na + 4*LENGTH l``]
      >>
        `MEM x' (MAP FST l)` by
          metis_tac[ALOOKUP_ZIP_MEM,LENGTH_MAP]>>
        fs[EVERY_MEM]>>
        metis_tac[DECIDE``x'<na ⇒ x' < na + 4*LENGTH l``])
  >-(*Inst*)
    (exists_tac>>
    Cases_on`i`>> (TRY (Cases_on`a`))>> (TRY(Cases_on`m`))>>
    fs[next_var_rename_def,ssa_cc_trans_inst_def,inst_def,assign_def,word_exp_perm,evaluate_def,LET_THM]
    >-
      (Cases_on`word_exp st (Const c)`>>
      fs[set_var_def,word_exp_def]>>
      match_mp_tac ssa_locals_rel_set_var>>
      fs[every_var_inst_def,every_var_def])
    >-
      (Cases_on`r`>>fs[evaluate_def,inst_def,assign_def]>>
      qpat_abbrev_tac `exp = (Op b [Var n0;B])`>>
      setup_tac>>
      match_mp_tac ssa_locals_rel_set_var>>
      fs[every_var_inst_def,every_var_def])
    >-
      (qpat_abbrev_tac`exp = (Shift s (Var n0) B)`>>
      setup_tac>>
      match_mp_tac ssa_locals_rel_set_var>>
      fs[every_var_inst_def,every_var_def])
    >-
      (qpat_abbrev_tac`exp=((Op Add [Var n';A]))`>>
      setup_tac>>
      fs [mem_load_def]>> fs [GSYM mem_load_def]>>
      BasicProvers.CASE_TAC >> fs [] >>
      match_mp_tac ssa_locals_rel_set_var>>
      fs[every_var_inst_def,every_var_def])
    >>
      (qpat_abbrev_tac`exp=Op Add [Var n';A]`>>
      fs[get_var_perm]>>
      setup_tac>>
      Cases_on`get_var n st`>>fs[]>>imp_res_tac ssa_locals_rel_get_var>>
      fs[option_lookup_def]>>
      Cases_on`mem_store x x' st`>>
      fs[mem_store_def]))
  >-(*Assign*)
    exp_tac
  >-(*Get*)
    exp_tac
  >-(*Set*)
    exp_tac
  >-(*Store*)
    (exists_tac>>
    fs[word_exp_perm,get_var_perm]>>
    Cases_on`word_exp st e`>>fs[]>>
    Cases_on`get_var n st`>>fs[]>>
    imp_res_tac ssa_locals_rel_get_var>>
    imp_res_tac ssa_cc_trans_exp_correct>>
    rfs[word_state_eq_rel_def]>>
    EVERY_CASE_TAC>>fs[mem_store_def,word_state_eq_rel_def]>>
    rfs[]>>
    qpat_assum`A=x'''` sym_sub_tac>>
    qpat_assum`A=x''` sym_sub_tac>>
    fs[])
  >- (*Call*)
   (Cases_on`o'`
    >-
    (*Tail call*)
    (exists_tac>>
    fs[MAP_ZIP]>>
    qpat_abbrev_tac`ls = GENLIST (λx.2*x) (LENGTH l)`>>
    `ALL_DISTINCT ls` by
      (fs[Abbr`ls`,ALL_DISTINCT_GENLIST]>>
      rw[]>>DECIDE_TAC)>>
    fs[get_vars_perm]>>
    Cases_on`get_vars l st`>>fs[]>>
    imp_res_tac ssa_locals_rel_get_vars>>
    IF_CASES_TAC>>fs[]>>
    `¬bad_dest_args o1 ls` by
      (fs[Abbr`ls`,bad_dest_args_def]>>
      Cases_on`l`>>fs[GENLIST_CONS])>>
    `get_vars ls (set_vars ls x cst) = SOME x` by
      (match_mp_tac get_vars_set_vars_eq>>
      fs[Abbr`ls`,get_vars_length_lemma,LENGTH_MAP]>>
      metis_tac[get_vars_length_lemma])>>
    fs[set_vars_def]>>
    EVERY_CASE_TAC>>
    fs[call_env_def,dec_clock_def]>>
    ntac 2 (pop_assum mp_tac)>>
    qpat_abbrev_tac`cst'=cst with <|locals:=A;clock:=B|>`>>
    qpat_abbrev_tac`st'=st with <|locals:=A;permute:=B;clock:=C|>`>>
    `cst'=st'` by
      (unabbrev_all_tac>>fs[state_component_equality])>>
    rfs[])
    >>
    (*Non tail call*)
    PairCases_on`x`>> fs[] >>
    Q.PAT_ABBREV_TAC`pp = ssa_cc_trans X Y Z` >>
    PairCases_on`pp` >> simp[] >>
    pop_assum(mp_tac o SYM o SIMP_RULE std_ss[markerTheory.Abbrev_def]) >>
    simp_tac std_ss [ssa_cc_trans_def]>>
    LET_ELIM_TAC>>
    fs[evaluate_def,get_vars_perm,add_ret_loc_def]>>
    ntac 6 (TOP_CASE_TAC>>fs[])>>
    `domain stack_set ≠ {}` by
      fs[Abbr`stack_set`,domain_fromAList,toAList_not_empty]>>
    `¬bad_dest_args o1 conv_args` by
      (fs[Abbr`conv_args`,Abbr`names`,bad_dest_args_def]>>
      Cases_on`l`>>fs[GENLIST_CONS])>>
    Q.SPECL_THEN [`st`,`ssa`,`na+2`,`ls`,`cst`]
      mp_tac list_next_var_rename_move_preserve>>
    discharge_hyps>-
      (rw[]
      >-
        (match_mp_tac ssa_locals_rel_more>>
        fs[]>>DECIDE_TAC)
      >-
        (fs[cut_env_def,Abbr`ls`]>>
        metis_tac[SUBSET_DEF,toAList_domain])
      >-
        fs[Abbr`ls`,ALL_DISTINCT_MAP_FST_toAList]
      >-
        (match_mp_tac ssa_map_ok_more>>
        fs[]>>DECIDE_TAC))
    >>
    LET_ELIM_TAC>>fs[]>>
    Q.ISPECL_THEN [`ls`,`ssa`,`na`,`stack_mov`,`ssa'`,`na'`] assume_tac list_next_var_rename_move_props_2>>
    Q.ISPECL_THEN [`ls`,`ssa_cut`,`na'`,`ret_mov`,`ssa''`,`na''`] assume_tac list_next_var_rename_move_props_2>>
    Q.ISPECL_THEN [`x2`,`ssa_2_p`,`na_2_p`,`ren_ret_handler`,`ssa_2`,`na_2`] assume_tac ssa_cc_trans_props>>
    rfs[]>>
    fs[MAP_ZIP]>>
    `ALL_DISTINCT conv_args` by
      (fs[Abbr`conv_args`,ALL_DISTINCT_GENLIST]>>
      rw[]>>DECIDE_TAC)>>
    (*Establish invariants about ssa_cut to use later*)
    `domain ssa_cut = domain x1` by
      (fs[EXTENSION,Abbr`ssa_cut`,domain_inter]>>
      rw[EQ_IMP_THM]>>
      fs[cut_env_def,SUBSET_DEF]>>
      res_tac>>
      fs[ssa_locals_rel_def]>>
      metis_tac[domain_lookup])>>
    `∀x y. lookup x ssa_cut = SOME y ⇒ lookup x ssa' = SOME y` by
      (rw[]>>fs[Abbr`ssa_cut`,lookup_inter]>>
      EVERY_CASE_TAC>>fs[])>>
    `ssa_map_ok na' ssa_cut` by
      fs[Abbr`ssa_cut`,ssa_map_ok_inter]>>
    (*Probably need to case split here to deal with the 2 cases*)
    Cases_on`o0`>>fs[]
    >-
    (*No handler*)
    (qpat_assum`A=pp0` (sym_sub_tac)>>fs[Abbr`prog`]>>
    qpat_assum`A=stack_mov` (sym_sub_tac)>>fs[]>>
    fs[evaluate_def,LET_THM,Abbr`move_args`]>>
    `LENGTH conv_args = LENGTH names` by
      (unabbrev_all_tac >>fs[])>>
    fs[MAP_ZIP]>>
    imp_res_tac ssa_locals_rel_get_vars>>
    fs[Abbr`names`]>>
    `LENGTH l = LENGTH x` by
      metis_tac[get_vars_length_lemma]>>
    `get_vars conv_args (set_vars conv_args x rcst) = SOME x` by
      (match_mp_tac get_vars_set_vars_eq>>
      fs[Abbr`ls`,get_vars_length_lemma,LENGTH_MAP])>>
    fs[set_vars_def]>>
    qpat_abbrev_tac `rcst' =
      rcst with locals:= alist_insert conv_args x rcst.locals`>>
    (*Important preservation step*)
    `ssa_locals_rel na' ssa' st.locals rcst'.locals` by
      (fs[Abbr`rcst'`,Abbr`conv_args`]>>
      match_mp_tac ssa_locals_rel_ignore_list_insert>>
      fs[EVERY_MEM,MEM_GENLIST]>>
      rw[]>>
      is_phy_var_tac) >>
    fs[word_state_eq_rel_def]>>
    qabbrev_tac`f = option_lookup ssa'`>>
    (*Try to use cut_env_lemma from word_live*)
    Q.ISPECL_THEN [`x1`,`st.locals`,`rcst'.locals`,`x'`,`f`]
      mp_tac cut_env_lemma>>
    discharge_hyps>-
      (rfs[Abbr`f`]>>
      fs[ssa_locals_rel_def,strong_locals_rel_def]>>
      ntac 1 (last_x_assum kall_tac)>>
      rw[INJ_DEF]>-
        (SPOSE_NOT_THEN assume_tac>>
        `x'' ∈ domain st.locals ∧ y ∈ domain st.locals` by
          fs[SUBSET_DEF,cut_env_def]>>
        fs[domain_lookup,option_lookup_def,ssa_map_ok_def]>>
        res_tac>>
        fs[]>>
        metis_tac[])
      >>
        fs[option_lookup_def,domain_lookup]>>
        res_tac>>
        fs[]>>
        qpat_assum`A=SOME v` SUBST_ALL_TAC>>fs[])
    >>
    rw[Abbr`rcst'`]>>fs[add_ret_loc_def]>>
    IF_CASES_TAC>>fs[call_env_def]>>
    qpat_abbrev_tac`rcst' = rcst with locals := A`>>
    Q.ISPECL_THEN[
      `y:'a word_loc num_map`,`x'`,`st with clock := st.clock-1`,
      `f`,`rcst' with clock := st.clock-1`,`NONE:(num#'a wordLang$prog#num#num)option`,`NONE:(num#'a wordLang$prog#num#num)option`,`λn. rcst.permute (n+1)`]
      mp_tac (GEN_ALL push_env_s_val_eq)>>
    discharge_hyps>-
      rfs[Abbr`rcst'`]
    >>
    strip_tac>>
    rfs[LET_THM,env_to_list_def,dec_clock_def]>>
    qabbrev_tac `envx = push_env x'
            (NONE:(num # 'a wordLang$prog #num #num)option)
            (st with <|permute := perm; clock := st.clock − 1|>) with
          locals := fromList2 (q)`>>
    qpat_abbrev_tac `envy = (push_env y A B) with <| locals := C; clock := _ |>`>>
    assume_tac evaluate_stack_swap>>
    pop_assum(qspecl_then [`r`,`envx`] mp_tac)>>
    ntac 2 FULL_CASE_TAC>-
      (rw[]>>qexists_tac`perm`>>
       fs[dec_clock_def])>>
    `envx with stack := envy.stack = envy` by
      (unabbrev_all_tac>>
      fs[push_env_def,state_component_equality]>>
      fs[LET_THM,env_to_list_def,dec_clock_def])>>
    `s_val_eq envx.stack envy.stack` by
      (unabbrev_all_tac>> simp[] >> fs[])>>
    FULL_CASE_TAC
    >-
      (strip_tac>>pop_assum(qspec_then`envy.stack` mp_tac)>>
      discharge_hyps>-
      (unabbrev_all_tac>> simp[])>>
      strip_tac>>fs[]>>
      rfs[]>>
      (*Backwards chaining*)
      IF_CASES_TAC>-
        (qexists_tac`perm`>>fs[])>>
      Q.ISPECL_THEN [`(rcst' with clock := st.clock-1)`,
                    `r' with stack := st'`,`y`,
                    `NONE:(num#'a wordLang$prog#num#num)option`]
                    assume_tac push_env_pop_env_s_key_eq>>
      Q.ISPECL_THEN [`(st with <|permute:=perm;clock := st.clock-1|>)`,
                    `r'`,`x'`,
                    `NONE:(num#'a wordLang$prog#num#num)option`]
                    assume_tac push_env_pop_env_s_key_eq>>
      (*This went missing somewhere..*)
      `rcst'.clock = st.clock` by
        fs[Abbr`rcst'`]>>
      pop_assum SUBST_ALL_TAC>>
      fs[Abbr`envy`,Abbr`envx`,state_component_equality]>>
      rfs[]>>
      (*Now is a good place to establish the invariant ssa_locals_rel*)
      `ssa_locals_rel na' ssa_cut y'.locals y''.locals ∧
       word_state_eq_rel y' y''` by
      (fs[state_component_equality]>>
      `s_key_eq y'.stack y''.stack` by
        metis_tac[s_key_eq_trans,s_key_eq_sym]>>
      assume_tac pop_env_frame>>rfs[word_state_eq_rel_def]>>
      fs[LET_THM,ssa_locals_rel_def]>>
      rw[]
      >-
        (ntac 20 (last_x_assum kall_tac)>>
        res_tac>>
        qpat_assum`A=domain(fromAList l'')` (sym_sub_tac)>>
        fs[Abbr`f`,option_lookup_def]>>
        qexists_tac`x''`>>fs[]>>
        fs[Abbr`ssa_cut`,domain_inter,lookup_inter]>>
        EVERY_CASE_TAC>>fs[]>>
        metis_tac[domain_lookup])
      >-
        fs[domain_lookup]
      >-
        (`x'' ∈ domain ssa_cut` by metis_tac[domain_lookup]>>
        fs[domain_lookup]>>
        ntac 20 (last_x_assum kall_tac)>>
        res_tac>>
        `v = f x''` by fs[Abbr`f`,option_lookup_def]>>
        fs[push_env_def,LET_THM,env_to_list_def]>>
        fs[s_key_eq_def,s_val_eq_def]>>
        Cases_on`opt`>>Cases_on`opt'`>>
        fs[s_frame_key_eq_def,s_frame_val_eq_def]>>
        fs[lookup_fromAList]>>
        imp_res_tac key_map_implies>>
        rfs[]>>
        `l'' = ZIP(MAP FST l'',MAP SND l'')` by fs[ZIP_MAP_FST_SND_EQ]>>
        pop_assum SUBST1_TAC>>
        pop_assum (SUBST1_TAC o SYM)>>
        match_mp_tac ALOOKUP_key_remap_2>>
        fs[]>>CONJ_TAC>>
        metis_tac[LENGTH_MAP,ZIP_MAP_FST_SND_EQ])
      >>
        fs[cut_env_def,SUBSET_DEF]>>
        `x'' ∈ domain st.locals` by fs[domain_lookup]>>
        fs[domain_lookup])>>
      fs[]>>
      (*We set variable 2 but it is never in the
        locals so the ssa_locals_rel property is preserved*)
      `ssa_locals_rel na' ssa_cut y'.locals
        (set_var 2 w0 y'').locals` by
        (match_mp_tac ssa_locals_rel_ignore_set_var>>
        fs[]>> is_phy_var_tac)>>
      Q.SPECL_THEN [`y'`,`ssa_cut`,`na'+2`,`(MAP FST (toAList x1))`
                   ,`(set_var 2 w0 y'')`] mp_tac
                   list_next_var_rename_move_preserve>>
      discharge_hyps>-
      (rw[]
      >-
        (match_mp_tac (GEN_ALL ssa_locals_rel_more)>>
        fs[]>>
        qexists_tac`na'`>>fs[]>>
        rfs[])
      >-
        fs[Abbr`ls`,set_toAList_keys]
      >-
        fs[ALL_DISTINCT_MAP_FST_toAList,Abbr`ls`]
      >-
        (`na' ≤ na'+2`by DECIDE_TAC>>
        metis_tac[ssa_map_ok_more,Abbr`ssa_cut`,ssa_map_ok_inter])
      >>
        fs[word_state_eq_rel_def,set_var_def])>>
      LET_ELIM_TAC>>
      fs[Abbr`mov_ret_handler`,evaluate_def]>>
      rfs[LET_THM]>>
      `get_vars [2] rcst'' = SOME [w0]` by
        (fs[ssa_map_ok_more,DECIDE ``na:num ≤ na+2``]>>
        `¬ is_phy_var (na'+2)` by
          metis_tac[is_stack_var_flip,convention_partitions]>>
        fs[get_vars_def,get_var_def]>>
        first_x_assum(qspec_then`2` assume_tac)>>
        fs[is_phy_var_def,set_var_def])>>
      fs[set_vars_def,alist_insert_def]>>
      qabbrev_tac`res_st = (set_var x0 w0 y')`>>
      qpat_abbrev_tac`res_rcst = rcst'' with locals:=A`>>
      `ssa_locals_rel na_2_p ssa_2_p res_st.locals res_rcst.locals` by
        (unabbrev_all_tac>>fs[next_var_rename_def,set_var_def]>>
        rpt VAR_EQ_TAC>>
        qpat_assum`A=fromAList l'` sym_sub_tac>>
        match_mp_tac ssa_locals_rel_set_var>>
        fs[every_var_def]>>
        rfs[]>>
        DECIDE_TAC)>>
      first_x_assum(qspecl_then[`x2`,`res_st`,`res_rcst`,`ssa_2_p`,`na_2_p`] mp_tac)>>
      size_tac>>discharge_hyps>-
      (fs[word_state_eq_rel_def,Abbr`res_st`,Abbr`res_rcst`,set_var_def]>>
      fs[every_var_def,next_var_rename_def]>>rw[]>>
      TRY
        (match_mp_tac every_var_mono>>
        HINT_EXISTS_TAC>>fs[]>>
        DECIDE_TAC)>>
      metis_tac[is_alloc_var_add,ssa_map_ok_extend,convention_partitions])>>
      rw[]>>
      qspecl_then[`r`,`push_env x' (NONE:(num#'a wordLang$prog#num#num) option)
            (st with <|permute := perm; clock := st.clock − 1|>) with
          locals := fromList2 q`,`perm'`]
      assume_tac permute_swap_lemma>>
      rfs[LET_THM]>>
      (*"Hot-swap" the suffix of perm, maybe move into lemma*)
      qexists_tac`λn. if n = 0:num then perm 0 else perm'' (n-1)`>>
      qpat_abbrev_tac `env1 = push_env A B C with locals := D`>>
      qpat_assum `A = (SOME B,C)` mp_tac>>
      qpat_abbrev_tac `env2 = push_env A B C with
                    <|locals:=D; permute:=E|>`>>
      strip_tac>>
      `env1 = env2` by
      (unabbrev_all_tac>>
      rpt (pop_assum kall_tac)>>
      simp[push_env_def,LET_THM,env_to_list_def
        ,state_component_equality,FUN_EQ_THM])>>
      fs[pop_env_perm,set_var_perm]>>
      EVERY_CASE_TAC>>fs[])
    >-
      (*Excepting without handler*)
      (fs[]>>strip_tac>>
      imp_res_tac s_val_eq_LAST_N_exists>>
      first_x_assum(qspecl_then[`envy.stack`,`e'`,`ls'`] assume_tac)>>
      rfs[]>>
      qexists_tac`perm`>>
      `ls'''=ls'` by
        (unabbrev_all_tac>>
        fs[push_env_def,env_to_list_def,LET_THM]>>
        Cases_on`st.handler < LENGTH st.stack`
        >-
          (imp_res_tac miscTheory.LAST_N_TL>>
          rfs[]>>fs[])
        >>
          `st.handler = LENGTH st.stack` by DECIDE_TAC>>
          rpt (qpat_assum `LAST_N A B = C` mp_tac)>-
          simp[LAST_N_LENGTH_cond])>>
      fs[]>>
      `lss = lss'` by
        (match_mp_tac LIST_EQ_MAP_PAIR>>fs[]>>
        qsuff_tac `e = e''`>-metis_tac[]>>
        unabbrev_all_tac>>
        fs[push_env_def,LET_THM,env_to_list_def]>>
        `st.handler < LENGTH st.stack` by
          (SPOSE_NOT_THEN assume_tac>>
          `st.handler = LENGTH st.stack` by DECIDE_TAC>>
          ntac 2 (qpat_assum`LAST_N A B = C` mp_tac)>>
          simp[LAST_N_LENGTH2])>>
        ntac 2 (qpat_assum`LAST_N A B = C` mp_tac)>>
        fs[LAST_N_TL])>>
      metis_tac[s_val_and_key_eq,s_key_eq_sym,s_key_eq_trans])
    >>
      (* 3 subgoals *)
      rw[]>>qexists_tac`perm`>>fs[]>>
      pop_assum(qspec_then`envy.stack` mp_tac)>>
      (discharge_hyps>- (unabbrev_all_tac>>fs[]))>>
      rw[]>>fs[])
  >>
    (*Handler reasoning*)
    qpat_assum`A=(pp0,pp1,pp2)` mp_tac>>PairCases_on`x''`>>fs[]>>
    LET_ELIM_TAC>>
    rfs[]>>
    qpat_assum`A=pp0` (sym_sub_tac)>>fs[Abbr`prog'`]>>
    qpat_assum`A=stack_mov` (sym_sub_tac)>>fs[]>>
    fs[evaluate_def,LET_THM,Abbr`move_args`]>>
    `LENGTH conv_args = LENGTH names` by
      (unabbrev_all_tac >>fs[])>>
    fs[MAP_ZIP]>>
    imp_res_tac ssa_locals_rel_get_vars>>
    fs[Abbr`names`]>>
    `LENGTH l = LENGTH x` by
      metis_tac[get_vars_length_lemma]>>
    `get_vars conv_args (set_vars conv_args x rcst) = SOME x` by
      (match_mp_tac get_vars_set_vars_eq>>
      fs[Abbr`ls`,get_vars_length_lemma,LENGTH_MAP])>>
    fs[set_vars_def]>>
    qpat_abbrev_tac `rcst' =
      rcst with locals:= alist_insert conv_args x rcst.locals`>>
    (*Important preservation lemma*)
    `ssa_locals_rel na' ssa' st.locals rcst'.locals` by
      (fs[Abbr`rcst'`,Abbr`conv_args`]>>
      match_mp_tac ssa_locals_rel_ignore_list_insert>>
      fs[EVERY_MEM,MEM_GENLIST]>>
      rw[]>>
      is_phy_var_tac) >>
    fs[word_state_eq_rel_def]>>
    qabbrev_tac`f = option_lookup ssa'`>>
    (*Try to use cut_env_lemma from word_live*)
    Q.ISPECL_THEN [`x1`,`st.locals`,`rcst'.locals`,`x'`,`f`]
      mp_tac cut_env_lemma>>
    discharge_hyps>-
      (rfs[Abbr`f`]>>
      fs[ssa_locals_rel_def,strong_locals_rel_def]>>
      rw[INJ_DEF]>-
        (SPOSE_NOT_THEN assume_tac>>
        `x'' ∈ domain st.locals ∧ y ∈ domain st.locals` by
          fs[SUBSET_DEF,cut_env_def]>>
        fs[domain_lookup,option_lookup_def,ssa_map_ok_def]>>
        ntac 20 (last_x_assum kall_tac)>>
        res_tac>>
        fs[]>>
        metis_tac[])
      >>
        ntac 20 (last_x_assum kall_tac)>>
        fs[option_lookup_def,domain_lookup]>>
        res_tac>>
        fs[]>>
        qpat_assum`A=SOME v` SUBST_ALL_TAC>>fs[])
    >>
    rw[Abbr`rcst'`]>>fs[add_ret_loc_def]>>
    IF_CASES_TAC>>fs[call_env_def]>>
    qpat_abbrev_tac`rcst' = rcst with locals := A`>>
    Q.ISPECL_THEN
      [`y:'a word_loc num_map`,`x'`,`st with clock := st.clock-1`,
      `f`,`rcst' with clock := st.clock-1`,`SOME(2:num,cons_exc_handler,x''2,x''3)`,`SOME (x''0,x''1,x''2,x''3)`,`λn. rcst.permute (n+1)`]
      mp_tac (GEN_ALL push_env_s_val_eq)>>
    discharge_hyps>-
      rfs[Abbr`rcst'`]
    >>
    strip_tac>>
    rfs[LET_THM,env_to_list_def,dec_clock_def]>>
    qabbrev_tac `envx = push_env x' (SOME (x''0,x''1,x''2,x''3))
            (st with <|permute := perm; clock := st.clock − 1|>) with
          locals := fromList2 q`>>
    qpat_abbrev_tac `envy = (push_env y A B) with <| locals := C; clock := _ |>`>>
    assume_tac evaluate_stack_swap>>
    pop_assum(qspecl_then [`r`,`envx`] mp_tac)>>
    ntac 2 FULL_CASE_TAC>-
      (rw[]>>qexists_tac`perm`>>
       fs[dec_clock_def])>>
    `envx with stack := envy.stack = envy` by
      (unabbrev_all_tac>>
      fs[push_env_def,state_component_equality]>>
      fs[LET_THM,env_to_list_def,dec_clock_def])>>
    `s_val_eq envx.stack envy.stack` by
      (unabbrev_all_tac>>fs[]>>simp[])>>
    (*More props theorems that will be useful*)
    `ssa_map_ok na_2_p ssa_2_p ∧ is_alloc_var na_2_p` by
      (fs[next_var_rename_def]>>
      rpt VAR_EQ_TAC>>rw[]
      >-
        (match_mp_tac ssa_map_ok_extend>>
        fs[]>>metis_tac[convention_partitions])
      >>
        metis_tac[is_alloc_var_add])>>
    fs[]>>
    Q.ISPECL_THEN [`x''1`,`ssa_3_p`,`na_3_p`,`ren_exc_handler`,`ssa_3`,`na_3`] mp_tac ssa_cc_trans_props>>
    discharge_hyps_keep>-
      (fs[next_var_rename_def]>>
      rpt VAR_EQ_TAC>>rw[]
      >-
        (match_mp_tac ssa_map_ok_extend>>
        fs[]>>rw[]>-
          (match_mp_tac (GEN_ALL ssa_map_ok_more)>>
          qexists_tac`na''`>>
          fs[]>>DECIDE_TAC)>>
        metis_tac[convention_partitions])
      >>
        metis_tac[is_alloc_var_add])>>
    strip_tac>>
    FULL_CASE_TAC
    >-
      (strip_tac>>pop_assum(qspec_then`envy.stack` mp_tac)>>
      discharge_hyps>-
      (unabbrev_all_tac>> fs[])>>
      strip_tac>>fs[]>>
      rfs[]>>
      (*Backwards chaining*)
      IF_CASES_TAC>-
        (qexists_tac`perm`>>fs[])>>
      Q.ISPECL_THEN [`(rcst' with clock := st.clock-1)`,
                    `r' with stack := st'`,`y`,
                    `SOME (2:num,cons_exc_handler,x''2,x''3)`]
                    assume_tac push_env_pop_env_s_key_eq>>
      Q.ISPECL_THEN [`(st with <|permute:=perm;clock := st.clock-1|>)`,
                    `r'`,`x'`,
                    `SOME (x''0,x''1,x''2,x''3)`]
                    assume_tac push_env_pop_env_s_key_eq>>
      (*This went missing somewhere..*)
      `rcst'.clock = st.clock` by fs[Abbr`rcst'`]>>
      pop_assum SUBST_ALL_TAC>>
      rfs[]>>
      fs[Abbr`envy`,Abbr`envx`,state_component_equality]>>
      rfs[] >>
      (*Now is a good place to establish the invariant ssa_locals_rel*)
      `ssa_locals_rel na' ssa_cut y'.locals y''.locals ∧
       word_state_eq_rel y' y''` by
      (fs[state_component_equality]>>
      `s_key_eq y'.stack y''.stack` by
        metis_tac[s_key_eq_trans,s_key_eq_sym]>>
      assume_tac pop_env_frame>>rfs[word_state_eq_rel_def]>>
      fs[LET_THM,ssa_locals_rel_def]>>
      rw[]
      >-
        (ntac 50 (last_x_assum kall_tac)>>
        res_tac>>
        qpat_assum`A=domain(fromAList l'')` (sym_sub_tac)>>
        fs[Abbr`f`,option_lookup_def]>>
        qexists_tac`x''`>>fs[]>>
        fs[Abbr`ssa_cut`,domain_inter,lookup_inter]>>
        EVERY_CASE_TAC>>fs[]>>
        metis_tac[domain_lookup])
      >-
        fs[domain_lookup]
      >-
        (`x'' ∈ domain ssa_cut` by metis_tac[domain_lookup]>>
        fs[domain_lookup]>>
        ntac 50 (last_x_assum kall_tac)>>
        res_tac>>
        `v = f x''` by fs[Abbr`f`,option_lookup_def]>>
        fs[push_env_def,LET_THM,env_to_list_def]>>
        fs[s_key_eq_def,s_val_eq_def]>>
        Cases_on`opt`>>Cases_on`opt'`>>
        fs[s_frame_key_eq_def,s_frame_val_eq_def]>>
        fs[lookup_fromAList]>>
        imp_res_tac key_map_implies>>
        rfs[]>>
        `l'' = ZIP(MAP FST l'',MAP SND l'')` by fs[ZIP_MAP_FST_SND_EQ]>>
        pop_assum SUBST1_TAC>>
        pop_assum (SUBST1_TAC o SYM)>>
        match_mp_tac ALOOKUP_key_remap_2>>
        fs[]>>CONJ_TAC>>
        metis_tac[LENGTH_MAP,ZIP_MAP_FST_SND_EQ])
      >>
        fs[cut_env_def,SUBSET_DEF]>>
        `x'' ∈ domain st.locals` by fs[domain_lookup]>>
        fs[domain_lookup])>>
      fs[]>>
      (*We set variable 2 but it is never in the
        locals so the ssa_locals_rel property is preserved*)
      `ssa_locals_rel na' ssa_cut y'.locals
        (set_var 2 w0 y'').locals` by
        (match_mp_tac ssa_locals_rel_ignore_set_var>>
        fs[]>> is_phy_var_tac)>>
      Q.SPECL_THEN [`y'`,`ssa_cut`,`na'+2`,`(MAP FST (toAList x1))`
                   ,`(set_var 2 w0 y'')`] mp_tac
                   list_next_var_rename_move_preserve>>
      discharge_hyps>-
      (rw[]
      >-
        (match_mp_tac (GEN_ALL ssa_locals_rel_more)>>
        fs[]>>
        qexists_tac`na'`>>fs[]>>
        rfs[])
      >-
        fs[Abbr`ls`,set_toAList_keys]
      >-
        fs[ALL_DISTINCT_MAP_FST_toAList,Abbr`ls`]
      >-
        (`na' ≤ na'+2`by DECIDE_TAC>>
        metis_tac[ssa_map_ok_more,Abbr`ssa_cut`,ssa_map_ok_inter])
      >>
        fs[word_state_eq_rel_def,set_var_def])>>
      LET_ELIM_TAC>>
      fs[Abbr`cons_ret_handler`,Abbr`mov_ret_handler`,evaluate_def]>>
      rfs[LET_THM]>>
      `get_vars [2] rcst'' = SOME [w0]` by
        (fs[ssa_map_ok_more,DECIDE ``na:num ≤ na+2``]>>
        `¬ is_phy_var (na'+2)` by
          metis_tac[is_stack_var_flip,convention_partitions]>>
        fs[get_vars_def,get_var_def]>>
        first_x_assum(qspec_then`2` assume_tac)>>
        fs[is_phy_var_def,set_var_def])>>
      fs[set_vars_def,alist_insert_def]>>
      qabbrev_tac`res_st = (set_var x0 w0 y')`>>
      qpat_abbrev_tac`res_rcst = rcst'' with locals:=A`>>
      `ssa_locals_rel na_2_p ssa_2_p res_st.locals res_rcst.locals` by
        (unabbrev_all_tac>>fs[next_var_rename_def,set_var_def]>>
        rpt VAR_EQ_TAC>>
        qpat_assum`A=fromAList l'` sym_sub_tac>>
        match_mp_tac ssa_locals_rel_set_var>>
        fs[every_var_def]>>
        rfs[]>>
        DECIDE_TAC)>>
      first_x_assum(qspecl_then[`x2`,`res_st`,`res_rcst`,`ssa_2_p`,`na_2_p`] mp_tac)>>
      size_tac>>discharge_hyps>-
      (fs[word_state_eq_rel_def,Abbr`res_st`,Abbr`res_rcst`,set_var_def]>>
      fs[every_var_def,next_var_rename_def]>>rw[]>>
      TRY
        (match_mp_tac every_var_mono>>
        qexists_tac `λx. x <na`>>fs[]>>
        rw[]>>DECIDE_TAC) >>
      metis_tac[is_alloc_var_add,ssa_map_ok_extend,convention_partitions])>>
      rw[]>>
      qspecl_then[`r`,`push_env x' (SOME(x''0,x''1,x''2,x''3))
            (st with <|permute := perm; clock := st.clock − 1|>) with
          locals := fromList2 q`,`perm'`]
      assume_tac permute_swap_lemma>>
      rfs[LET_THM]>>
      (*"Hot-swap" the suffix of perm, maybe move into lemma*)
      qexists_tac`λn. if n = 0:num then perm 0 else perm'' (n-1)`>>
      qpat_abbrev_tac `env1 = push_env A B C with locals := D`>>
      qpat_assum `A = (SOME B,C)` mp_tac>>
      qpat_abbrev_tac `env2 = push_env A B C with
                    <|locals:=D; permute:=E|>`>>
      strip_tac>>
      `env1 = env2` by
      (unabbrev_all_tac>>
      rpt (pop_assum kall_tac)>>
      simp[push_env_def,LET_THM,env_to_list_def
        ,state_component_equality,FUN_EQ_THM])>>
      fs[pop_env_perm,set_var_perm]>>
      Cases_on`evaluate(x2,res_st with permute:=perm')`>>
      Cases_on`evaluate(ren_ret_handler,res_rcst)`>>fs[]>>
      Cases_on`q'`>>fs[]>>
      Cases_on`q''`>>fs[]>>
      Q.SPECL_THEN [`na_3`,`ssa_2`,`ssa_3`] mp_tac fix_inconsistencies_correctL>>
      `na_2 ≤ na_3` by
       (fs[next_var_rename_def]>>
       rpt VAR_EQ_TAC>>
       DECIDE_TAC)>>
      discharge_hyps>-
        (rfs[]>>
       metis_tac[ssa_map_ok_more])>>
      rfs[LET_THM]>>
      rw[]>>
      pop_assum (qspecl_then[`r''`,`r'''`] mp_tac)>>
      discharge_hyps>-
        (metis_tac[ssa_locals_rel_more,ssa_map_ok_more])>>
      Cases_on`evaluate(ret_cons,r''')`>>fs[word_state_eq_rel_def])
    >-
      (*Excepting with handler*)
      (fs[]>>strip_tac>>
      imp_res_tac s_val_eq_LAST_N_exists>>
      first_x_assum(qspecl_then[`envy.stack`,`e'`,`ls'`] assume_tac)>>
      rfs[]>>
      unabbrev_all_tac>>
      fs[push_env_def,LET_THM,env_to_list_def]>>
      rpt (qpat_assum `LAST_N A B = C` mp_tac)>>
      simp[LAST_N_LENGTH_cond]>>
      rpt strip_tac>>
      fs[domain_fromAList]>>
      imp_res_tac list_rearrange_keys>>
      `set (MAP FST lss') = domain y` by
        (qpat_assum`A=MAP FST lss'` (SUBST1_TAC o SYM)>>
        fs[EXTENSION]>>rw[EXISTS_PROD]>>
        simp[MEM_MAP,QSORT_MEM]>>rw[EQ_IMP_THM]
        >-
          (Cases_on`y'`>>
          fs[MEM_toAList]>>
          imp_res_tac domain_lookup>>
          metis_tac[])
        >>
          fs[EXISTS_PROD,MEM_toAList]>>
          metis_tac[domain_lookup])>>
      `domain x' = set (MAP FST lss)` by
        (qpat_assum `A = MAP FST lss` (SUBST1_TAC o SYM)>>
          fs[EXTENSION,MEM_MAP,QSORT_MEM,MEM_toAList
            ,EXISTS_PROD,domain_lookup])>>
      fs[word_state_eq_rel_def]>>
      rfs[]>>
      fs[domain_fromAList]>>
      IF_CASES_TAC>-
        (qexists_tac`perm`>>fs[])>>
      qabbrev_tac`ssa_cut = inter ssa' x1`>>
      qpat_abbrev_tac`cres=r'' with <|locals:= A;stack := B;handler:=C|>`>>
      `ssa_locals_rel na' ssa_cut r'.locals cres.locals ∧
       word_state_eq_rel r' cres` by
      (fs[Abbr`cres`,LET_THM,ssa_locals_rel_def,state_component_equality]>>
      rw[Abbr`ssa_cut`]
      >-
        (ntac 20 (last_x_assum kall_tac)>>
        fs[domain_fromAList,option_lookup_def,lookup_inter]>>
        EVERY_CASE_TAC>>fs[]>>
        qexists_tac`x''`>>fs[]>>
        metis_tac[EXTENSION,domain_lookup])
      >-
        (`x'' ∈ domain (fromAList lss)` by metis_tac[domain_lookup]>>
        fs[domain_fromAList]>>
        qpat_assum`A=MAP FST lss` sym_sub_tac>>
        metis_tac[MEM_MAP,mem_list_rearrange])
      >-
        (`x'' ∈ domain (fromAList lss)` by metis_tac[domain_lookup]>>
        fs[domain_fromAList]>>
        `x'' ∈ domain x'` by metis_tac[MEM_MAP,mem_list_rearrange]>>
        `x'' ∈ domain ssa' ∧ x'' ∈ domain x1` by
          (fs[cut_env_def,EXTENSION,domain_inter]>>
          metis_tac[])>>
        `THE (lookup x'' (inter ssa' x1)) = option_lookup ssa' x''` by
          fs[lookup_inter,option_lookup_def,domain_lookup]>>
        fs[lookup_fromAList]>>
        `lss' = ZIP(MAP FST lss',MAP SND lss')` by fs[ZIP_MAP_FST_SND_EQ]>>
        pop_assum SUBST_ALL_TAC>>
        `lss = ZIP(MAP FST lss,MAP SND lss)` by fs[ZIP_MAP_FST_SND_EQ]>>
        pop_assum SUBST_ALL_TAC>>
        fs[MAP_ZIP]>>
        imp_res_tac key_map_implies>>
        rfs[]>>
        pop_assum sym_sub_tac>>
        qpat_assum `A=MAP SND lss'` sym_sub_tac>>
        match_mp_tac ALOOKUP_key_remap_2>>
        rw[])
      >-
        (`x'' ∈ domain (fromAList lss)` by metis_tac[domain_lookup]>>
        fs[domain_fromAList]>>
        qpat_assum`A=MAP FST lss` sym_sub_tac>>
        `x'' ∈ domain x'` by metis_tac[MEM_MAP,mem_list_rearrange]>>
        fs[EXTENSION,every_var_def]>>res_tac>>
        fs[every_name_def,toAList_domain,EVERY_MEM]>>
        `x'' < na` by fs[]>>
        DECIDE_TAC)
      >>
        fs[word_state_eq_rel_def]>>
        metis_tac[s_key_eq_trans,s_val_and_key_eq])>>
      `ssa_locals_rel na' ssa_cut r'.locals
        (set_var 2 w0 cres).locals` by
        (match_mp_tac ssa_locals_rel_ignore_set_var>>
        fs[]>>rw[]>> is_phy_var_tac)>>
      Q.SPECL_THEN [`r'`,`ssa_cut`,`na'+2`,`(MAP FST (toAList x1))`
                   ,`(set_var 2 w0 cres)`] mp_tac
                   list_next_var_rename_move_preserve>>
      discharge_hyps>-
      (rw[]
      >-
        (match_mp_tac (GEN_ALL ssa_locals_rel_more)>>
        fs[]>>
        qexists_tac`na'`>>fs[]>>
        rfs[])
      >-
        fs[domain_fromAList,set_toAList_keys]
      >-
        fs[ALL_DISTINCT_MAP_FST_toAList]
      >-
        (`na' ≤ na'+2`by DECIDE_TAC>>
        metis_tac[ssa_map_ok_more,Abbr`ssa_cut`,ssa_map_ok_inter])
      >>
        fs[word_state_eq_rel_def,set_var_def])>>
      LET_ELIM_TAC>>
      rfs[LET_THM,evaluate_def]>>
      `get_vars [2] rcst' = SOME [w0]` by
        (fs[ssa_map_ok_more,DECIDE ``na:num ≤ na+2``]>>
        `¬ is_phy_var (na'+2)` by
          metis_tac[is_stack_var_flip,convention_partitions]>>
        fs[get_vars_def,get_var_def]>>
        first_x_assum(qspec_then`2` assume_tac)>>
        fs[is_phy_var_def,set_var_def])>>
      fs[set_vars_def,alist_insert_def]>>
      qabbrev_tac`res_st = (set_var x''0 w0 r')`>>
      qpat_abbrev_tac`res_rcst = rcst'' with locals:=A`>>
      `ssa_locals_rel na_3_p ssa_3_p res_st.locals res_rcst.locals` by
        (unabbrev_all_tac>>fs[next_var_rename_def,set_var_def]>>
        rpt VAR_EQ_TAC>>
        qpat_assum`A=fromAList lss` sym_sub_tac>>
        match_mp_tac ssa_locals_rel_set_var>>
        fs[every_var_def]>>
        `na'' ≤ n'` by DECIDE_TAC>>
        rw[]>>
        TRY(DECIDE_TAC)>>
        metis_tac[ssa_locals_rel_more,ssa_map_ok_more])>>
      first_x_assum(qspecl_then[`x''1`,`res_st`,`res_rcst`,`ssa_3_p`,`na_3_p`] mp_tac)>>
      size_tac>>discharge_hyps>-
      (fs[word_state_eq_rel_def,Abbr`res_st`,Abbr`res_rcst`,set_var_def]>>
      fs[every_var_def,next_var_rename_def]>>rw[]>>
      rfs[]>>
      match_mp_tac every_var_mono>>
      HINT_EXISTS_TAC>>fs[]>>
      DECIDE_TAC)>>
      rw[]>>
      qspecl_then[`r`,`push_env x' (SOME (x''0,x''1,x''2,x''3))
            (st with <|permute := perm; clock := st.clock − 1|>) with
          locals := fromList2 q`,`perm'`]
        assume_tac permute_swap_lemma>>
      rfs[LET_THM,push_env_def,env_to_list_def]>>
      (*"Hot-swap" the suffix of perm, maybe move into lemma*)
      qexists_tac`λn. if n = 0:num then perm 0 else perm'' (n-1)`>>
      qpat_abbrev_tac `env1 = st with <|locals:= A; stack:= B; permute:= C; handler:=D;clock:=E|>`>>
      qpat_assum `A = (SOME B,C)` mp_tac>>
      qpat_abbrev_tac `env2 = st with <|locals:= A; stack:= B; permute:= C; handler:=D;clock:=E|>`>>
      strip_tac>>
      `env1 = env2` by
      (unabbrev_all_tac>>
      rpt(pop_assum kall_tac)>>
      simp[state_component_equality,FUN_EQ_THM])>>
      fs[pop_env_perm,set_var_perm]>>
      EVERY_CASE_TAC>>fs[]>>
      Cases_on`evaluate(x''1,res_st with permute:=perm')`>>
      Cases_on`evaluate(ren_exc_handler,res_rcst)`>>fs[]>>
      Cases_on`q''`>>fs[]>>
      Cases_on`q'`>>fs[]>>
      (*Fix inconsistencies*)
      Q.SPECL_THEN [`na_3`,`ssa_2`,`ssa_3`] assume_tac fix_inconsistencies_correctR>>rfs[LET_THM]>>
      pop_assum (qspecl_then[`r''`,`r'''`] mp_tac)>>
      discharge_hyps>-
        (metis_tac[ssa_locals_rel_more,ssa_map_ok_more])>>
      Cases_on`evaluate(exc_cons,r''')`>>fs[word_state_eq_rel_def])
    >>
      rw[]>>qexists_tac`perm`>>fs[]>>
      first_x_assum(qspec_then`envy.stack` mp_tac)>>
      (discharge_hyps>- (unabbrev_all_tac>>fs[]))>>
      rw[]>>fs[])
  >- (*Seq*)
    (rw[]>>fs[evaluate_def,ssa_cc_trans_def,LET_THM]>>
    last_assum(qspecl_then[`p`,`st`,`cst`,`ssa`,`na`] mp_tac)>>
    size_tac>>
    discharge_hyps>>fs[every_var_def]>>rw[]>>
    Cases_on`ssa_cc_trans p ssa na`>>Cases_on`r`>>fs[]>>
    Cases_on`ssa_cc_trans p0 q' r'`>>Cases_on`r`>>fs[]>>
    fs[evaluate_def,LET_THM]>>
    Cases_on`evaluate(p,st with permute:=perm')`>>fs[]
    >- (qexists_tac`perm'`>>fs[]) >>
    Cases_on`evaluate(q,cst)`>>fs[]>>
    reverse (Cases_on`q'''''`)
    >-
      (qexists_tac`perm'`>>rw[]>>fs[])
    >>
    fs[]>>
    first_assum(qspecl_then[`p0`,`r`,`r'''`,`q'`,`r'`] mp_tac)>>
    size_tac>>
    discharge_hyps>-
      (rfs[]>>imp_res_tac ssa_cc_trans_props>>
      fs[]>>
      match_mp_tac every_var_mono>>
      HINT_EXISTS_TAC>>
      fs[]>>DECIDE_TAC)>>
    rw[]>>
    qspecl_then[`p`,`st with permute:=perm'`,`perm''`]
      assume_tac permute_swap_lemma>>
    rfs[LET_THM]>>
    qexists_tac`perm'''`>>rw[]>>fs[])
  >- (*If*)
   (qpat_abbrev_tac `A = ssa_cc_trans B C D` >>
    PairCases_on`A`>>simp[]>>
    pop_assum(mp_tac o SYM o SIMP_RULE std_ss[markerTheory.Abbrev_def]) >>
    fs[evaluate_def,ssa_cc_trans_def]>>
    LET_ELIM_TAC>>fs[get_var_perm,get_var_imm_perm]>>
    qpat_assum`B = A0` sym_sub_tac>>fs[evaluate_def]>>
    Cases_on`get_var n st`>>fs[]>>
    Cases_on`x`>>fs[]>>
    Cases_on`get_var_imm r st`>>fs[]>>
    Cases_on`x`>>fs[]>>
    imp_res_tac ssa_locals_rel_get_var>>fs[Abbr`r1'`]>>
    `get_var_imm ri' cst = SOME(Word c'')` by
      (Cases_on`r`>>fs[Abbr`ri'`,get_var_imm_def]>>
      metis_tac[ssa_locals_rel_get_var])>>
    Cases_on`word_cmp c c' c''`>>fs[]
    >-
      (first_assum(qspecl_then[`p`,`st`,`cst`,`ssa`,`na`] mp_tac)>>
      size_tac>>
      discharge_hyps>-
        (rfs[]>>imp_res_tac ssa_cc_trans_props>>
        fs[every_var_def])>>
      rw[]>>
      qexists_tac`perm'`>>fs[LET_THM]>>
      Cases_on`evaluate(p,st with permute := perm')`>>
      Cases_on`evaluate(e2',cst)`>>fs[]>>
      Cases_on`q'`>>fs[]>>rfs[]>>
      Q.SPECL_THEN [`na3`,`ssa2`,`ssa3`] mp_tac fix_inconsistencies_correctL>>
      discharge_hyps>-
        (imp_res_tac ssa_cc_trans_props>>
        metis_tac[ssa_map_ok_more])>>
      rfs[LET_THM]>>
      rw[]>>
      pop_assum (qspecl_then[`r'`,`r''`] mp_tac)>>
      discharge_hyps>-
        (imp_res_tac ssa_cc_trans_props>>
        metis_tac[ssa_locals_rel_more,ssa_map_ok_more])>>
      Cases_on`evaluate(e2_cons,r'')`>>fs[word_state_eq_rel_def])
    >>
      (first_assum(qspecl_then[`p0`,`st`,`cst`,`ssa`,`na2`] mp_tac)>>
      size_tac>>
      discharge_hyps>-
        (rfs[]>>imp_res_tac ssa_cc_trans_props>>rw[]
        >-
          metis_tac[ssa_locals_rel_more]
        >-
          (fs[every_var_def]>>match_mp_tac every_var_mono>>
          Q.EXISTS_TAC`λx.x<na`>>fs[] >>
          DECIDE_TAC)
        >>
          metis_tac[ssa_map_ok_more])
      >>
      rw[]>>
      qexists_tac`perm'`>>fs[LET_THM]>>
      Cases_on`evaluate(p0,st with permute := perm')`>>
      Cases_on`evaluate(e3',cst)`>>fs[]>>
      Cases_on`q'`>>fs[]>>rfs[]>>
      (*Start reasoning about fix_inconsistencies*)
      Q.SPECL_THEN [`na3`,`ssa2`,`ssa3`] mp_tac fix_inconsistencies_correctR>>
      discharge_hyps>-
        (imp_res_tac ssa_cc_trans_props>>
        metis_tac[ssa_map_ok_more])>>
      rfs[LET_THM]>>rw[]>>
      pop_assum (qspecl_then[`r'`,`r''`] mp_tac)>>
      discharge_hyps>-
        (imp_res_tac ssa_cc_trans_props>>
        metis_tac[ssa_locals_rel_more,ssa_map_ok_more])>>
      Cases_on`evaluate(e3_cons,r'')`>>fs[word_state_eq_rel_def]))
  >- (*Alloc*)
    (qabbrev_tac`A = ssa_cc_trans (Alloc n s) ssa na`>>
    PairCases_on`A`>>fs[ssa_cc_trans_def]>>
    pop_assum mp_tac>>
    LET_ELIM_TAC>>fs[]>>
    fs[evaluate_def,get_var_perm]>>
    FULL_CASE_TAC>>Cases_on`x`>>fs[alloc_def]>>
    FULL_CASE_TAC>>fs[]>>
    Q.SPECL_THEN [`st`,`ssa`,`na+2`,`ls`,`cst`] mp_tac list_next_var_rename_move_preserve>>
    discharge_hyps_keep>-
      (rw[]
      >-
        (match_mp_tac ssa_locals_rel_more>>
        fs[]>>DECIDE_TAC)
      >-
        (fs[cut_env_def,Abbr`ls`]>>
        metis_tac[SUBSET_DEF,toAList_domain])
      >-
        fs[Abbr`ls`,ALL_DISTINCT_MAP_FST_toAList]
      >-
        (match_mp_tac ssa_map_ok_more>>
        fs[]>>DECIDE_TAC))>>
    LET_ELIM_TAC>>
    qpat_assum`A=A0` sym_sub_tac>>
    fs[Abbr`prog`,evaluate_def,LET_THM]>>
    rw[]>>rfs[Abbr`num'`]>>fs[]>>
    imp_res_tac ssa_locals_rel_get_var>>
    fs[alloc_def]>>
    qabbrev_tac`f = option_lookup ssa'`>>
    Q.ISPECL_THEN [`ls`,`ssa`,`na+2`,`mov`,`ssa'`,`na'`] assume_tac list_next_var_rename_move_props>>
    `is_stack_var (na+2)` by fs[is_alloc_var_flip]>>
    rfs[]>>
    fs[get_vars_def,get_var_def,set_vars_def,alist_insert_def]>>
    qpat_abbrev_tac `rcstlocs = insert 2 A rcst.locals`>>
    (*Try to use cut_env_lemma from word_live*)
    Q.ISPECL_THEN [`s`,`st.locals`,`rcstlocs`,`x`
                  ,`f` ] mp_tac cut_env_lemma>>
    discharge_hyps>-
      (rfs[Abbr`f`]>>
      fs[ssa_locals_rel_def,strong_locals_rel_def]>>
      rw[INJ_DEF]>-
        (SPOSE_NOT_THEN assume_tac>>
        `x' ∈ domain st.locals ∧ y ∈ domain st.locals` by
          fs[SUBSET_DEF,cut_env_def]>>
        fs[domain_lookup,option_lookup_def,ssa_map_ok_def]>>
        res_tac>>
        fs[]>>
        metis_tac[])
      >>
        fs[option_lookup_def,domain_lookup,Abbr`rcstlocs`,lookup_insert]>>
        last_x_assum kall_tac>>
        res_tac>>
        fs[ssa_map_ok_def]>>
        first_x_assum(qspecl_then [`n'`,`v'`] mp_tac)>>
        simp[]>>
        qpat_assum`A=SOME v'` SUBST_ALL_TAC>>fs[]>>
        rw[is_phy_var_def])
    >>
    rw[]>>fs[set_store_def]>>
    qpat_abbrev_tac`non = NONE`>>
    Q.ISPECL_THEN [`y`,`x`,`st with store:= st.store |+ (AllocSize,Word c)`
    ,`f`,`rcst with store:= rcst.store |+ (AllocSize,Word c)`
    ,`non`,`non`,`rcst.permute`] assume_tac (GEN_ALL push_env_s_val_eq)>>
    rfs[word_state_eq_rel_def,Abbr`non`]>>
    qexists_tac`perm`>>fs[]>>
    qpat_abbrev_tac `st' = push_env x NONE A`>>
    qpat_abbrev_tac `cst' = push_env y NONE B`>>
    Cases_on`gc st'`>>fs[]>>
    Q.ISPECL_THEN [`st'`,`cst'`,`x'`] mp_tac gc_s_val_eq_gen>>
    discharge_hyps_keep>-
      (unabbrev_all_tac>>
      fs[push_env_def,LET_THM,env_to_list_def,word_state_eq_rel_def]>>
      rfs[])
    >>
    rw[]>>simp[]>>
    unabbrev_all_tac>>
    imp_res_tac gc_frame>>
    Cases_on`pop_env x'`>>rfs[]>>fs[]>>
    imp_res_tac push_env_pop_env_s_key_eq>>
    rfs[]>>fs[]>>
    imp_res_tac gc_s_key_eq>>
    fs[push_env_def,LET_THM,env_to_list_def]>>
    rpt (qpat_assum `s_key_eq A B` mp_tac)>>
    qpat_abbrev_tac `lsA = list_rearrange (rcst.permute 0)
        (QSORT key_val_compare ( (toAList y)))`>>
    qpat_abbrev_tac `lsB = list_rearrange (perm 0)
        (QSORT key_val_compare ( (toAList x)))`>>
    ntac 4 strip_tac>>
    Q.ISPECL_THEN [`x'.stack`,`y'`,`t'`,`NONE:(num#num#num) option`
        ,`lsA`,`rcst.stack`] mp_tac (GEN_ALL s_key_eq_val_eq_pop_env)>>
      discharge_hyps
    >-
      (fs[]>>metis_tac[s_key_eq_sym,s_val_eq_sym])
    >>
    strip_tac>>fs[]>>
    Q.ISPECL_THEN [`t'.stack`,`x''`,`x'`,`NONE:(num#num#num) option`
      ,`lsB`,`st.stack`] mp_tac (GEN_ALL s_key_eq_val_eq_pop_env)>>
      discharge_hyps
    >-
      (fs[]>>metis_tac[s_key_eq_sym,s_val_eq_sym])
    >>
    rw[]>>
    `LENGTH ls' = LENGTH l ∧ LENGTH lsB = LENGTH l` by
      metis_tac[s_key_eq_def,s_frame_key_eq_def,
                s_val_eq_def,LENGTH_MAP,s_frame_val_eq_def]>>
    (*Establish invariants about ssa_cut to use later*)
    qabbrev_tac `ssa_cut = inter ssa' s` >>
    `domain ssa_cut = domain x` by
      (fs[EXTENSION,Abbr`ssa_cut`,domain_inter]>>
      rw[EQ_IMP_THM]>>
      fs[cut_env_def,SUBSET_DEF]>>
      res_tac>>
      fs[ssa_locals_rel_def]>>
      metis_tac[domain_lookup])>>
    `∀x y. lookup x ssa_cut = SOME y ⇒ lookup x ssa' = SOME y` by
      (rw[]>>fs[Abbr`ssa_cut`,lookup_inter]>>
      Cases_on`lookup x''' ssa'`>>Cases_on`lookup x''' s`>>fs[])>>
   `domain x''.locals = domain x` by
     (fs[domain_fromAList,MAP_ZIP]>>
     fs[EXTENSION,Abbr`lsB`]>>
     fs[MEM_MAP,mem_list_rearrange,QSORT_MEM]>>
     rw[]>>
     fs[EXISTS_PROD,MEM_toAList,domain_lookup])>>
    last_x_assum kall_tac>>
    `ssa_locals_rel na' ssa_cut x''.locals y'.locals ∧
        word_state_eq_rel x'' y'` by
       (fs[state_component_equality]>>
       fs[LET_THM,ssa_locals_rel_def]>>
       rw[]
       >-
         (qpat_assum`A=domain(fromAList l)` sym_sub_tac>>
         fs[option_lookup_def]>>
         res_tac>>fs[]>>
         qexists_tac`x'''`>>fs[]>>
         metis_tac[domain_lookup])
       >-
         metis_tac[domain_lookup]
       >-
         (`x''' ∈ domain x` by metis_tac[domain_lookup]>>
         qpat_assum`A = fromAList l` sym_sub_tac>>
         fs[lookup_fromAList,s_key_eq_def,s_frame_key_eq_def
           ,s_val_eq_def,s_frame_val_eq_def]>>
         qpat_assum`A = MAP FST l` sym_sub_tac>>
         qabbrev_tac`f = option_lookup ssa'`>>
         `MAP FST (MAP (λ(x,y). (f x,y)) lsB) =
          MAP f (MAP FST lsB)` by
           fs[MAP_MAP_o,MAP_EQ_f,FORALL_PROD]>>
         fs[]>>
         `THE (lookup x''' ssa_cut) = f x'''` by
           (fs[Abbr`f`,option_lookup_def]>>
           `x''' ∈ domain ssa_cut` by metis_tac[]>>
           fs[domain_lookup]>>res_tac>>
           fs[])>>
         simp[]>>
         match_mp_tac ALOOKUP_key_remap_2>>rw[]>>
         metis_tac[])
       >-
         (`x''' ∈ domain s` by metis_tac[domain_lookup]>>
         fs[every_var_def,every_name_def,EVERY_MEM,toAList_domain]>>res_tac>>
         DECIDE_TAC)
       >-
         (fs[word_state_eq_rel_def,pop_env_def]>>
         rfs[state_component_equality]>>
         metis_tac[s_val_and_key_eq,s_key_eq_sym
           ,s_val_eq_sym,s_key_eq_trans]))
       >>
    ntac 2 (qpat_assum `A = (B,C)` mp_tac)>>
    FULL_CASE_TAC>>fs[word_state_eq_rel_def,has_space_def]>>
    Cases_on`x'''`>>fs[]>>
    Cases_on`FLOOKUP x''.store NextFree`>>fs[]>>
    Cases_on`x'''`>>fs[] >>
    Cases_on`FLOOKUP x''.store EndOfHeap`>>fs[]>>
    Cases_on`x'''`>>fs[] >>
    IF_CASES_TAC >> fs[] >>
    ntac 2 strip_tac>> rveq >> fs[call_env_def] >-
    (Q.SPECL_THEN [`rst`,`inter ssa' s`,`na'+2`,`(MAP FST (toAList s))`
                 ,`y'`] mp_tac list_next_var_rename_move_preserve>>
    discharge_hyps>-
    (rw[]
    >-
      (rfs[]>>
      match_mp_tac (GEN_ALL ssa_locals_rel_more)>>
      fs[]>>
      qpat_assum `A = fromAList _` sym_sub_tac>>
      HINT_EXISTS_TAC>>fs[])
    >-
      (rw[SUBSET_DEF]>>
      fs[MEM_MAP]>>Cases_on`y''`>>fs[MEM_toAList,domain_lookup])
    >-
      (unabbrev_all_tac>>match_mp_tac ssa_map_ok_inter>>
      match_mp_tac (GEN_ALL ssa_map_ok_more)>>
      HINT_EXISTS_TAC>>
      fs[]>>DECIDE_TAC)
    >>
      fs[word_state_eq_rel_def])>>
    simp[] >>
    rw[]>>fs[word_state_eq_rel_def]) >>
    fs[word_state_eq_rel_def] >> rw[])
  >-
    (*Raise*)
    (exists_tac>>fs[get_var_perm]>>
    Cases_on`get_var n st`>>imp_res_tac ssa_locals_rel_get_var>>
    fs[get_vars_def,get_var_def,set_vars_def,lookup_alist_insert]>>
    fs[jump_exc_def]>>EVERY_CASE_TAC>>fs[])
  >-
    (*Return*)
    (exists_tac>>fs[get_var_perm]>>
    Cases_on`get_var n st`>>
    Cases_on`get_var n0 st`>>
    imp_res_tac ssa_locals_rel_get_var>>fs []>>
    Cases_on `x`>>fs []>>
    fs[get_vars_def,set_vars_def]>>
    imp_res_tac ssa_locals_rel_ignore_list_insert>>
    ntac 4 (pop_assum kall_tac)>>
    pop_assum(qspecl_then [`[x']`,`[2]`] mp_tac)>>
    discharge_hyps>-fs[]>>
    discharge_hyps>- is_phy_var_tac>>
    rw[]>>fs[alist_insert_def]>>
    assume_tac (INST_TYPE [gamma|->beta] (GEN_ALL ssa_locals_rel_get_var))>>
    qpat_abbrev_tac`rcst=cst with locals:=A`>>
    qcase_tac `get_var _ cst = SOME (Loc l1 l2)`>>
    first_assum(qspecl_then[`Loc l1 l2`,`st`,`ssa`,`na`,`n`,`rcst`] assume_tac)>>
    first_x_assum(qspecl_then[`x'`,`st`,`ssa`,`na`,`n0`,`rcst`] assume_tac)>>
    unabbrev_all_tac>>rfs[]>>
    fs[get_var_def,call_env_def])
  >- (* Tick *)
    (exists_tac>>
    EVERY_CASE_TAC>>fs[call_env_def,dec_clock_def])
  >>
    (*FFI*)
    exists_tac>>
    last_x_assum kall_tac>>
    qabbrev_tac`A = ssa_cc_trans (FFI n n0 n1 s) ssa na`>>
    PairCases_on`A`>>fs[ssa_cc_trans_def]>>
    pop_assum mp_tac>>
    LET_ELIM_TAC>>fs[]>>
    fs[evaluate_def,get_var_perm]>>
    Cases_on`get_var n0 st`>>fs[]>>
    Cases_on`x`>>fs[]>>
    Cases_on`get_var n1 st`>>fs[]>>
    Cases_on`x`>>fs[]>>
    Cases_on`cut_env s st.locals`>>fs[]>>
    FULL_CASE_TAC>>fs[LET_THM]>>
    Cases_on`call_FFI st.ffi n x'`>>fs[]>>
    Q.SPECL_THEN [`st`,`ssa`,`na+2`,`ls`,`cst`] mp_tac list_next_var_rename_move_preserve>>
    discharge_hyps_keep>-
      (rw[word_state_eq_rel_def]
      >-
        (match_mp_tac ssa_locals_rel_more>>
        fs[]>>DECIDE_TAC)
      >-
        (fs[cut_env_def,Abbr`ls`]>>
        metis_tac[SUBSET_DEF,toAList_domain])
      >-
        fs[Abbr`ls`,ALL_DISTINCT_MAP_FST_toAList]
      >-
        (match_mp_tac ssa_map_ok_more>>
        fs[]>>DECIDE_TAC))>>
    LET_ELIM_TAC>>
    qpat_assum`A=A0` sym_sub_tac>>
    fs[Abbr`prog`,evaluate_def,LET_THM]>>
    rw[]>>
    `get_vars [cptr;clen] rcst = SOME [Word c;Word c']` by
      (unabbrev_all_tac>>fs[get_vars_def]>>
      imp_res_tac ssa_locals_rel_get_var>>fs[get_var_def])>>
    qabbrev_tac`f = option_lookup ssa'`>>
    Q.ISPECL_THEN [`ls`,`ssa`,`na+2`,`mov`,`ssa'`,`na'`] assume_tac list_next_var_rename_move_props>>
    `is_stack_var (na+2)` by fs[is_alloc_var_flip]>>
    rfs[]>>fs[set_vars_def,alist_insert_def]>>
    qpat_abbrev_tac `rcstlocs = insert 2 A (insert 4 B rcst.locals)`>>
    fs[get_var_def]>>
    `lookup 2 rcstlocs = SOME (Word c) ∧
     lookup 4 rcstlocs = SOME (Word c')` by
      fs[Abbr`rcstlocs`,lookup_insert]>>
    fs[]>>
    Q.ISPECL_THEN [`s`,`st.locals`,`rcstlocs`,`x`
                  ,`f` ] mp_tac cut_env_lemma>>
    discharge_hyps>-
      (rfs[Abbr`f`]>>
      fs[ssa_locals_rel_def,strong_locals_rel_def]>>
      rw[INJ_DEF]>-
        (SPOSE_NOT_THEN assume_tac>>
        `x'' ∈ domain st.locals ∧ y ∈ domain st.locals` by
          fs[SUBSET_DEF,cut_env_def]>>
        fs[domain_lookup,option_lookup_def,ssa_map_ok_def]>>
        res_tac>>
        fs[]>>
        metis_tac[])
      >>
        fs[option_lookup_def,domain_lookup,Abbr`rcstlocs`,lookup_insert]>>
        res_tac>>
        fs[ssa_map_ok_def]>>
        first_x_assum(qspecl_then [`n'`,`v'`] mp_tac)>>
        simp[]>>
        qpat_assum`A=SOME v'` SUBST_ALL_TAC>>fs[]>>
        rw[is_phy_var_def])>>
    rw[]>>
    fs[word_state_eq_rel_def]>>
    qpat_abbrev_tac`mem = write_bytearray A B C D E`>>
    qabbrev_tac`rst = st with <|locals := x;memory:=mem;ffi:=q|>`>>
    qpat_abbrev_tac`rcstt = rcst with <|locals := A;memory:=B;ffi:=D|>`>>
    `domain ssa_cut = domain x` by
      (fs[EXTENSION,Abbr`ssa_cut`,domain_inter]>>
      rw[EQ_IMP_THM]>>
      fs[cut_env_def,SUBSET_DEF]>>
      res_tac>>
      fs[ssa_locals_rel_def]>>
      metis_tac[domain_lookup])>>
    `∀x y. lookup x ssa_cut = SOME y ⇒ lookup x ssa' = SOME y` by
      (rw[]>>fs[Abbr`ssa_cut`,lookup_inter]>>
      Cases_on`lookup x'' ssa'`>>Cases_on`lookup x'' s`>>fs[])>>
   `domain rst.locals = domain x` by
     fs[Abbr`rst`]>>
   `ssa_locals_rel na' ssa_cut rst.locals rcstt.locals ∧
       word_state_eq_rel rst rcstt` by
      (fs[Abbr`rst`,Abbr`rcstt`,state_component_equality
      ,word_state_eq_rel_def,ssa_locals_rel_def]>>
      rw[]
      >-
        (qexists_tac`x''`>>unabbrev_all_tac>>
        fs[option_lookup_def,lookup_inter]>>
        pop_assum mp_tac >>EVERY_CASE_TAC>>fs[domain_lookup])
      >-
        metis_tac[domain_lookup]
      >-
        (`THE (lookup x'' ssa_cut) = f x''` by
          (fs[Abbr`f`,option_lookup_def]>>
          `x'' ∈ domain ssa_cut` by metis_tac[domain_lookup]>>
          fs[domain_lookup]>>res_tac>>
          fs[])>>
        fs[strong_locals_rel_def]>>
        metis_tac[domain_lookup])
      >-
        (`x'' ∈ domain s` by metis_tac[domain_lookup]>>
        fs[every_var_def,every_name_def,EVERY_MEM,toAList_domain]>>res_tac>>
        DECIDE_TAC))>>
    Q.SPECL_THEN [`rst`,`inter ssa' s`,`na'+2`,`(MAP FST (toAList s))`
                   ,`rcstt`] mp_tac list_next_var_rename_move_preserve>>
      discharge_hyps>-
      (rw[]
      >-
        (unabbrev_all_tac>>rfs[]>>
        match_mp_tac (GEN_ALL ssa_locals_rel_more)>>
        fs[]>>
        HINT_EXISTS_TAC>>fs[])
      >-
        (rw[SUBSET_DEF,Abbr`ls`]>>
        fs[MEM_MAP]>>Cases_on`y'`>>fs[MEM_toAList,domain_lookup])
      >-
        (unabbrev_all_tac>>match_mp_tac ssa_map_ok_inter>>
        match_mp_tac (GEN_ALL ssa_map_ok_more)>>
        HINT_EXISTS_TAC>>
        fs[]>>DECIDE_TAC))>>
      fs[LET_THM]>>
      rw[]>>
      Cases_on`evaluate(ret_mov,rcstt)`>>unabbrev_all_tac>>fs[state_component_equality,word_state_eq_rel_def])

(*DONE main correctness proofs*)

val get_vars_eq = prove(
  ``(set ls) SUBSET domain st.locals ==> ?y. get_vars ls st = SOME y /\
                                             y = MAP (\x. THE (lookup x st.locals)) ls``,
  Induct_on`ls`>>fs[get_vars_def,get_var_def]>>rw[]>>
  fs[domain_lookup])

(*For starting up*)
val setup_ssa_props = prove(``
  is_alloc_var lim ∧
  domain st.locals = set (even_list n) ⇒
  let (mov:'a wordLang$prog,ssa,na) = setup_ssa n lim (prog:'a wordLang$prog) in
  let (res,cst) = evaluate(mov,st) in
    res = NONE ∧
    word_state_eq_rel st cst ∧
    ssa_map_ok na ssa ∧
    ssa_locals_rel na ssa st.locals cst.locals ∧
    is_alloc_var na ∧
    lim ≤ na``,
  rw[setup_ssa_def,list_next_var_rename_move_def]>>
  fs[word_state_eq_rel_def,evaluate_def]>>
  imp_res_tac list_next_var_rename_lemma_1>>
  fs[LET_THM,MAP_ZIP,LENGTH_COUNT_LIST]>>
  fs[ALL_DISTINCT_MAP]>>
  `set args ⊆ domain st.locals` by fs[]>>
  imp_res_tac get_vars_eq>>
  `MAP (option_lookup LN) args = args` by
    fs[MAP_EQ_ID,option_lookup_def,lookup_def]>>
  fs[set_vars_def,state_component_equality]
  >>
    TRY(`ssa_map_ok lim LN` by
      fs[ssa_map_ok_def,lookup_def]>>
    imp_res_tac list_next_var_rename_props>>NO_TAC)>>
  fs[ssa_locals_rel_def]>>
  `ALL_DISTINCT args` by
    (unabbrev_all_tac>>
    fs[even_list_def,ALL_DISTINCT_GENLIST]>>rw[]>>
    DECIDE_TAC)>>
  imp_res_tac list_next_var_rename_lemma_2>>
  pop_assum kall_tac>>
  pop_assum(qspecl_then [`LN`,`lim`] mp_tac)>>
  LET_ELIM_TAC>>fs[]>>rfs[]
  >-
    (qpat_assum`A=cst.locals` (sym_sub_tac)>>
    fs[domain_alist_insert,LENGTH_COUNT_LIST]>>
    `x ∈ domain ssa` by fs[domain_lookup]>>
    qpat_assum `MAP f args = B` (sym_sub_tac)>>
    DISJ2_TAC>>
    fs[MEM_MAP]>>
    qexists_tac`x`>>
    `x ∈ domain ssa` by fs[domain_lookup]>>
    fs[]>>metis_tac[EXTENSION])
  >-
    (`x ∈ domain st.locals` by fs[domain_lookup]>>
    metis_tac[EXTENSION])
  >-
    (qpat_assum`A=cst.locals` (sym_sub_tac)>>
    fs[lookup_alist_insert,LENGTH_COUNT_LIST]>>
    fs[ALOOKUP_ALL_DISTINCT_EL]>>
    use_ALOOKUP_ALL_DISTINCT_MEM >>
    fs[MAP_ZIP,LENGTH_COUNT_LIST]>>
    strip_tac>>
    pop_assum(qspec_then `y'` mp_tac)>>discharge_hyps
    >-
      (fs[MEM_ZIP,LENGTH_COUNT_LIST]>>
      `x ∈ set args` by metis_tac[domain_lookup]>>
      fs[MEM_EL]>>HINT_EXISTS_TAC>>fs[EL_MAP]>>
      fs[LIST_EQ_REWRITE]>>last_x_assum(qspec_then`n''` assume_tac)>>
      rfs[]>>
      rfs[EL_MAP,LENGTH_COUNT_LIST])
    >>
    fs[])
  >>
    `x ∈ domain st.locals` by fs[domain_lookup]>>
    `MEM x args` by metis_tac[EXTENSION]>>
    fs[Abbr`args`]>>
    fs[even_list_def,MEM_GENLIST]>>
    `is_phy_var x` by is_phy_var_tac>>
    metis_tac[convention_partitions])

val max_var_exp_max = prove(``
  ∀exp.
    every_var_exp (λx. x≤ max_var_exp exp) exp``,
  ho_match_mp_tac max_var_exp_ind>>
  rw[every_var_exp_def,max_var_exp_def]>>
  fs[EVERY_MEM]>>rw[]>>res_tac>>
  match_mp_tac every_var_exp_mono>>
  HINT_EXISTS_TAC>>rw[]>>
  qpat_abbrev_tac`ls':(num list) = MAP f ls`>>
  Q.ISPECL_THEN [`ls'`] assume_tac list_max_max>>
  fs[EVERY_MEM,Abbr`ls'`,MEM_MAP,PULL_EXISTS]>>
  pop_assum(qspec_then`a` assume_tac)>>rfs[]>>
  DECIDE_TAC)

val max_var_inst_max = prove(``
  ∀inst.
    every_var_inst (λx. x ≤ max_var_inst inst) inst``,
  ho_match_mp_tac max_var_inst_ind>>
  rw[every_var_inst_def,max_var_inst_def]>>
  TRY(Cases_on`ri`)>>fs[every_var_imm_def]>>
  TRY(IF_CASES_TAC)>>fs[]>>
  DECIDE_TAC)

val max_var_max = store_thm("max_var_max",``
  ∀prog.
    every_var (λx. x ≤ max_var prog) prog``,
  ho_match_mp_tac max_var_ind>>
  rw[every_var_def,max_var_def]>>
  TRY(Cases_on`ri`)>>fs[every_var_imm_def]>>
  rpt IF_CASES_TAC>>fs[]>>
  rw[]>>TRY(fs[Abbr`r`])>>
  TRY(DECIDE_TAC)>>
  TRY
  (Q.ISPECL_THEN [`MAP FST ls ++ MAP SND ls`] assume_tac list_max_max>>
  rfs[])
  >- metis_tac[max_var_inst_max]>>
  TRY
    (match_mp_tac every_var_exp_mono>>
    qexists_tac`λx. x ≤ max_var_exp exp`>>
    fs[max_var_exp_max]>>
    DECIDE_TAC)
  >-
    (fs[LET_THM,EVERY_MEM,MAX_DEF]>>rw[]>>
    EVERY_CASE_TAC>>unabbrev_all_tac>>fs[]>>
    `x ≤ list_max args` by
       (Q.ISPECL_THEN [`args`] assume_tac list_max_max>>
       fs[EVERY_MEM])>>
    TRY(DECIDE_TAC))
  >-
    (EVERY_CASE_TAC>>fs[every_name_def,EVERY_MEM,toAList_domain,MAX_DEF]>>
    LET_ELIM_TAC>>
    qcase_tac`toAList tree`>>
    TRY(
    `∀z. z ∈ domain tree ⇒ z ≤ cutset_max` by
      (rw[]>>
      Q.ISPECL_THEN [`MAP FST(toAList tree)`] assume_tac list_max_max>>
      fs[Abbr`cutset_max`,EVERY_MEM,MEM_MAP,PULL_EXISTS
        ,FORALL_PROD,MEM_toAList,domain_lookup]>>
      res_tac>>DECIDE_TAC)>>res_tac)>>
    TRY(match_mp_tac every_var_mono>>
    TRY(HINT_EXISTS_TAC)>>
    TRY(qexists_tac`λx.x ≤ max_var q''''`>>fs[]))>>
    fs[every_name_def]>>
    unabbrev_all_tac>>EVERY_CASE_TAC>>fs[]>>DECIDE_TAC)
  >>
    TRY(match_mp_tac every_var_mono>>
    TRY(HINT_EXISTS_TAC)>>TRY(qexists_tac`λx. x ≤ max_var prog`)>>
    rw[]>>
    DECIDE_TAC)
  >>
    qabbrev_tac`ls' = MAP FST (toAList numset)`>>
    Q.ISPECL_THEN [`ls'`] assume_tac list_max_max>>
    fs[every_name_def,Abbr`ls'`,EVERY_MEM,MEM_MAP,PULL_EXISTS,FORALL_PROD,MEM_toAList,domain_lookup,MAX_DEF]>>rw[]>>
    res_tac>>DECIDE_TAC)

val limit_var_props = prove(``
  limit_var prog = lim ⇒
  is_alloc_var lim ∧
  every_var (λx. x< lim) prog``,
  reverse (rw[limit_var_def,is_alloc_var_def])
  >-
    (qspec_then `prog` assume_tac max_var_max >>
    match_mp_tac every_var_mono>>
    HINT_EXISTS_TAC>>
    rw[]>>
    fs[Abbr`x'`]>>
    DECIDE_TAC)
  >>
  qspec_then `4` assume_tac arithmeticTheory.MOD_PLUS>>
  `(x + (4 - x MOD 4)) MOD 4 = 0` by
   (`x MOD 4 < 4` by fs[]>>
    `(x MOD 4 = 0) ∨ (x MOD 4 = 1) ∨ (x MOD 4 = 2) ∨ (x MOD 4 = 3)` by
      DECIDE_TAC>>
    fs[]>>
    (*Fastest way I could find*)
    `(0 MOD 4 = 0) ∧
    (1 MOD 4 = 1) ∧
    (2 MOD 4 = 2) ∧
    (3 MOD 4 = 3) ∧
    (4 MOD 4 = 0)` by fs[]>>
    `((0+0)MOD 4 = 0) ∧
    ((1+3)MOD 4 = 0) ∧
    ((2+2)MOD 4 = 0) ∧
    ((3+1)MOD 4 = 0)` by fs[]>>
    metis_tac[])>>
  fs[]>>
  first_x_assum(qspecl_then [`x+(4- x MOD 4)`,`1`] assume_tac)>>
  pop_assum sym_sub_tac>>
  fs[])

(*Full correctness theorem*)
val full_ssa_cc_trans_correct = store_thm("full_ssa_cc_trans_correct",
``∀prog st n.
  domain st.locals = set (even_list n) ⇒
  ∃perm'.
  let (res,rst) = evaluate(prog,st with permute:=perm') in
  if (res = SOME Error) then T else
  let (res',rcst) = evaluate(full_ssa_cc_trans n prog,st) in
    res = res' ∧
    word_state_eq_rel rst rcst ∧
    (case res of
      NONE => T
    | SOME _    => rst.locals = rcst.locals )``,
  rw[]>>
  qpat_abbrev_tac`sprog = full_ssa_cc_trans n prog`>>
  fs[full_ssa_cc_trans_def]>>
  pop_assum mp_tac>>LET_ELIM_TAC>>
  assume_tac limit_var_props>>
  pop_assum mp_tac>> discharge_hyps>- metis_tac[]>>
  rw[]>>
  imp_res_tac setup_ssa_props>>
  pop_assum(qspec_then`prog` mp_tac)>>
  LET_ELIM_TAC>>
  simp[Abbr`sprog`,Once evaluate_def]>>
  rfs[]>>
  Q.ISPECL_THEN [`prog`,`st`,`cst`,`ssa`,`na`] mp_tac ssa_cc_trans_correct>>
  discharge_hyps>-
    (fs[]>>match_mp_tac every_var_mono>>HINT_EXISTS_TAC >>
    rw[]>>DECIDE_TAC)>>
  rw[]>>
  qexists_tac`perm'`>>rw[]>>
  fs[LET_THM]>>
  FULL_CASE_TAC>>fs[]);

(*Prove that the ssa form sets up conventions*)

val fake_moves_conventions = prove(``
  ∀ls ssaL ssaR na.
  let (a,b,c,d,e) = fake_moves ls ssaL ssaR na in
  every_stack_var is_stack_var a ∧
  every_stack_var is_stack_var b ∧
  call_arg_convention a ∧
  call_arg_convention b``,
  Induct>>fs[fake_moves_def]>>
  LET_ELIM_TAC>>
  TRY(first_x_assum (assume_tac o SYM)>>
  fs[call_arg_convention_def,every_stack_var_def,fake_moves_def]>>NO_TAC)>>
  EVERY_CASE_TAC>>
  first_x_assum(qspecl_then[`ssaL`,`ssaR`,`na`] mp_tac)>>LET_ELIM_TAC>>
  fs[LET_THM,fake_move_def]>>rpt VAR_EQ_TAC>>
  fs[call_arg_convention_def,every_stack_var_def,fake_moves_def])

val fix_inconsistencies_conventions = prove(``
  ∀ssaL ssaR na.
  let (a:'a wordLang$prog,b:'a wordLang$prog,c,d) =
    fix_inconsistencies ssaL ssaR na in
  every_stack_var is_stack_var a ∧
  every_stack_var is_stack_var b ∧
  call_arg_convention a ∧
  call_arg_convention b``,
  fs[fix_inconsistencies_def,call_arg_convention_def,every_stack_var_def,UNCURRY]>>
  rpt strip_tac>>
  rw[]>>unabbrev_all_tac>>
  fs[every_stack_var_def,call_arg_convention_def]>>
  qabbrev_tac `ls = MAP FST (toAList (union ssaL ssaR))` >>
  Q.SPECL_THEN [`ls`,`ssa_L'`,`ssa_R'`,`na'`]
    assume_tac fake_moves_conventions>>rfs[LET_THM])

(*Prove that the transform sets up arbitrary programs with
  the appropriate conventions*)
val ssa_cc_trans_pre_alloc_conventions = store_thm("ssa_cc_trans_pre_alloc_conventions",
``∀prog ssa na.
  is_alloc_var na ∧
  ssa_map_ok na ssa ⇒
  let (prog',ssa',na') = ssa_cc_trans prog ssa na in
  pre_alloc_conventions prog'``,
  completeInduct_on`wordLang$prog_size (K 0) prog`>>
  rpt strip_tac>>
  fs[PULL_FORALL,LET_THM]>>
  Cases_on`prog`>>
  TRY(fs[ssa_cc_trans_def,pre_alloc_conventions_def,every_stack_var_def,call_arg_convention_def,LET_THM,UNCURRY]>>rw[]>>NO_TAC)>>
  fs[ssa_cc_trans_def,pre_alloc_conventions_def]>>rw[]>>
  fs[call_arg_convention_def,every_stack_var_def]
  >-
  (Cases_on`o'`
  >-
    (fs[ssa_cc_trans_def]>>LET_ELIM_TAC>>
    unabbrev_all_tac>>
    fs[every_stack_var_def,call_arg_convention_def])
  >>
  PairCases_on`x`>>Cases_on`o0`>>TRY(PairCases_on`x`)>>
  fs[ssa_cc_trans_def]>>LET_ELIM_TAC>>
  `∀x. x ∈ domain stack_set ⇒ is_stack_var x` by
  (unabbrev_all_tac>>
  rpt (rator_x_assum `list_next_var_rename_move` mp_tac)>>
  fs[domain_fromAList,MAP_ZIP,list_next_var_rename_move_def]>>
  LET_ELIM_TAC>>
  `ALL_DISTINCT (MAP FST (toAList x1))` by fs[ALL_DISTINCT_MAP_FST_toAList]>>
  imp_res_tac list_next_var_rename_lemma_2>>
  pop_assum(qspecl_then [`ssa`,`na+2`] assume_tac)>>
  imp_res_tac list_next_var_rename_lemma_1>>rfs[LET_THM]>>
  fs[MAP_MAP_o]>>
  `MEM x new_ls'` by
    (`MAP (option_lookup ssa' o FST) (toAList x1) = new_ls'` by
    (qpat_assum`new_ls' = A` sym_sub_tac>>
    qpat_assum`A=new_ls'` sym_sub_tac>>
    fs[MAP_EQ_f,option_lookup_def]>>rw[]>>
    `FST e ∈  domain ssa'` by
      (Cases_on`e`>>
      fs[EXISTS_PROD,MEM_MAP])>>
    fs[domain_lookup])>>
    pop_assum sym_sub_tac>>
    fs[MEM_MAP,EXISTS_PROD]>>
    metis_tac[])>>
  rfs[MEM_MAP,is_stack_var_def]>>
  qspec_then `4` mp_tac arithmeticTheory.MOD_PLUS >>
  discharge_hyps>-simp[]>>
  disch_then(qspecl_then[`4*x'`,`na+2`](SUBST1_TAC o SYM)) >>
  `(4*x') MOD 4 =0 ` by
    (`0<4:num` by DECIDE_TAC>>
        `∀k.(4:num)*k=k*4` by DECIDE_TAC>>
        metis_tac[arithmeticTheory.MOD_EQ_0])>>
  `is_stack_var (na+2)` by metis_tac[is_alloc_var_flip]>>
  fs[is_stack_var_def])>>
  unabbrev_all_tac>>fs[]>>
  imp_res_tac list_next_var_rename_move_props_2>>
  rfs[ssa_map_ok_inter]>>
  first_assum(qspecl_then[`x2`,`ssa_2_p`,`na_2_p`] mp_tac)>>
  size_tac>>
  (discharge_hyps_keep>-
    (fs[next_var_rename_def]>>
     metis_tac[is_alloc_var_add,ssa_map_ok_extend,convention_partitions]))>>
  TRY(
  strip_tac>>
  imp_res_tac ssa_cc_trans_props>>fs[]>>
  first_x_assum(qspecl_then[`x1'`,`ssa_3_p`,`na_3_p`] mp_tac)>>
  size_tac>>
  discharge_hyps>-
  (fs[next_var_rename_def]>>
   rw[]>-
      metis_tac[is_alloc_var_add]
   >-
    (match_mp_tac ssa_map_ok_extend>>
    rw[]>-
      (match_mp_tac (GEN_ALL ssa_map_ok_more)>>
      qexists_tac`na''`>>
      rfs[]>>
      DECIDE_TAC)>>
    rfs[]>>metis_tac[convention_partitions])))>>
  rpt (rator_x_assum `list_next_var_rename_move` mp_tac)>>
  fs[list_next_var_rename_move_def]>>LET_ELIM_TAC>>
  fs[EQ_SYM_EQ]>>rw[]>>
  fs[every_stack_var_def,call_arg_convention_def]>>
  fs[every_name_def,toAList_domain,EVERY_MEM]>>
  rfs[]>>
  TRY(Q.ISPECL_THEN [`ssa_2`,`ssa_3`,`na_3`] assume_tac fix_inconsistencies_conventions>>
  rfs[LET_THM]))
  >-
  (*Seq*)
  (first_assum(qspecl_then[`p`,`ssa`,`na`] assume_tac)>>
  first_x_assum(qspecl_then[`p0`,`ssa'`,`na'`] assume_tac)>>
  ntac 2 (pop_assum mp_tac >> size_tac)>>
  rw[]>>metis_tac[ssa_cc_trans_props])
  >-
  (*If*)
  (FULL_CASE_TAC>>fs[]>>
  imp_res_tac ssa_cc_trans_props>>
  first_assum(qspecl_then[`p`,`ssa`,`na`] mp_tac)>>
  (size_tac>>discharge_hyps>-fs[])>>
  strip_tac>>
  first_x_assum(qspecl_then[`p0`,`ssa`,`na2`] mp_tac)>>
  (size_tac>>discharge_hyps>-metis_tac[ssa_map_ok_more])>>
  strip_tac>>
  rfs[]>>
  Q.SPECL_THEN [`ssa2`,`ssa3`,`na3`] assume_tac fix_inconsistencies_conventions>>
  rfs[LET_THM])
  >>
  (*Alloc -- old proof broke for some reason*)
  (fs[Abbr`prog`,list_next_var_rename_move_def]>>
  ntac 2 (qpat_assum `A = (B,C,D)` mp_tac)>>
  LET_ELIM_TAC>>fs[]>>
  qpat_assum`A=stack_mov` sym_sub_tac>>
  qpat_assum`A=ret_mov` sym_sub_tac>>
  fs[every_stack_var_def,is_stack_var_def,call_arg_convention_def]>>
  fs[every_name_def,EVERY_MEM,toAList_domain]>>
  rw[Abbr`stack_set`]>>
  fs[domain_numset_list_insert,EVERY_MEM,domain_fromAList]>>
  fs[MAP_ZIP]>>
  imp_res_tac list_next_var_rename_lemma_1>>
  `ALL_DISTINCT ls` by
    (fs[Abbr`ls`]>>metis_tac[ALL_DISTINCT_MAP_FST_toAList])>>
  imp_res_tac list_next_var_rename_lemma_2>>
  pop_assum(qspecl_then[`ssa`,`na+2`] assume_tac)>>rfs[LET_THM]>>
  qabbrev_tac `lss = MAP (λx. THE(lookup x ssa')) ls`>>
  qabbrev_tac `lss' = MAP (option_lookup ssa' o FST) (toAList s)`>>
  `∀x. MEM x lss' ⇒ MEM x lss` by
    (unabbrev_all_tac>>
    fs[MEM_MAP,EXISTS_PROD]>>rw[]>>
    res_tac>>
    fs[option_lookup_def]>>
    HINT_EXISTS_TAC>>
    fs[])>>
  `MEM e lss'` by
    (unabbrev_all_tac>>
    fs[MEM_MAP,MAP_MAP_o,EXISTS_PROD]>>
    metis_tac[])>>
  res_tac>>
  qpat_assum`A = lss` sym_sub_tac>>
  fs[MEM_MAP]>>
  `is_stack_var (na+2)` by fs[is_alloc_var_flip]>>
  `(4 * x) MOD 4 = 0` by
    (qspec_then `4` assume_tac arithmeticTheory.MOD_EQ_0>>
    fs[]>>pop_assum(qspec_then `x` assume_tac)>>
    DECIDE_TAC)>>
  `(na +2) MOD 4 = 3` by fs[is_stack_var_def]>>
  qspec_then `4` assume_tac arithmeticTheory.MOD_PLUS>>
  pop_assum mp_tac >>discharge_hyps>-
    fs[]>>
  disch_then(qspecl_then [`4*x`,`na+2`] assume_tac)>>
  rfs[is_stack_var_def]))

val setup_ssa_props_2 = prove(``
  is_alloc_var lim ⇒
  let (mov:'a wordLang$prog,ssa,na) = setup_ssa n lim (prog:'a wordLang$prog) in
    ssa_map_ok na ssa ∧
    is_alloc_var na ∧
    pre_alloc_conventions mov ∧
    lim ≤ na``,
  rw[setup_ssa_def,list_next_var_rename_move_def,pre_alloc_conventions_def]>>
  fs[word_state_eq_rel_def,evaluate_def,every_stack_var_def,call_arg_convention_def]>>
  imp_res_tac list_next_var_rename_lemma_1>>
  fs[LET_THM,MAP_ZIP,LENGTH_COUNT_LIST]>>
  fs[ALL_DISTINCT_MAP]>>
  TRY(`ssa_map_ok lim LN` by
    fs[ssa_map_ok_def,lookup_def]>>
  imp_res_tac list_next_var_rename_props>>NO_TAC))

val full_ssa_cc_trans_pre_alloc_conventions = store_thm("full_ssa_cc_trans_pre_alloc_conventions",
``∀n prog.
  pre_alloc_conventions (full_ssa_cc_trans n prog)``,
  fs[full_ssa_cc_trans_def,pre_alloc_conventions_def,list_next_var_rename_move_def]>>LET_ELIM_TAC>>
  fs[Abbr`lim'`]>>
  imp_res_tac limit_var_props>>
  imp_res_tac setup_ssa_props_2>>
  pop_assum(qspecl_then [`prog`,`n`] assume_tac)>>rfs[LET_THM]>>
  imp_res_tac ssa_cc_trans_props>>
  Q.ISPECL_THEN [`prog`,`ssa`,`na`] assume_tac ssa_cc_trans_pre_alloc_conventions>>
  rfs[pre_alloc_conventions_def,every_stack_var_def,call_arg_convention_def,LET_THM])

val colouring_satisfactory_colouring_ok_alt = prove(``
  ∀prog f live hd tl spg.
  get_clash_sets prog live = (hd,tl) ∧
  spg = clash_sets_to_sp_g (hd::tl) ∧
  colouring_satisfactory (f:num->num) spg
  ⇒
  colouring_ok_alt f prog live``,
  rpt strip_tac>>
  fs[LET_THM,colouring_ok_alt_def,colouring_satisfactory_def]>>
  qabbrev_tac `ls = hd::tl`>>
  qsuff_tac `EVERY (λs. INJ f (domain s) UNIV) ls`
  >-
    fs[Abbr`ls`]
  >>
  rw[EVERY_MEM]>>
  imp_res_tac clash_sets_clique>>
  imp_res_tac colouring_satisfactory_cliques>>
  pop_assum(qspec_then`f`mp_tac)>>
  discharge_hyps
  >- fs[colouring_satisfactory_def,LET_THM]>>
  discharge_hyps
  >- fs[ALL_DISTINCT_MAP_FST_toAList]>>
  fs[INJ_DEF]>>rw[]>>
  fs[domain_lookup]>>
  `MEM x (MAP FST (toAList s)) ∧
   MEM y (MAP FST (toAList s))` by
    (fs[MEM_MAP,EXISTS_PROD]>>
    metis_tac[domain_lookup,MEM_MAP,EXISTS_PROD,MEM_toAList])>>
  `ALL_DISTINCT (MAP FST (toAList s))` by
    metis_tac[ALL_DISTINCT_MAP_FST_toAList]>>
  fs[EL_ALL_DISTINCT_EL_EQ]>>
  fs[MEM_EL]>>rfs[EL_MAP]>>
  metis_tac[])

val is_phy_var_tac =
    fs[is_phy_var_def]>>
    `0<2:num` by DECIDE_TAC>>
    `∀k.(2:num)*k=k*2` by DECIDE_TAC>>
    metis_tac[arithmeticTheory.MOD_EQ_0];

val call_arg_convention_preservation = prove(``
  ∀prog f.
  every_var (λx. is_phy_var x ⇒ f x = x) prog ∧
  call_arg_convention prog ⇒
  call_arg_convention (apply_colour f prog)``,
  ho_match_mp_tac call_arg_convention_ind>>
  rw[call_arg_convention_def,every_var_def]>>
  EVERY_CASE_TAC>>unabbrev_all_tac>>
  fs[call_arg_convention_def]>>
  `is_phy_var 2` by is_phy_var_tac>>fs[]>>
  `is_phy_var 4` by is_phy_var_tac>>fs[]>>
  `EVERY is_phy_var args` by
    (qpat_assum`args=A` SUBST_ALL_TAC>>
    fs[EVERY_GENLIST]>>rw[]>>
    is_phy_var_tac)>>
  qpat_assum`args = A` (SUBST_ALL_TAC o SYM)>>
  fs[EVERY_MEM,miscTheory.MAP_EQ_ID]>>
  rfs[])

(*Composing with a function using apply_colour*)
val every_var_inst_apply_colour_inst = store_thm("every_var_inst_apply_colour_inst",``
  ∀P inst Q f.
  every_var_inst P inst ∧
  (∀x. P x ⇒ Q (f x)) ⇒
  every_var_inst Q (apply_colour_inst f inst)``,
  ho_match_mp_tac every_var_inst_ind>>rw[every_var_inst_def]>>
  TRY(Cases_on`ri`>>fs[apply_colour_imm_def])>>
  EVERY_CASE_TAC>>fs[every_var_imm_def])

val every_var_exp_apply_colour_exp = store_thm("every_var_exp_apply_colour_exp",``
  ∀P exp Q f.
  every_var_exp P exp ∧
  (∀x. P x ⇒ Q (f x)) ⇒
  every_var_exp Q (apply_colour_exp f exp)``,
  ho_match_mp_tac every_var_exp_ind>>rw[every_var_exp_def]>>
  fs[EVERY_MAP,EVERY_MEM])

val every_var_apply_colour = store_thm("every_var_apply_colour",``
  ∀P prog Q f.
  every_var P prog ∧
  (∀x. P x ⇒ Q (f x)) ⇒
  every_var Q (apply_colour f prog)``,
  ho_match_mp_tac every_var_ind>>rw[every_var_def]>>
  fs[MAP_ZIP,(GEN_ALL o SYM o SPEC_ALL) MAP_MAP_o]>>
  fs[EVERY_MAP,EVERY_MEM]
  >-
    metis_tac[every_var_inst_apply_colour_inst]
  >-
    metis_tac[every_var_exp_apply_colour_exp]
  >-
    metis_tac[every_var_exp_apply_colour_exp]
  >-
    (fs[every_name_def,EVERY_MEM,toAList_domain]>>
    fs[domain_fromAList,MEM_MAP,ZIP_MAP]>>rw[]>>
    Cases_on`y'`>>fs[MEM_toAList,domain_lookup])
  >-
    (EVERY_CASE_TAC>>unabbrev_all_tac>>fs[every_var_def,EVERY_MAP,EVERY_MEM]>>
    fs[every_name_def,EVERY_MEM,toAList_domain]>>
    rw[]>>fs[domain_fromAList,MEM_MAP,ZIP_MAP]>>
    Cases_on`y'`>>fs[MEM_toAList,domain_lookup])
  >-
    (Cases_on`ri`>>fs[every_var_imm_def])
  >-
    (fs[every_name_def,EVERY_MEM,toAList_domain]>>
    fs[domain_fromAList,MEM_MAP,ZIP_MAP]>>rw[]>>
    Cases_on`y'`>>fs[MEM_toAList,domain_lookup])
  >>
    metis_tac[every_var_exp_apply_colour_exp])

val every_stack_var_apply_colour = store_thm("every_stack_var_apply_colour",``
  ∀P prog Q f.
  every_stack_var P prog ∧
  (∀x. P x ⇒ Q (f x)) ⇒
  every_stack_var Q (apply_colour f prog)``,
  ho_match_mp_tac every_stack_var_ind>>rw[every_stack_var_def]
  >>
  (EVERY_CASE_TAC>>unabbrev_all_tac>>fs[every_stack_var_def,EVERY_MAP,EVERY_MEM]>>
    fs[every_name_def,EVERY_MEM,toAList_domain]>>
    rw[]>>fs[domain_fromAList,MEM_MAP,ZIP_MAP]>>
    Cases_on`y'`>>fs[MEM_toAList,domain_lookup]))

val oracle_colour_ok_conventions = prove(``
  oracle_colour_ok k col_opt ls prog = SOME x ⇒
  post_alloc_conventions k x``,
  fs[oracle_colour_ok_def,LET_THM]>>EVERY_CASE_TAC>>fs[]>>
  metis_tac[])

val pre_post_conventions_word_alloc = prove(``
  ∀alg prog k col_opt.
  pre_alloc_conventions prog ⇒ (*this is generated by ssa form*)
  post_alloc_conventions k (word_alloc alg k prog col_opt)``,
  fs[pre_alloc_conventions_def,post_alloc_conventions_def,word_alloc_def]>>
  rw[]>>
  FULL_CASE_TAC>>fs[]>>
  imp_res_tac oracle_colour_ok_conventions >>fs[post_alloc_conventions_def]>>
  `undir_graph clash_graph` by
    metis_tac[clash_sets_to_sp_g_undir]>>
  imp_res_tac reg_alloc_conventional>>
  pop_assum(qspecl_then[`moves`,`k`,`alg`] assume_tac)>>rfs[LET_THM]>>
  `every_var (in_clash_sets (hd::tl)) prog` by
     (Q.ISPECL_THEN [`prog`,`LN:num_set`] assume_tac
       every_var_in_get_clash_set>>
     rfs[LET_THM])>>
  `every_var (λx. x ∈ domain clash_graph) prog` by
    (match_mp_tac every_var_mono>>
    HINT_EXISTS_TAC>>rw[]>>
    metis_tac[clash_sets_to_sp_g_domain])>>
  fs[colouring_conventional_def,LET_THM]
  >-
    (match_mp_tac every_var_apply_colour>>
    HINT_EXISTS_TAC>>fs[]>>
    rw[]>>
    metis_tac[])
  >-
    (match_mp_tac every_stack_var_apply_colour>>
    imp_res_tac every_var_imp_every_stack_var>>
    qexists_tac `λx. (x ∈ domain clash_graph ∧ is_stack_var x)` >>rw[]
    >-
      metis_tac[every_stack_var_conj]
    >>
    metis_tac[convention_partitions])
  >>
  match_mp_tac call_arg_convention_preservation>>
  rw[]>>match_mp_tac every_var_mono>>
  HINT_EXISTS_TAC>>
  metis_tac[])

(*Actually, it should probably be exactly 0,2,4,6...*)
val even_starting_locals_def = Define`
  even_starting_locals (locs:'a word_loc num_map) ⇔
    ∀x. x ∈ domain locs ⇒ is_phy_var x`

fun rm_let tm = tm|> SIMP_RULE std_ss [LET_THM]

val INJ_ALL_DISTINCT_MAP = prove(``
  ∀ls.
  ALL_DISTINCT (MAP f ls) ⇒
  INJ f (set ls) UNIV``,
  Induct>>fs[INJ_DEF]>>rw[]>>
  metis_tac[MEM_MAP])

val check_colouring_ok_alt_INJ = prove(``
  ∀ls.
  check_colouring_ok_alt f ls ⇒
  EVERY (λx. INJ f (domain x) UNIV) ls``,
  Induct>>fs[check_colouring_ok_alt_def,LET_THM]>>rw[]>>
  fs[GSYM MAP_MAP_o]>>
  imp_res_tac INJ_ALL_DISTINCT_MAP>>
  fs[set_toAList_keys])

val oracle_colour_ok_correct = prove(``
  ∀prog k col_opt st hd tl x.
  even_starting_locals st.locals ∧
  get_clash_sets prog LN = (hd,tl) ∧
  oracle_colour_ok k col_opt (hd::tl) prog = SOME x ⇒
  ∃perm'.
  let (res,rst) = evaluate(prog,st with permute:=perm') in
  if (res = SOME Error) then T else
  let (res',rcst) = evaluate(x,st) in
    res = res' ∧
    word_state_eq_rel rst rcst ∧
    case res of
      NONE => T
    | SOME _ => rst.locals = rcst.locals``,
  rw[oracle_colour_ok_def]>>fs[LET_THM]>>
  EVERY_CASE_TAC>>fs[]>>
  Q.ISPECL_THEN[`prog`,`st`,`st`,`total_colour x'`,`LN:num_set`] mp_tac evaluate_apply_colour>>
  discharge_hyps>-
    (fs[word_state_eq_rel_def,strong_locals_rel_def]>>
    rw[]
    >-
      (match_mp_tac colouring_ok_alt_thm>>
      fs[colouring_ok_alt_def,LET_THM]>>
      qabbrev_tac`ls = hd::tl`>>
      imp_res_tac check_colouring_ok_alt_INJ>>
      fs[Abbr`ls`])
    >>
      fs[every_even_colour_def]>>
      fs[total_colour_def]>>FULL_CASE_TAC>>
      fs[even_starting_locals_def]>>
      fs[GSYM MEM_toAList]>>
      fs[EVERY_MEM]>>
      res_tac>>
      fs[]>>
      fs[MEM_toAList,domain_lookup])>>
  rw[]>>qexists_tac`perm'`>>pop_assum mp_tac>>
  LET_ELIM_TAC>>fs[]>>
  FULL_CASE_TAC>>fs[])

(*Prove the full correctness theorem for word_alloc*)
val word_alloc_correct = store_thm("word_alloc_correct",``
  ∀alg prog k col_opt st.
  even_starting_locals st.locals
  ⇒
  ∃perm'.
  let (res,rst) = evaluate(prog,st with permute:=perm') in
  if (res = SOME Error) then T else
  let (res',rcst) = evaluate(word_alloc alg k prog col_opt,st) in
    res = res' ∧
    word_state_eq_rel rst rcst ∧
    case res of
      NONE => T
    | SOME _ => rst.locals = rcst.locals``,
  rw[]>>
  qpat_abbrev_tac`cprog = word_alloc A B C D`>>
  fs[word_alloc_def]>>
  pop_assum mp_tac>>LET_ELIM_TAC>>
  pop_assum mp_tac>>reverse FULL_CASE_TAC>>strip_tac
  >-
    (imp_res_tac oracle_colour_ok_correct>>fs[LET_THM,Abbr`cprog`]>>
    qexists_tac`perm'`>>rw[]>>fs[])
  >>
  Q.ISPECL_THEN[`prog`,`st`,`st`,`total_colour col`,`LN:num_set`] mp_tac evaluate_apply_colour>>
  discharge_hyps>-
    (rw[]
    >-
      (*Prove that the colors are okay*)
      (match_mp_tac colouring_ok_alt_thm>>
      match_mp_tac (colouring_satisfactory_colouring_ok_alt|>rm_let)>>
      unabbrev_all_tac>>
      fs[]>>
      match_mp_tac (reg_alloc_total_satisfactory|>rm_let)>>
      fs[clash_sets_to_sp_g_undir])
    >-
      fs[word_state_eq_rel_def]
    >>
      fs[strong_locals_rel_def,even_starting_locals_def]>>
      rw[]>>
      fs[domain_lookup]>>
      first_x_assum(qspec_then`n` assume_tac)>>
      rfs[]>>
      Q.ISPECL_THEN[`alg`,`clash_graph`,`k`,`moves`] mp_tac (reg_alloc_conventional_phy_var|>rm_let)>>
      discharge_hyps>-
        (rw[Abbr`clash_graph`]>>fs[clash_sets_to_sp_g_undir])
      >>
      rw[colouring_conventional_def,LET_THM])
  >>
  rw[]>>
  qexists_tac`perm'`>>rw[]>>
  fs[LET_THM]>>
  FULL_CASE_TAC>>fs[])

(*This is only needed for instructions so that we can do 3-to-2 easily*)
val distinct_tar_reg_def = Define`
  (distinct_tar_reg (Arith (Binop bop r1 r2 ri))
    ⇔ (r1 ≠ r2 ∧ case ri of (Reg r3) => r1 ≠ r3 | _ => T)) ∧
  (distinct_tar_reg  (Arith (Shift l r1 r2 n))
    ⇔ r1 ≠ r2) ∧
  (distinct_tar_reg _ ⇔ T)`

val fake_moves_distinct_tar_reg = prove(``
  ∀ls ssal ssar na l r a b c conf.
  fake_moves ls ssal ssar na = (l,r,a,b,c) ⇒
  every_inst distinct_tar_reg l ∧
  every_inst distinct_tar_reg r``,
  Induct>>fs[fake_moves_def]>>rw[]>>fs[every_inst_def]>>
  pop_assum mp_tac>> LET_ELIM_TAC>> EVERY_CASE_TAC>> fs[LET_THM]>>
  unabbrev_all_tac>>
  metis_tac[fake_move_def,every_inst_def,distinct_tar_reg_def])

val ssa_cc_trans_distinct_tar_reg = prove(``
  ∀prog ssa na.
  is_alloc_var na ∧
  every_var (λx. x < na) prog ∧
  ssa_map_ok na ssa ⇒
  every_inst distinct_tar_reg (FST (ssa_cc_trans prog ssa na))``,
  ho_match_mp_tac ssa_cc_trans_ind>>fs[ssa_cc_trans_def]>>rw[]>>
  unabbrev_all_tac>>
  fs[every_inst_def]>>imp_res_tac ssa_cc_trans_props>>fs[]
  >-
    (Cases_on`i`>>TRY(Cases_on`a`)>>TRY(Cases_on`m`)>>TRY(Cases_on`r`)>>
    fs[ssa_cc_trans_inst_def,LET_THM,next_var_rename_def,every_var_def,every_var_inst_def,every_var_imm_def]>>
    qpat_assum`A=i'` sym_sub_tac>>
    fs[distinct_tar_reg_def,ssa_map_ok_def,option_lookup_def]>>
    EVERY_CASE_TAC>>rw[]>>res_tac>>fs[]>>
    TRY(DECIDE_TAC))
  >-
    (fs[every_var_def]>>
    first_x_assum match_mp_tac>>
    match_mp_tac every_var_mono >>
    HINT_EXISTS_TAC>>fs[]>>DECIDE_TAC)
  >-
    (fs[every_var_def]>>qpat_assum`A = (B,C,D,E)`mp_tac>>fs[fix_inconsistencies_def,fake_moves_def]>>LET_ELIM_TAC>>
    fs[every_inst_def,EQ_SYM_EQ]>>
    TRY(metis_tac[fake_moves_distinct_tar_reg])>>
    first_x_assum match_mp_tac>>
    rw[]
    >-
      (match_mp_tac every_var_mono >>
      HINT_EXISTS_TAC>>fs[]>>DECIDE_TAC)
    >>
    metis_tac[ssa_map_ok_more])
  >> TRY
    (fs[list_next_var_rename_move_def]>>rpt (pop_assum mp_tac)>>
    LET_ELIM_TAC>>fs[every_inst_def,EQ_SYM_EQ]>>NO_TAC)
  >>
  FULL_CASE_TAC>>fs[every_var_def,every_inst_def]
  >-
    (qpat_assum`A ∧ B ∧ C ⇒ every_inst distinct_tar_reg D` mp_tac>>
    discharge_hyps>-
      (imp_res_tac list_next_var_rename_move_props_2>>
      fs[next_var_rename_def]>>
      `ssa_map_ok na' (inter ssa' numset)` by
        metis_tac[ssa_map_ok_inter]>>
      rfs[]>>rw[]
      >-
        metis_tac[is_alloc_var_add]
      >-
        (match_mp_tac every_var_mono>>HINT_EXISTS_TAC>>
        fs[]>>DECIDE_TAC)
      >>
        match_mp_tac ssa_map_ok_extend>>
        fs[]>>
        metis_tac[convention_partitions])
      >>
      fs[list_next_var_rename_move_def]>>
      rpt(qpat_assum`A=(B,C,D)` mp_tac)>>
      LET_ELIM_TAC>>fs[EQ_SYM_EQ,every_inst_def])
    >>
      PairCases_on`x`>>fs[fix_inconsistencies_def]>>LET_ELIM_TAC>>unabbrev_all_tac>>fs[every_inst_def]>>
      qpat_assum`A ∧ B ∧ C ⇒ every_inst distinct_tar_reg ren_ret_handler` mp_tac>>
      discharge_hyps_keep>-
        (imp_res_tac list_next_var_rename_move_props_2>>
        fs[next_var_rename_def]>>
        `ssa_map_ok na' (inter ssa' numset)` by
          metis_tac[ssa_map_ok_inter]>>
        rfs[]>>rw[]
        >-
          metis_tac[is_alloc_var_add]
        >-
          (match_mp_tac every_var_mono>>
          qexists_tac` λx. x < na`>>fs[]>>
          DECIDE_TAC)
        >>
          match_mp_tac ssa_map_ok_extend>>
          fs[]>>
          metis_tac[convention_partitions])>>
      qpat_assum`A ∧ B ∧ C ⇒ every_inst distinct_tar_reg ren_exc_handler` mp_tac>>
      discharge_hyps_keep>-
        (imp_res_tac list_next_var_rename_move_props_2>>
        fs[next_var_rename_def]>>
        `ssa_map_ok na' (inter ssa' numset)` by
          metis_tac[ssa_map_ok_inter]>>
        rfs[]>>rw[]
        >-
          metis_tac[is_alloc_var_add]
        >-
          (match_mp_tac every_var_mono>>
          qexists_tac` λx. x < na`>>fs[]>>
          DECIDE_TAC)
        >>
          match_mp_tac ssa_map_ok_extend>>
          fs[]>>rw[]
          >-
            (`na'' ≤ n'` by DECIDE_TAC>>
            metis_tac[ssa_map_ok_more])
          >> metis_tac[convention_partitions])>>
      fs[list_next_var_rename_move_def]>>
      rpt(qpat_assum`A=(B,C,D)` mp_tac)>>
      LET_ELIM_TAC>>fs[EQ_SYM_EQ,every_inst_def]>>
      metis_tac[fake_moves_distinct_tar_reg])

val full_ssa_cc_trans_distinct_tar_reg = store_thm("full_ssa_cc_trans_distinct_tar_reg",``
  ∀n prog.
  every_inst distinct_tar_reg (full_ssa_cc_trans n prog)``,
  rw[]>>
  fs[full_ssa_cc_trans_def]>>
  LET_ELIM_TAC>>
  simp[every_inst_def]>>CONJ_TAC
  >-
    (fs[setup_ssa_def,list_next_var_rename_move_def,LET_THM]>>
    split_pair_tac>>fs[]>>
    metis_tac[every_inst_def])
  >>
  assume_tac limit_var_props>>
  fs[markerTheory.Abbrev_def]>>
  rfs[]>>
  imp_res_tac setup_ssa_props_2>>
  pop_assum(qspecl_then[`prog`,`n`] mp_tac)>>
  LET_ELIM_TAC>>
  Q.ISPECL_THEN [`prog`,`ssa''`,`na''`] mp_tac ssa_cc_trans_distinct_tar_reg>>
  discharge_hyps>-
    (rfs[]>>match_mp_tac every_var_mono>>HINT_EXISTS_TAC>>fs[]>>
    DECIDE_TAC)>>
  fs[]);

val list_max_IMP = prove(``
  ∀ls.
  P 0 ∧ EVERY P ls ⇒ P (list_max ls)``,
  Induct>>fs[list_max_def]>>rw[]>>
  IF_CASES_TAC>>fs[])

val max_var_exp_IMP = prove(``
  ∀exp.
  P 0 ∧ every_var_exp P exp ⇒
  P (max_var_exp exp)``,
  ho_match_mp_tac max_var_exp_ind>>fs[max_var_exp_def,every_var_exp_def]>>
  rw[]>>
  match_mp_tac list_max_IMP>>
  fs[EVERY_MAP,EVERY_MEM])

val max_var_IMP = store_thm("max_var_IMP",``
  ∀prog.
  P 0 ∧ every_var P prog ⇒
  P (max_var prog)``,
  ho_match_mp_tac max_var_ind>>
  fs[every_var_def,max_var_def,max_var_exp_IMP,MAX_DEF]>>rw[]>>
  TRY(metis_tac[max_var_exp_IMP])>>
  TRY (match_mp_tac list_max_IMP>>fs[EVERY_APPEND,every_name_def])
  >-
    (Cases_on`i`>>TRY(Cases_on`a`)>>TRY(Cases_on`m`)>>
    fs[max_var_inst_def,every_var_inst_def,every_var_imm_def,MAX_DEF]>>
    EVERY_CASE_TAC>>fs[every_var_imm_def])
  >-
    (TOP_CASE_TAC>>unabbrev_all_tac>>fs[list_max_IMP]>>
    EVERY_CASE_TAC>>fs[LET_THM]>>rw[]>>
    match_mp_tac list_max_IMP>>fs[EVERY_APPEND,every_name_def])
  >> (unabbrev_all_tac>>EVERY_CASE_TAC>>fs[every_var_imm_def]))

val _ = export_theory();