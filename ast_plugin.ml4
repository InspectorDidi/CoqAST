DECLARE PLUGIN "ast_plugin"

open Declarations
open Format
open Univ
open Term
open Names
open Pp

let rec range (min : int) (max : int) =
  if min < max then min :: range (min + 1) max else []

type ast =
| Leaf of string
| Node of string * ast list

let build_name (n : name) =
  match n with
  | Name id -> Node ("Name", [Leaf (string_of_id id)])
  | Anonymous -> Leaf "Anonymous"

let build_var (v : identifier) =
  Node ("Var", [Leaf (string_of_id v)])

let build_rel (env : Environ.env) (i : int) =
  let (name, body, typ) = Environ.lookup_rel i env in
  match name with
    Name id -> build_var id
  | Anonymous -> Node ("Rel", [Leaf (string_of_int i)])

let build_meta (n : metavariable) =
  Node ("Meta", [Leaf (string_of_int n)])

let build_evar (k : existential_key) (c_asts : ast list) =
  Node ("Evar", Leaf string_of_int (Evar.repr k) :: c_asts)

let build_sort (s : sorts) =
  let s_ast =
    match s with
      Prop _ -> if s = prop_sort then "Prop" else "Set"
    | Type _ -> "Type" (* skip universe *)
  in Node ("Sort", [Leaf s_ast])

let string_of_cast_kind (k : cast_kind) =
  match k with
    VMcast -> "VMcast"
  | DEFAULTcast -> "DEFAULTcast"
  | REVERTcast -> "REVERTcast"
  | NATIVEcast -> "NATIVEcast"

let build_cast (trm_ast : ast) (kind : cast_kind) (typ_ast : ast) =
  Node ("Cast", [trm_ast; Leaf (string_of_cast_kind kind); typ_ast])

let build_product (n : name) (typ_ast : ast) (body_ast : ast) =
  Node ("Prod", [build_name n; typ_ast; body_ast])

let build_lambda (n : name) (typ_ast : ast) (body_ast : ast) =
  Node ("Lambda", [build_name n; typ_ast; body_ast])

let build_let_in (n : name) (typ_ast : ast) (expr_ast : ast) (body_ast : ast) =
  Node ("LetIn", [build_name n; typ_ast; expr_ast; body_ast])

let build_app (f_ast : ast) (arg_asts : ast list) =
  Node ("App", f_ast :: arg_asts)

let build_case (info : case_info) (case_typ_ast : ast) (match_ast : ast) (branch_asts : ast list) =
  let num_args = Leaf (string_of_int info.ci_npar) in
  let match_typ = Node ("CaseMatch", [match_ast]) in
  let branches = Node ("CaseBranches", branch_asts) in
  Node ("Case", [num_args; case_typ_ast; match_typ; branches])

let build_proj (p_const_ast : ast) (c_ast : ast) =
  Node ("Proj", [p_const_ast; c_ast])

let build_construct ((k,i):Names.inductive) (index : int) =
  let kn = Names.canonical_mind k in
  Node ("Construct", [Leaf (Names.string_of_kn kn); Leaf (string_of_int index)])

let get_definition (cb : Declarations.constant_body) =
  match cb.const_body with
  | Undef _ ->
    None
  | Def cs ->
    Some (Mod_subst.force_constr cs)
  | OpaqueDef o ->
    Some (Opaqueproof.force_proof (Global.opaque_tables ()) o)

let bindings_for_fix (names : name array) (typs : constr array) =
  Array.to_list
    (CArray.map2_i
       (fun i name typ -> (name, None, Vars.lift i typ))
       names typs)

let build_fix_fun (index : int) (body_ast : ast) =
  Node ("Fun", [Leaf (string_of_int index); body_ast])

let build_fix (index : int) (funs : ast list) =
  Node ("Fix", Leaf (string_of_int index) :: funs)

let build_cofix (index : int) (funs : ast list) =
  Node ("CoFix", Leaf (string_of_int index) :: funs)

let bindings_for_inductive (env : Environ.env) (mutind_body : mutual_inductive_body) (ind_bodies : one_inductive_body list) =
  List.map
    (fun ind_body ->
      let univ_context = mutind_body.mind_universes in
      let univ_instance = UContext.instance univ_context in
      let name_id = ind_body.mind_typename in
      let mutind_spec = (mutind_body, ind_body) in
      let typ = Inductive.type_of_inductive env (mutind_spec, univ_instance) in
      (Names.Name name_id, None, typ))
    ind_bodies

let named_constructors (ind_body : one_inductive_body) =
  let constr_names = Array.to_list ind_body.mind_consnames in
  let indexes = List.map string_of_int (range 1 ((List.length constr_names) + 1)) in
  let constrs = Array.to_list ind_body.mind_user_lc in
  List.combine indexes (List.combine constr_names constrs)

