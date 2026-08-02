namespace Tsgen.Loading;

uses
  System.Collections.Generic,
  System.IO,
  System.Reflection,
  System.Runtime.InteropServices,
  Tsgen.Diagnostics;

type
  AssemblyLoader = public static class
  public
    class method Load(aAssemblyPath: String; aDiagnostics: DiagnosticList): RawAssembly;
    begin
      var fullPath := Path.GetFullPath(aAssemblyPath);
      var runtimeDir := RuntimeEnvironment.GetRuntimeDirectory();
      var resolverPaths := new List<String>(Directory.GetFiles(runtimeDir, '*.dll'));
      resolverPaths.Add(fullPath);

      var resolver := new PathAssemblyResolver(resolverPaths);
      using mlc := new MetadataLoadContext(resolver) do begin
        var asm := mlc.LoadFromAssemblyPath(fullPath);
        result := new RawAssembly;
        var skippedCount: Int32 := 0;

        for each t in asm.GetTypes() do begin
          if (not t.IsPublic) or t.IsNested or t.IsGenericType or (not (t.IsClass or t.IsEnum)) then begin
            inc(skippedCount);
            continue;
          end;

          var rt := new RawType;
          rt.FullName := t.FullName;
          rt.NamespaceName := t.Namespace;
          rt.Name := t.Name;

          if t.IsEnum then begin
            rt.Kind := RawTypeKind.Enum;
            for each f in t.GetFields(BindingFlags.Public or BindingFlags.Static) do begin
              var ev := new RawEnumValue;
              ev.Name := f.Name;
              ev.Value := Convert.ToInt64(f.GetRawConstantValue());
              rt.EnumValues.Add(ev);
            end;
          end
          else begin
            rt.Kind := RawTypeKind.ClassLike;

            for each p in t.GetProperties(BindingFlags.Public or BindingFlags.Instance) do begin
              var m := new RawMember;
              m.Name := p.Name;
              m.Kind := RawMemberKind.PropertyMember;
              m.ClrTypeName := p.PropertyType.FullName;
              rt.Members.Add(m);
            end;

            for each fi in t.GetFields(BindingFlags.Public or BindingFlags.Instance) do begin
              var m := new RawMember;
              m.Name := fi.Name;
              m.Kind := RawMemberKind.Field;
              m.ClrTypeName := fi.FieldType.FullName;
              rt.Members.Add(m);
            end;
          end;

          result.Types.Add(rt);
        end;

        if skippedCount > 0 then
          aDiagnostics.AddWarning('skipped ' + skippedCount.ToString() + ' non-public/nested/generic/unsupported-kind type(s); their members will not appear in the output.');
      end;
    end;
  end;

end.
