namespace Tsgen.Ir;

uses
  System.Collections.Generic,
  Tsgen.Loading,
  Tsgen.Nrt;

type
  NrtUnknownPolicy = public enum (TreatAsNullable, TreatAsNonNull, MarkUnknown);

  {
    Merges the raw reflection model with the NRT scan results only --
    does not resolve TS type names or apply --nrt-unknown-policy. Both of
    those are Stage 3/4 concerns and happen in DtsEmitter instead, so the
    IR keeps the "explicitly annotated vs. Unknown" distinction intact for
    whichever emitter/policy consumes it (see IrModel.pas).

    Nullability is resolved through the INullabilityProvider chain
    (Tsgen.Nrt.NullabilityProviders, docs/DESIGN.md §4.2) rather than a
    direct dictionary lookup: Provider 1 (OxygeneSourceScanProvider) tries
    the source scan's explicit annotations first, and Provider 3
    (ValueTypeDefaultProvider) falls back to "value types are non-nullable
    by default" for anything Provider 1 has no opinion on. Provider 2
    (reflection-attribute-based, for C#/VB dependency assemblies) remains
    unimplemented -- the chain is exactly the two providers that are real.
  }
  IrBuilder = public static class
  public
    {
      Builds the standard two-provider chain (Tsgen.Nrt.NullabilityProviders)
      from a source-scan result dictionary. Exposed separately from Build
      so Tsgen.Inertia.InertiaIrBuilder (entry-point-driven mode,
      HANDOFF.md §24) can reuse the exact same provider setup instead of
      duplicating it.
    }
    class method BuildProviders(aNullability: Dictionary<String, NullabilityKind>): List<INullabilityProvider>;
    begin
      result := new List<INullabilityProvider>;
      result.Add(new OxygeneSourceScanProvider(aNullability));
      result.Add(new ValueTypeDefaultProvider);
    end;

    {
      Converts a single RawType to an IrTypeLite. Exposed separately from
      Build for the same reason as BuildProviders -- InertiaIrBuilder needs
      to convert an arbitrary reachable subset of aRaw.Types, not "all of
      them," but the per-type conversion logic itself (including NRT
      resolution) is identical either way.
    }
    class method BuildType(aRawType: RawType; aProviders: List<INullabilityProvider>): IrTypeLite;
    begin
      result := new IrTypeLite;
      result.NamespaceName := aRawType.NamespaceName;
      result.Name := aRawType.Name;

      if aRawType.Kind = RawTypeKind.Enum then begin
        result.Kind := IrTypeKindLite.EnumLike;
        for each rev in aRawType.EnumValues do begin
          var iev := new IrEnumValueLite;
          iev.Name := rev.Name;
          iev.NumericValue := rev.Value;
          result.EnumValues.Add(iev);
        end;
      end
      else begin
        result.Kind := IrTypeKindLite.ClassLike;
        for each rm in aRawType.Members do begin
          var im := new IrMemberLite;
          im.Name := rm.Name;
          im.TypeRef := rm.TypeRef;
          im.Nullability := NullabilityProviderChain.Resolve(aProviders, aRawType.FullName, rm.Name, rm.TypeRef);
          result.Members.Add(im);
        end;
      end;
    end;

    class method Build(aRaw: RawAssembly; aNullability: Dictionary<String, NullabilityKind>): IrAssemblyLite;
    begin
      result := new IrAssemblyLite;
      var providers := BuildProviders(aNullability);
      for each rt in aRaw.Types do
        result.Types.Add(BuildType(rt, providers));
    end;
  end;

end.
