open preamble
      mllistTheory miscTheory

val _ = new_theory"mlvector"

val _ = Datatype `
  vector = Vector ('a list)`;

val sub_def = Define `
  sub (Vector l) n = EL n l`;

val length_def = Define `
  length (Vector l) = LENGTH l`;

val tabulate_def = Define`
  tabulate n f = Vector (GENLIST f n)`;

val toList_aux_def = tDefine "toList_aux"`
  toList_aux vec n =
  if length(vec) <= n
    then []
  else sub vec n::toList_aux vec (n + 1)`
(wf_rel_tac `measure (\(vec, n). length(vec) - n)`)

val toList_aux_ind = theorem"toList_aux_ind";

val toList_def = Define`toList vec = toList_aux vec 0`;

val toList_aux_thm = Q.prove (
  `!vec n. toList_aux vec n = case vec of Vector vs => DROP n vs`,
  ho_match_mp_tac toList_aux_ind \\
  rw [] \\
  ONCE_REWRITE_TAC [toList_aux_def] \\
  IF_CASES_TAC THEN1
    (Cases_on `vec` \\
    fs [length_def, DROP_NIL]) \\
  fs [] \\ 
  Cases_on `vec` \\ 
  fs [sub_def, length_def, DROP_EL_CONS]
);

val toList_thm = Q.store_thm (
  "toList_thm",
  `!ls. toList (Vector ls) = ls`,  
  rw [toList_def, toList_aux_thm]
);

val update_def = Define`
  update vec i x = Vector (LUPDATE x i (toList(vec)))`;

val update_thm = Q.store_thm (
  "update_thm",
  `!vec i x. sub (update vec i x) i = if i < length vec then x
    else sub vec i`,
  Cases \\
  rw [update_def, toList_thm, EL_LUPDATE, length_def, sub_def]
);



val concat_def = Define`
  concat l = Vector (FLAT (MAP toList l))`;

val map_def = Define`
  map vec f = Vector (MAP f (toList vec))`;

val mapi_def = Define`
  mapi vec f = Vector (mllist$mapi f 0 (toList vec))`;


val less_than_length_thm = Q.prove (
  `!xs n. (n < LENGTH xs) ==> (?ys z zs. (xs = ys ++ z::zs) /\ (LENGTH ys = n))`,
  rw[] \\
  qexists_tac`TAKE n xs` \\
  rw[] \\
  qexists_tac`HD (DROP n xs)` \\
  qexists_tac`TL (DROP n xs)` \\
  Cases_on`DROP n xs` \\ fs[]
  >- fs[DROP_NIL] \\
  metis_tac[TAKE_DROP,APPEND_ASSOC,CONS_APPEND]
);

val foldli_aux_def = Define`
  (foldli_aux f e vec n 0 = e) /\
  (foldli_aux f e vec n (SUC len) = foldli_aux f (f n e (sub vec n)) vec (n + 1) len)`;

val foldli_def = Define`
  foldli f e vec = foldli_aux f e vec 0 (length vec)`;

val foldli_aux_thm = Q.prove (
  `!f e vec n len. (n + len = length vec) ==> 
    (foldli_aux f e vec n len = mllist$foldli_aux f e n (DROP n (toList vec)))`,
  Cases_on `vec` \\ Induct_on `len` \\
  rw [foldli_aux_def, toList_thm, length_def, sub_def]
  >- rw [DROP_LENGTH_TOO_LONG, mllistTheory.foldli_aux_def]
  \\ rw [DROP_EL_CONS, mllistTheory.foldli_aux_def, ADD1]
);

val foldli_thm = Q.store_thm (
  "foldli_thm",
  `!f e vec. foldli f e vec = mllist$foldli f e (toList vec)`,
  rw [foldli_def, mllistTheory.foldli_def, foldli_aux_thm]
);

val foldl_aux_def = Define`
  (foldl_aux f e vec n 0 = e) /\
  (foldl_aux f e vec n (SUC len) = foldl_aux f (f e (sub vec n)) vec (n + 1) len)`;

val foldl_def = Define`
  foldl f e vec = foldl_aux f e vec 0 (length vec)`;

