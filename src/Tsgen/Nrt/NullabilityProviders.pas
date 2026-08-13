namespace Tsgen.Nrt;

uses
  System.Collections.Generic,
  Tsgen.Loading;

type
  {
    Swappable NRT-determination providers, matching docs/DESIGN.md §4.2's
    INullabilityProvider chain design: providers are tried in priority
    order, and the first one returning something other than Unknown wins
    (the same "first match wins" philosophy as the type-mapping chain).
    Adapted to the concrete data this tool actually has today (a type's
    full name, a member name, and its raw structural type reference)
    rather than the design doc's more abstract IrMemberRef/AnalysisContext
    sketch -- there is no reflection-attribute provider wired in yet
    (docs/DESIGN.md §4.2 Provider 2, still genuinely unimplemented,
    post-MVP), so the concrete shape here only needs to carry what
    Provider 1 and Provider 3 actually use. Takes a Tsgen.Loading.RawTypeRef
    (not just a flat type-name string) so Provider 3 can recognize
    Nullable<T> regardless of what T is -- this needs the structural
    generic-argument info a plain string can't carry.
  }
  INullabilityProvider = public interface
    method TryGetNullability(aTypeFullName: String; aMemberName: String; aTypeRef: RawTypeRef): NullabilityKind;
  end;

  {
    Provider 1 (primary, docs/DESIGN.md §4.2): wraps NullabilityScanner's
    source-scan result dictionary. The only provider that can return
    anything but Unknown for Oxygene-authored code (HANDOFF.md §8.3).
  }
  OxygeneSourceScanProvider = public class(INullabilityProvider)
  private
    fScanResult: Dictionary<String, NullabilityKind>;
  public
    constructor(aScanResult: Dictionary<String, NullabilityKind>);
    begin
      fScanResult := aScanResult;
    end;

    method TryGetNullability(aTypeFullName: String; aMemberName: String; aTypeRef: RawTypeRef): NullabilityKind;
    begin
      var key := aTypeFullName + '.' + aMemberName;
      if fScanResult.ContainsKey(key) then
        result := fScanResult[key]
      else
        result := NullabilityKind.Unknown;
    end;
  end;

  {
    Provider 3 (docs/DESIGN.md §4.2): CLR value types are non-nullable by
    default unless explicitly annotated otherwise -- and if a value-typed
    member WAS explicitly annotated ("nullable Int32"), Provider 1 already
    caught that and this provider never runs (the chain stops at the
    first non-Unknown answer). This only fires for the "no annotation at
    all" case, matching C#'s own default. Also recognizes Nullable<T>
    (Oxygene's "nullable Int32" on a value type compiles to
    System.Nullable`1[[Int32]], confirmed hands-on) as always nullable,
    regardless of T -- Nullable<T> IS the CLR's own "this value type is
    nullable" marker, so no policy judgment is being made here, just
    reading what the type already says. The known-type-name set
    intentionally mirrors Tsgen.Ir.TypeMapper's set, kept as a separate
    list rather than a shared call to avoid a Tsgen.Ir <-> Tsgen.Nrt
    circular unit reference (Tsgen.Ir already depends on Tsgen.Nrt
    one-way) -- keep both lists in sync if either changes. Reference-typed
    generics (List<T>, Dictionary<K,V>, arrays, ...) are deliberately NOT
    touched here -- like any other reference type, "no annotation" means
    Unknown, not an auto-resolved default, so they fall through unchanged.

    Also recognizes aTypeRef.IsEnum (HANDOFF.md §33) and, since §35's
    follow-up, aTypeRef.IsStruct: the target assembly's own enum AND
    struct (Oxygene "record") types are CLR value types too, just like
    Int32/Boolean/etc., but can't be enumerated in IsKnownValueType's
    hardcoded name list up front (their names are whatever the target
    assembly happens to call them). Both flags are propagated from
    Tsgen.Loading.RawType by the same two call sites that build a
    RawTypeRef -- AssemblyLoader.BuildTypeRef (reflection path, from
    System.Type.IsEnum / IsValueType-and-not-enum-and-not-primitive) and
    InertiaScanner.Scan's aKnownTypes construction (source-scan path, from
    RawType.Kind / RawType.IsStruct directly) -- rather than this provider
    trying to look either up itself, keeping it a pure function of the
    RawTypeRef it's handed, same as every other check here.
  }
  ValueTypeDefaultProvider = public class(INullabilityProvider)
  public
    method TryGetNullability(aTypeFullName: String; aMemberName: String; aTypeRef: RawTypeRef): NullabilityKind;
    begin
      if aTypeRef.FullName = 'System.Nullable`1' then
        result := NullabilityKind.IsNullable
      else if IsKnownValueType(aTypeRef.FullName) or aTypeRef.IsEnum or aTypeRef.IsStruct then
        result := NullabilityKind.IsNotNullable
      else
        result := NullabilityKind.Unknown;
    end;

    class method IsKnownValueType(aClrTypeName: String): Boolean;
    begin
      result :=
        (aClrTypeName = 'System.Boolean') or
        (aClrTypeName = 'System.Byte') or (aClrTypeName = 'System.SByte') or
        (aClrTypeName = 'System.Int16') or (aClrTypeName = 'System.UInt16') or
        (aClrTypeName = 'System.Int32') or (aClrTypeName = 'System.UInt32') or
        (aClrTypeName = 'System.Int64') or (aClrTypeName = 'System.UInt64') or
        (aClrTypeName = 'System.Single') or (aClrTypeName = 'System.Double') or (aClrTypeName = 'System.Decimal') or
        (aClrTypeName = 'System.DateTime') or (aClrTypeName = 'System.DateTimeOffset') or
        (aClrTypeName = 'System.DateOnly') or (aClrTypeName = 'System.TimeOnly') or
        (aClrTypeName = 'System.Guid');
    end;
  end;

  {
    Resolves a member's nullability by trying each provider in order and
    stopping at the first non-Unknown answer.
  }
  NullabilityProviderChain = public static class
  public
    class method Resolve(aProviders: List<INullabilityProvider>; aTypeFullName: String; aMemberName: String; aTypeRef: RawTypeRef): NullabilityKind;
    begin
      result := NullabilityKind.Unknown;
      for each provider in aProviders do begin
        var kind := provider.TryGetNullability(aTypeFullName, aMemberName, aTypeRef);
        if kind <> NullabilityKind.Unknown then begin
          result := kind;
          exit;
        end;
      end;
    end;
  end;

end.
