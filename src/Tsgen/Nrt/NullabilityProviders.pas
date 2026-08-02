namespace Tsgen.Nrt;

uses
  System.Collections.Generic;

type
  {
    Swappable NRT-determination providers, matching docs/DESIGN.md §4.2's
    INullabilityProvider chain design: providers are tried in priority
    order, and the first one returning something other than Unknown wins
    (the same "first match wins" philosophy as the type-mapping chain).
    Adapted to the concrete data this tool actually has today (a type's
    full name, a member name, and its raw CLR type name as a string)
    rather than the design doc's more abstract IrMemberRef/AnalysisContext
    sketch -- there is no reflection-attribute provider wired in yet
    (docs/DESIGN.md §4.2 Provider 2, still genuinely unimplemented,
    post-MVP), so the concrete shape here only needs to carry what
    Provider 1 and Provider 3 actually use.
  }
  INullabilityProvider = public interface
    method TryGetNullability(aTypeFullName: String; aMemberName: String; aClrTypeName: String): NullabilityKind;
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

    method TryGetNullability(aTypeFullName: String; aMemberName: String; aClrTypeName: String): NullabilityKind;
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
    all" case, matching C#'s own default. The known-type-name set
    intentionally mirrors Tsgen.Ir.TypeMapper's set, kept as a separate
    list rather than a shared call to avoid a Tsgen.Ir <-> Tsgen.Nrt
    circular unit reference (Tsgen.Ir already depends on Tsgen.Nrt
    one-way) -- keep both lists in sync if either changes.
  }
  ValueTypeDefaultProvider = public class(INullabilityProvider)
  public
    method TryGetNullability(aTypeFullName: String; aMemberName: String; aClrTypeName: String): NullabilityKind;
    begin
      if IsKnownValueType(aClrTypeName) then
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
        (aClrTypeName = 'System.Guid');
    end;
  end;

  {
    Resolves a member's nullability by trying each provider in order and
    stopping at the first non-Unknown answer.
  }
  NullabilityProviderChain = public static class
  public
    class method Resolve(aProviders: List<INullabilityProvider>; aTypeFullName: String; aMemberName: String; aClrTypeName: String): NullabilityKind;
    begin
      result := NullabilityKind.Unknown;
      for each provider in aProviders do begin
        var kind := provider.TryGetNullability(aTypeFullName, aMemberName, aClrTypeName);
        if kind <> NullabilityKind.Unknown then begin
          result := kind;
          exit;
        end;
      end;
    end;
  end;

end.