let rec build_ast (env : Environ.env) (depth : int) (trm : types) =
  match kind_of_term trm with
  | Rel i ->
    build_rel env i
  | Var v ->
    build_var v
  | Meta mv ->
    build_meta mv
  | Evar (k, cs) ->
    let cs' = List.map (build_ast env depth) (Array.to_list cs) in
    build_evar k cs'
  | Sort s ->
    build_sort s
  | Cast (c, k, t) ->
    let c' = build_ast env depth c in
    let t' = build_ast env depth t in
    build_cast c' k t'
  | Prod (n, t, b) ->
    let t' = build_ast env depth t in
    let b' = build_ast (Environ.push_rel (n, None, t) env) depth b in
    build_product n t' b'
  | Lambda (n, t, b) ->
    let t' = build_ast env depth t in
    let b' = build_ast (Environ.push_rel (n, None, t) env) depth b in
    build_lambda n t' b'
  | LetIn (n, t, e, b) ->
    let t' = build_ast env depth t in
    let e' = build_ast env depth e in
    let b' = build_ast (Environ.push_rel (n, Some e, t) env) depth b in
    build_let_in n t' e' b'
  | App (f, xs) ->
    let f' = build_ast env depth f in
    let xs' = List.map (build_ast env depth) (Array.to_list xs) in
    build_app f' xs'
  | Case (ci, ct, m, bs) ->
    let typ = build_ast env depth ct in
    let match_typ = build_ast env depth m in
    let branches = List.map (build_ast env depth) (Array.to_list bs) in
    build_case ci typ match_typ branches
  | Proj (p, c) ->
    let p' = build_ast env depth (Term.mkConst (Projection.constant p)) in
    let c' = build_ast env depth c in
    build_proj p' c'
  | Construct ((i, c_index), _) ->
    build_construct i c_index
  | Const c ->
    build_const env depth c
  | Fix ((is, i), (ns, ts, ds)) ->
    build_fix i (build_fixpoint_functions env depth ns ts ds)
  | CoFix (i, (ns, ts, ds)) ->
    build_cofix i (build_fixpoint_functions env depth ns ts ds)
  | Ind i ->
    build_minductive env depth i
and build_const (env : Environ.env) (depth : int) ((c, _) : pconstant) =
  let kn = Constant.canonical c in
  if depth <= 0 then (* don't expand *)
    Node ("Const", [Leaf (string_of_kn kn)])
  else (* expand *)
    let cb = Environ.lookup_constant c env in
    match get_definition cb with
    | None ->
      begin
	match cb.const_type with
	| RegularArity _ -> (* axiom *)
	  Node ("Const", [Leaf (string_of_kn kn)])
	| TemplateArity _ -> assert false
      end
    | Some t ->
      build_ast env (depth - 1) t
and build_fixpoint_functions (env : Environ.env) (depth : int) (names : name array) (typs : constr array) (defs : constr array)  =
  let env_fix = Environ.push_rel_context (bindings_for_fix names typs) env in
  List.map
    (fun i ->
      let def = build_ast env_fix depth (Array.get defs i) in
      build_fix_fun i def)
    (range 0 (Array.length names))
and build_minductive (env : Environ.env) (depth : int) (((i, i_index), _) : pinductive) =
  let mutind_body = Environ.lookup_mind i env in
  let ind_bodies = mutind_body.mind_packets in
  let ind_bodies_list = Array.to_list ind_bodies in
  let env_ind = Environ.push_rel_context (bindings_for_inductive env mutind_body ind_bodies_list) env in
  let cs = List.map (build_oinductive env_ind depth) ind_bodies_list in
  Node ("MInd", cs)
and build_oinductive (env : Environ.env) (depth : int) (ind_body : one_inductive_body) =
  let constrs =
    List.map (fun (i, (n, typ)) -> Node ("Cons", [Leaf i; Leaf (Names.string_of_id n); build_ast env (depth - 1) typ])) (named_constructors ind_body)
  in
  Node ("Ind", Leaf (Names.string_of_id ind_body.mind_typename) :: constrs)

let rec string_of_ast a =
match a with
| Leaf s -> s
| Node (h, l) ->
  let sl = List.map string_of_ast l in 
  let s = String.concat " " sl in
  Printf.sprintf "(%s %s)" h s

let buf = Buffer.create 1000

let formatter out =
  let fmt =
    match out with
    | Some oc -> Pp_control.with_output_to oc
    | None -> Buffer.clear buf; Format.formatter_of_buffer buf
  in
  Format.pp_set_max_boxes fmt max_int;
  fmt

VERNAC COMMAND EXTEND Print_AST
| [ "PrintAST" constr(c) ] ->
  [
    let fmt = formatter None in
    let (evm, env) = Lemmas.get_current_context () in
    let (t, _) = Constrintern.interp_constr env evm c in
    let ast = build_ast (Global.env ()) 1 t in
    pp_with fmt (str (string_of_ast ast));
    Format.pp_print_flush fmt ();
    if not (Int.equal (Buffer.length buf) 0) then begin
      Pp.msg_notice (str (Buffer.contents buf));
      Buffer.reset buf
    end
  ]
(*| [ "PrintAST" string(f) constr(c) ] ->
  [
    let oc = open_out f in
    let fmt = formatter (Some oc) in
    List.iter (fun def -> print_ast fmt 0 def) cl;
    close_out oc;
    Pp.msg_notice (str "wrote AST(s) to file: " ++ str f)
  ]*)
END