val foldl_aux_thm = Q.prove (
  `!f e vec x len. (x + len = length vec) ==>
    (foldl_aux f e vec x len = FOLDL f e (DROP x (toList vec)))`,
  Induct_on `len` \\ Cases_on `vec` \\
  rw [foldl_aux_def, DROP_LENGTH_TOO_LONG, length_def, toList_thm] \\
  rw [length_def, sub_def, toList_thm] \\
  `x < LENGTH l` by decide_tac \\
  drule less_than_length_thm \\
  rw [] \\
  rw [] \\
  `LENGTH ys + 1 = LENGTH (ys ++ [z])` by (fs [] \\ NO_TAC) \\ ASM_REWRITE_TAC [DROP_LENGTH_APPEND]\\
  simp_tac std_ss [GSYM APPEND_ASSOC, APPEND, EL_LENGTH_APPEND, NULL, HD,
        FOLDL,  DROP_LENGTH_APPEND]
);

val foldl_thm = Q.store_thm (
  "foldl_thm",
  `!f e vec. foldl f e vec = FOLDL f e (toList vec)`,
  rw [foldl_aux_thm, foldl_def]
);



val foldri_aux_def = Define`
  (foldri_aux f e vec 0 = e) /\
  (foldri_aux f e vec (SUC len) = foldri_aux f (f len (sub vec len) e) vec len)`;

val foldri_def = Define`
  foldri f e vec = foldri_aux f e vec (length vec)`;


val foldri_aux_thm = Q.prove (
  `!f e vec len. len <= length vec ==>
    (foldri_aux f e vec len = FOLDRi f e (TAKE len (toList vec)))`,
  Induct_on `len` \\ rw[foldri_aux_def] \\
  Cases_on `vec` \\ fs[length_def, toList_thm, sub_def] \\
  rw [ADD1, TAKE_SUM, take1_drop, FOLDRi_APPEND]
);

val foldri_thm = Q.store_thm (
  "foldri_thm",
  `!f e vec. foldri f e vec = FOLDRi f e (toList vec)`,
  Cases_on `vec` \\
  rw [foldri_aux_thm, foldri_def, toList_thm, length_def]
);



val foldr_aux_def = Define`
  (foldr_aux f e vec 0 = e) /\
  (foldr_aux f e vec (SUC len) = foldr_aux f (f (sub vec len) e) vec len)`;

val foldr_def = Define`
  foldr f e vec = foldr_aux f e vec (length vec)`;

val foldr_aux_thm = Q.prove (
  `!f e vec len. len <= length vec ==>
    (foldr_aux f e vec len = FOLDR f e (TAKE len (toList vec)))`,
  Induct_on `len` \\ rw[foldr_aux_def] \\
  Cases_on `vec` \\ fs[length_def, toList_thm, sub_def] \\
  rw [ADD1, TAKE_SUM, take1_drop, FOLDR_APPEND]
);

val foldr_thm = Q.store_thm (
  "foldr_thm",
  `!f e vec. foldr f e vec = FOLDR f e (toList vec)`,
  Cases_on `vec` \\
  rw[foldr_def, foldr_aux_thm, length_def, toList_thm]
);


val findi_aux_def = Define`
  (findi_aux f vec n 0 = NONE) /\
  (findi_aux f vec n (SUC len) =
  if f n (sub vec n)
    then SOME(n, (sub vec n))
  else findi_aux f vec (n + 1) len)`;

val findi_def = Define`
  findi f vec = findi_aux f vec 0 (length vec)`;



val find_aux_def = Define`
  (find_aux f vec n 0 = NONE) /\
  (find_aux f vec n (SUC len) =
  if f (sub vec n)
    then SOME(sub vec n)
  else find_aux f vec (n + 1) len)`;

val find_def = Define `
  find f vec = find_aux f vec 0 (length vec)`;

val find_aux_thm = Q.prove (
  `!f vec n len. (n + len = length vec) ==> (find_aux f vec n len = FIND f (DROP n (toList vec)))`,
  Induct_on `len` \\ Cases_on `vec` \\ rw [find_aux_def, sub_def, length_def,
  toList_thm, FIND_def, INDEX_FIND_def] \\
  rw[DROP_LENGTH_NIL, INDEX_FIND_def] THEN1
  (qexists_tac`(0, EL n l)` \\ rw [DROP_EL_CONS, INDEX_FIND_def]) \\
  rw [DROP_EL_CONS, INDEX_FIND_def, index_find_thm]
);

val find_thm = Q.store_thm (
  "find_thm",
  `!f vec. find f vec = FIND f (toList vec)`,
  rw [find_aux_thm, find_def]
);



val exists_aux_def = Define`
  (exists_aux f vec n 0 = F) /\
  (exists_aux f vec n (SUC len) =
    if f (sub vec n)
      then T
    else exists_aux f vec (n + 1) len)`;

val exists_def = Define`
  exists f vec = exists_aux f vec 0 (length vec)`;

