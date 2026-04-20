import Lake
open Lake DSL

package harvest where
  leanOptions := #[
    ⟨`autoImplicit, false⟩
  ]

@[default_target]
lean_lib Harvest where
  srcDir := "."
