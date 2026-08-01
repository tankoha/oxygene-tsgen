namespace Tsgen.Ir;

uses
  System.Collections.Generic,
  Tsgen.Nrt;

type
  {
    ClrTypeName + Nullability are carried through unresolved -- mapping to
    a TS type string and applying --nrt-unknown-policy both happen in
    Stage 4 (DtsEmitter), not here. An earlier version of this IR stored a
    pre-mapped TsType:String and a pre-resolved IsNullable:Boolean
    directly, which quietly folded Stage 3 into Stage 2 and destroyed the
    "explicitly annotated vs. Unknown+policy" distinction needed for
    docs/DESIGN.md §4.3's mark-unknown policy. Keeping the raw CLR type
    name and the tri-state NullabilityKind here instead keeps that
    information available to whichever emitter/policy needs it.
  }
  IrMemberLite = public class
  public
    Name: String;
    ClrTypeName: String;
    Nullability: NullabilityKind;
  end;

  IrEnumValueLite = public class
  public
    Name: String;
    NumericValue: Int64;
  end;

  IrTypeKindLite = public enum (ClassLike, EnumLike);

  IrTypeLite = public class
  public
    NamespaceName: String;
    Name: String;
    Kind: IrTypeKindLite;
    Members: List<IrMemberLite> := new List<IrMemberLite>;
    EnumValues: List<IrEnumValueLite> := new List<IrEnumValueLite>;
  end;

  IrAssemblyLite = public class
  public
    Types: List<IrTypeLite> := new List<IrTypeLite>;
  end;

end.
