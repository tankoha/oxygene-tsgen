namespace Tsgen.Ir;

uses
  System.Collections.Generic,
  Tsgen.Loading,
  Tsgen.Nrt;

type
  NrtUnknownPolicy = public enum (TreatAsNullable, TreatAsNonNull);

  {
    Merges the raw reflection model with the NRT scan results only --
    does not resolve TS type names or apply --nrt-unknown-policy. Both of
    those are Stage 3/4 concerns and happen in DtsEmitter instead, so the
    IR keeps the "explicitly annotated vs. Unknown" distinction intact for
    whichever emitter/policy consumes it (see IrModel.pas).
  }
  IrBuilder = public static class
  public
    class method Build(aRaw: RawAssembly; aNullability: Dictionary<String, NullabilityKind>): IrAssemblyLite;
    begin
      result := new IrAssemblyLite;

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

            var lookupKey := rt.FullName + '.' + rm.Name;
            var kind := NullabilityKind.Unknown;
            if aNullability.ContainsKey(lookupKey) then
              kind := aNullability[lookupKey];
            im.Nullability := kind;

            it.Members.Add(im);
          end;
        end;

        result.Types.Add(it);
      end;
    end;
  end;

end.
