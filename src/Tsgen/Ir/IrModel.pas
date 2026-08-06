namespace Tsgen.Ir;

uses
  System.Collections.Generic,
  Tsgen.Loading,
  Tsgen.Nrt;

type
  {
    TypeRef + Nullability are carried through unresolved -- mapping to
    a TS type string and applying --nrt-unknown-policy both happen in
    Stage 4 (DtsEmitter), not here. An earlier version of this IR stored a
    pre-mapped TsType:String and a pre-resolved IsNullable:Boolean
    directly, which quietly folded Stage 3 into Stage 2 and destroyed the
    "explicitly annotated vs. Unknown+policy" distinction needed for
    docs/DESIGN.md §4.3's mark-unknown policy. Keeping the raw
    Tsgen.Loading.RawTypeRef and the tri-state NullabilityKind here
    instead keeps that information available to whichever emitter/policy
    needs it. Reusing RawTypeRef directly (rather than a parallel
    "IrTypeRef") matches the same reuse-not-duplicate pattern already
    used for NullabilityKind.
  }
  IrMemberLite = public class
  public
    Name: String;
    TypeRef: RawTypeRef;
    Nullability: NullabilityKind;
  end;

  IrEnumValueLite = public class
  public
    Name: String;
    NumericValue: Int64;
  end;

  {
    FormErrorsLike reuses Members for its field-name list only (Name is
    read, TypeRef/Nullability are ignored) -- see DtsEmitter.EmitType,
    which renders it as `Partial<Record<'field1' | 'field2', string>>`
    rather than an interface. Kept as a third IrTypeLite kind instead of a
    parallel type so InertiaIrBuilder can build it with the exact same
    Members list already assembled for the paired Props type (docs/
    DESIGN.md §5.4).
  }
  IrTypeKindLite = public enum (ClassLike, EnumLike, FormErrorsLike);

  IrTypeLite = public class
  public
    NamespaceName: String;
    Name: String;
    Kind: IrTypeKindLite;
    Members: List<IrMemberLite> := new List<IrMemberLite>;
    EnumValues: List<IrEnumValueLite> := new List<IrEnumValueLite>;
    {
      Only meaningful for ClassLike -- fully-qualified names (e.g.
      "Props.SharedData") this interface should `extends`. Empty for
      every existing type; introduced for the Inertia Shared Data
      feature so each page's Props interface can extend a shared
      "SharedData" interface instead of duplicating its members
      (docs/DESIGN.md §2.6 item 2, HANDOFF.md §27).
    }
    BaseTypeNames: List<String> := new List<String>;
  end;

  IrAssemblyLite = public class
  public
    Types: List<IrTypeLite> := new List<IrTypeLite>;
  end;

end.