val exists_aux_thm = Q.prove(
  `!f vec n len. (n + len = length (vec)) ==> 
    (exists_aux f vec n len = EXISTS f (DROP n (toList vec)))`,
  Induct_on `len` \\ Cases_on `vec` \\ rw[toList_thm, length_def, sub_def, exists_aux_def] THEN1
  rw [DROP_LENGTH_NIL, EVERY_DEF] \\
  rw [DROP_EL_CONS]
);

val exists_thm = Q.store_thm (
  "exists_thm",
  `!f vec. exists f vec = EXISTS f (toList vec)`,
  Cases_on `vec` \\
  rw [exists_def, exists_aux_thm]
);



val all_aux_def = Define`
  (all_aux f vec n 0 = T) /\
  (all_aux f vec n (SUC len) =
    if f (sub vec n) 
      then all_aux f vec (n + 1) len
    else F)`;

val all_def = Define`
  all f vec = all_aux f vec 0 (length vec)`;

val all_aux_thm = Q.prove (
  `!f vec n len. (n + len = length vec) ==> (all_aux f vec n len = EVERY f (DROP n (toList vec)))`,
  Induct_on `len` \\ Cases_on `vec` \\ rw[toList_thm, length_def, sub_def, all_aux_def] THEN1
  rw [DROP_LENGTH_NIL] \\
  rw [DROP_EL_CONS]
);

val all_thm = Q.store_thm (
  "all_thm",
  `!f vec. all f vec = EVERY f (toList vec)`,
  Cases_on `vec` \\ rw[all_def, all_aux_thm]
);



val collate_aux_def = Define`
  (collate_aux f vec1 vec2 n ord 0 = ord) /\
  (collate_aux f vec1 vec2 n ord (SUC len) =
    if f (sub vec1 n) (sub vec2 n) = EQUAL
      then collate_aux f vec1 vec2 (n + 1) ord len
    else f (sub vec1 n) (sub vec2 n))`;

val collate_def = Define`
  collate f vec1 vec2 =
  if (length vec1) < (length vec2)
    then collate_aux f vec1 vec2 0 LESS (length vec1)
  else if (length vec2) < (length vec1)
    then collate_aux f vec1 vec2 0 GREATER (length vec2)
  else collate_aux f vec1 vec2 0 EQUAL (length vec2)`;

val collate_aux_less_thm = Q.prove (
  `!f vec1 vec2 n len. (n + len = length vec1) /\ (length vec1 < length vec2) ==> 
    (collate_aux f vec1 vec2 n Less len = mllist$collate f (DROP n (toList vec1)) (DROP n (toList vec2)))`,
      Cases_on `vec1` \\ Cases_on `vec2` \\ Induct_on `len` \\
      rw [collate_aux_def, mllistTheory.collate_def, length_def, toList_thm, sub_def, DROP_EL_CONS]
      >- rw [DROP_LENGTH_TOO_LONG, mllistTheory.collate_def] 
);

val collate_aux_equal_thm = Q.prove (
  `!f vec1 vec2 n len. (n + len = length vec2) /\ (length vec1 = length vec2) ==>
    (collate_aux f vec1 vec2 n Equal len = 
      mllist$collate f (DROP n (toList vec1)) (DROP n (toList vec2)))`,
  Cases_on `vec1` \\ Cases_on `vec2` \\ Induct_on `len` \\
  rw [collate_aux_def, mllistTheory.collate_def, length_def, toList_thm, sub_def]
  >- rw [DROP_LENGTH_TOO_LONG, mllistTheory.collate_def] \\
  fs [DROP_EL_CONS, mllistTheory.collate_def] 
);

val collate_aux_greater_thm = Q.prove (
  `!f vec1 vec2 n len. (n + len = length vec2) /\ (length vec2 < length vec1) ==>
    (collate_aux f vec1 vec2 n Greater len = 
      mllist$collate f (DROP n (toList vec1)) (DROP n (toList vec2)))`,
  Cases_on `vec1` \\ Cases_on `vec2` \\ Induct_on `len` \\
  rw [collate_aux_def, mllistTheory.collate_def, length_def, toList_thm, sub_def, DROP_EL_CONS]
  >- rw [DROP_LENGTH_TOO_LONG, mllistTheory.collate_def] 
);

val collate_thm = Q.store_thm (
  "collate_thm",
  `!f vec1 vec2. collate f vec1 vec2 = mllist$collate f (toList vec1) (toList vec2)`,
  rw [collate_def, collate_aux_greater_thm, collate_aux_equal_thm, collate_aux_less_thm]
);   

val _ = export_theory()