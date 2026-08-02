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
    class method Build(aRaw: RawAssembly; aNullability: Dictionary<String, NullabilityKind>): IrAssemblyLite;
    begin
      result := new IrAssemblyLite;

      var providers := new List<INullabilityProvider>;
      providers.Add(new OxygeneSourceScanProvider(aNullability));
      providers.Add(new ValueTypeDefaultProvider);

      for each rt in aRaw.Types do begin
        var it := new IrTypeLite;
        it.NamespaceName := rt.NamespaceName;
        it.Name := rt.Name;

        if rt.Kind = RawTypeKind.Enum then begin
          it.Kind := IrTypeKindLite.EnumLike;
          for each rev in rt.EnumValues do begin
            var iev := new IrEnumValueLite;
            iev.Name := rev.Name;
            iev.NumericValue := rev.Value;
            it.EnumValues.Add(iev);
          end;
        end
        else begin
          it.Kind := IrTypeKindLite.ClassLike;
          for each rm in rt.Members do begin
            var im := new IrMemberLite;
            im.Name := rm.Name;
            im.ClrTypeName := rm.ClrTypeName;
            im.Nullability := NullabilityProviderChain.Resolve(providers, rt.FullName, rm.Name, rm.ClrTypeName);
            it.Members.Add(im);
          end;
        end;

        result.Types.Add(it);
      end;
    end;
  end;

end.
