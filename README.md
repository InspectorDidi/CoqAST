This plugin is a fork of uwplse/CoqAST, which provides the ability to traverse the Gallina AST.

# Plugin functionality

The plugin works roughly like Print, except that instead of pretty-printing a term,
it prints an s-expression that represents the AST.


For example:

    Coq < PrintAST nat_ind.

    (Definition Coq.Init.Datatypes.nat_ind (Lambda P_2 (Prod n_1 nat (Sort Prop)) (Lambda f_22 (App P_2 O) (Lambda f_222 (Prod n_221 nat (Prod out_2211 (App P_2 n_221) (App P_2 (App S n_221)))) (Fix (Functions (App F 0 (Prod n_2221 nat (App P_2 n_2221)) (Lambda n_2222 nat (Case 0 (Lambda n_22222 nat (App P_2 n_22222)) (CaseMatch n_2222) (CaseBranches f_22 (Lambda n_22222 nat (App f_222 n_22222 (App F n_22222)))))))) 0)))))

## Differences from the original

The purpose of this fork is provide a version of Coq proof trees that is especially amenable to proof tree analysis in the project https://github.com/scottviteri/ManipulateProofTrees. The specific changes are listed below:

 1. Variables names are modified when bound by a Lambda (append 2), Prod (append 1), or LetIn (append 3) constructors.
    This prevents two variables from having the same name in the same scope.

 2. Does not expand axioms or inductive types (still expands particular terms of an inductive type).
    These prevent the proof trees from exploding in size.
    So 'PrintAST nat' will not output anything.

 3. Some substitutions:
    Inductive type constructors: (Construct nat 1) -> S
    Removal of Name constructor: (Name "foo") -> "foo"

For comparison, here is an AST exported from the original version of the plugin:

    (Definition Coq.Init.Datatypes.nat_ind (Lambda (Name P) (Prod (Name n) (Name nat) (Sort Prop)) (Lambda (Name f) (App (Name P) (Construct (Name nat) 1)) (Lambda (Name f) (Prod (Name n) (Name nat) (Prod (Anonymous) (App (Name P) (Name n)) (App (Name P) (App (Construct (Name nat) 2) (Name n))))) (Fix (Functions ((Name F) 0 (Prod (Name n) (Name nat) (App (Name P) (Name n))) (Lambda (Name n) (Name nat) (Case 0 (Lambda (Name n) (Name nat) (App (Name P) (Name n))) (CaseMatch (Name n)) (CaseBranches (Name f) (Lambda (Name n) (Name nat) (App (Name f) (Name n) (App (Name F) (Name n))))))))) 0)))))


## Using the Plugin

The plugin is built to work with Coq 8.8. It may not build for other versions of Coq, since the
API sometimes changes between Coq versions.

To build:

        cd plugin
        make

To print:

        Coq < Add LoadPath "${YOUR_COQ_AST_DIR}/plugin/src".
        Coq < Require Import PrintAST.ASTPlugin.
        Coq < PrintAST nat_ind.

### Toggling DeBruijn Indexing

You can change the plugin to use DeBruijn indexing instead of names:

    Coq < Set PrintAST Indexing.

    Coq < PrintAST nat.
    (Inductive ((Name nat) (inductive_body (O 1 (Rel 1)) (S 2 (Prod (Anonymous) (Rel 1) (Rel 2))))))

### Showing Universe Instances

For universe-polymorphic constants, you can turn on printing universe instances:

    Coq < Set PrintAST Show Universes.

### Controlling the Printing Depth

You can change the depth at which the plugin prints definitions:

    Coq < PrintAST le with depth 1.
    (Inductive ((Name le) (inductive_body (le_n 1 (Prod (Name n) (Inductive ((Name nat) (inductive_body (O 1 (Rel 1)) (S 2 (Prod (Anonymous) (Rel 1) (Rel 2)))))) (App (Rel 2) (Rel 1) (Rel 1)))) (le_S 2 (Prod (Name n) (Inductive ((Name nat) (inductive_body (O 1 (Rel 1)) (S 2 (Prod (Anonymous) (Rel 1) (Rel 2)))))) (Prod (Name m) (Inductive ((Name nat) (inductive_body (O 1 (Rel 1)) (S 2 (Prod (Anonymous) (Rel 1) (Rel 2)))))) (Prod (Anonymous) (App (Rel 3) (Rel 2) (Rel 1)) (App (Rel 4) (Rel 3) (App (Construct (Inductive ((Name nat) (inductive_body (O 1 (Rel 1)) (S 2 (Prod (Anonymous) (Rel 1) (Rel 2)))))) 2) (Rel 2))))))))))

## Modifying the Command

To modify the top-level behavior, change the `VERNAC COMMAND EXTEND` block of code at the end of the file.

## Changing or Adding Options

To modify the options, change the options code at the beginning of the file.

## Traversing the AST

To modify the behavior when traversing the AST, modify `build_ast` and the functions it calls.
This is the bulk of the code.

There are comments explaining the different terms in the functions that `build_ast` calls.
The file purposely has non-standard OCaml style to try to make it clear what's going on.

If it's still not clear what is going on from the comments, the code you care about in Coq itself is inside of
the `kernel` directory. Start with `term.mli` and open up associated files as you need them.
**If you do this, please submit a pull request with your discoveries.** My eventual goal is to make this
so clear that nobody even needs to open up `term.mli` to begin with, because digging through
legacy Coq code can be arduous.
