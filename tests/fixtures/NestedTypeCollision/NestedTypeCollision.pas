namespace NestedTypeCollision;

// Regression fixture for a Fable5 review finding (HANDOFF.md §20): the
// NullabilityScanner.TOK_PROPERTY branch was missing the (depth =
// typeDepth) guard the field-declaration branches already had. Without
// it, a nested type's annotated property is attributed to the OUTER
// type (currentTypeName/typeDepth only get assigned once, on the first
// class/record/interface open) instead of being ignored, and
// ScanMemberDecl's unconditional dictionary write can silently
// overwrite an outer member of the same name with the nested member's
// (opposite) nullability -- corrupting output that DOES reach the
// generated .d.ts, not just orphaning invisible nested-type data as the
// original "nested types are moot" reasoning assumed.
//
// AssemblyLoader filters nested types out entirely (t.IsNested), so
// "Inner" below never reaches the IR/output either way -- the only
// observable signal here is whether Outer.Name keeps its own (nullable)
// annotation or wrongly ends up matching Inner's (not nullable) one.

type
  Outer = public class
  public
    // Outer's own declaration comes FIRST in the token stream -- this
    // ordering matters. ScanMemberDecl overwrites unconditionally, so
    // whichever declaration the scanner walks LAST wins the dictionary
    // key; putting Inner's (misattributed, pre-fix) write after Outer's
    // own is what makes the corruption actually observable here.
    property Name: nullable String read write;

    type
      Inner = public class
      public
        property Name: not nullable String read write := '';
      end;
  end;

end.
