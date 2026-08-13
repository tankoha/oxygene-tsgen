namespace Tsgen.Loading;

uses
  System.Collections.Generic,
  System.IO,
  System.Reflection,
  System.Runtime.InteropServices,
  System.Text.Json,
  Tsgen.Diagnostics;

type
  {
    One <name, version> pair read from a target assembly's own
    "<assembly>.runtimeconfig.json" (only executables get one -- library
    fixtures like tests/fixtures/*/*.dll legitimately have none, which is
    not an error, see ParseRuntimeConfigFrameworks). Kept as a small class
    rather than System.Tuple<String, String> to keep field names
    self-documenting at call sites (FrameworkVersion, not Item2).
  }
  RuntimeConfigFramework = public class
  public
    Name: String;
    FrameworkVersion: String;
  end;

  AssemblyLoader = public static class
  private
    const DotnetSharedRoot = 'C:\Program Files\dotnet\shared';

    {
      Recursively builds a RawTypeRef from a System.Type, using
      GetElementType()/GetGenericArguments() directly rather than
      string-parsing the mangled, assembly-qualified FullName a closed
      generic type reports (e.g. "List`1[[Foo, MyAsm, Version=...]]").
      Note this is about a MEMBER's type being a closed generic
      instantiation (List<Foo>, Nullable<Int32>, ...) -- unrelated to the
      "for each t in asm.GetTypes() ... t.IsGenericType" skip below, which
      is about the target assembly declaring its OWN open generic types
      (e.g. "class TreeNode<T>"), still out of scope.
    }
    class method BuildTypeRef(aType: &Type): RawTypeRef;
    begin
      result := new RawTypeRef;
      if aType.IsArray then begin
        result.IsArray := true;
        result.ElementType := BuildTypeRef(aType.GetElementType());
      end
      else if aType.IsGenericType then begin
        result.FullName := aType.GetGenericTypeDefinition().FullName;
        for each argType in aType.GetGenericArguments() do
          result.TypeArguments.Add(BuildTypeRef(argType));
      end
      else begin
        result.FullName := aType.FullName;
        result.IsEnum := aType.IsEnum;
        // HANDOFF.md §35 follow-up: same "wide" definition IsEnum already
        // uses (a BCL enum reports IsEnum too, not just a target-assembly
        // one). This also marks BCL structs (DateTime/Decimal/...) true,
        // but those already resolve non-null via
        // ValueTypeDefaultProvider.IsKnownValueType, so behavior for them
        // is unchanged. A BCL struct NOT on that list (e.g. TimeSpan) now
        // goes Unknown -> non-null instead, which is more correct, not
        // less: a non-Nullable<T> value type can never be null in the
        // serialized JSON either way.
        result.IsStruct := aType.IsValueType and (not aType.IsEnum) and (not aType.IsPrimitive);
      end;
    end;

    {
      Registers aFilePath under its bare file name (case-insensitive) in
      aPaths, unless a path with that same file name was already
      registered -- first-registered wins. Callers add paths in priority
      order (target assembly > its own folder > shared frameworks > the
      hosting runtime's own directory) so a higher-priority source is
      never silently overwritten by a lower-priority one carrying a
      same-named DLL.
    }
    class method AddResolverFile(aPaths: Dictionary<String, String>; aFilePath: String);
    begin
      var key := Path.GetFileName(aFilePath).ToLowerInvariant();
      if not aPaths.ContainsKey(key) then
        aPaths[key] := aFilePath;
    end;

    class method AddResolverDir(aPaths: Dictionary<String, String>; aDir: String);
    begin
      if String.IsNullOrEmpty(aDir) or (not Directory.Exists(aDir)) then exit;
      for each f in Directory.GetFiles(aDir, '*.dll') do
        AddResolverFile(aPaths, f);
    end;

    class method AddFrameworkFromJson(aElement: JsonElement; aList: List<RuntimeConfigFramework>);
    begin
      var nameEl: JsonElement;
      var verEl: JsonElement;
      if aElement.TryGetProperty('name', out nameEl) and aElement.TryGetProperty('version', out verEl) then begin
        var fw := new RuntimeConfigFramework;
        fw.Name := nameEl.GetString();
        fw.FrameworkVersion := verEl.GetString();
        aList.Add(fw);
      end;
    end;

    {
      Reads "runtimeOptions.framework" (single) and/or
      "runtimeOptions.frameworks" (array -- used when an app references
      more than one shared framework) from a "<assembly>.runtimeconfig.json"
      sitting next to the target assembly. Returns an empty list -- not an
      error -- when the file doesn't exist at all (library-only assemblies,
      including every current test fixture, have no runtimeconfig.json;
      only executables get one) or fails to parse (malformed/unexpected
      shape), so this can never be the thing that crashes Load.
    }
    class method ParseRuntimeConfigFrameworks(aRuntimeConfigPath: String; aDiagnostics: DiagnosticList): List<RuntimeConfigFramework>;
    begin
      result := new List<RuntimeConfigFramework>;
      if not File.Exists(aRuntimeConfigPath) then exit;

      try
        var text := File.ReadAllText(aRuntimeConfigPath);
        using doc := JsonDocument.Parse(text) do begin
          var root := doc.RootElement;
          var runtimeOptions: JsonElement;
          if not root.TryGetProperty('runtimeOptions', out runtimeOptions) then exit;

          var singleFramework: JsonElement;
          if runtimeOptions.TryGetProperty('framework', out singleFramework) then
            AddFrameworkFromJson(singleFramework, result);

          var frameworksArray: JsonElement;
          if runtimeOptions.TryGetProperty('frameworks', out frameworksArray) and (frameworksArray.ValueKind = JsonValueKind.Array) then
            for each item in frameworksArray.EnumerateArray() do
              AddFrameworkFromJson(item, result);
        end;
      except
        on E: Exception do
          aDiagnostics.AddWarning('could not parse "' + aRuntimeConfigPath + '" for shared-framework resolution: ' + E.Message + ' -- continuing without it.');
      end;
    end;

    {
      Picks the shared-framework version directory under aFrameworkRoot
      whose major version matches aWantedVersion, preferring the highest
      such version when the exact version isn't installed locally (e.g.
      the target app was built against 10.0.10 but only 10.0.9 is
      installed on this machine). Returns nil if aWantedVersion doesn't
      parse or no directory shares its major version.
    }
    class method PickBestFrameworkVersionDir(aFrameworkRoot: String; aWantedVersion: String): String;
    begin
      result := nil;
      var wantedVer: Version := nil;
      if not Version.TryParse(aWantedVersion, out wantedVer) then exit;

      var bestVer: Version := nil;
      var bestDir: String := nil;
      for each dir in Directory.GetDirectories(aFrameworkRoot) do begin
        var dirVer: Version := nil;
        if not Version.TryParse(Path.GetFileName(dir), out dirVer) then continue;
        if dirVer.Major <> wantedVer.Major then continue;
        if (bestVer = nil) or (dirVer > bestVer) then begin
          bestVer := dirVer;
          bestDir := dir;
        end;
      end;
      result := bestDir;
    end;

    {
      Adds every *.dll under the resolved shared-framework directory for
      (aFrameworkName, aFrameworkVersion) -- e.g. "Microsoft.AspNetCore.App"
      10.0.10 -> "C:\Program Files\dotnet\shared\Microsoft.AspNetCore.App\10.0.10\*.dll"
      -- to aPaths. Falls back to the highest installed same-major-version
      directory when the exact version isn't present (common on a dev
      machine that's been patched since the app was last built), and warns
      via aDiagnostics rather than throwing when neither the framework nor
      any same-major fallback can be found; the caller still proceeds
      (missing types now fail individually, per-type, in the Load loop's
      own try/except, instead of one missing framework crashing everything
      up front).
    }
    class method AddFrameworkResolverPaths(aPaths: Dictionary<String, String>; aFrameworkName: String; aFrameworkVersion: String; aDiagnostics: DiagnosticList);
    begin
      var frameworkRoot := Path.Combine(DotnetSharedRoot, aFrameworkName);
      if not Directory.Exists(frameworkRoot) then begin
        aDiagnostics.AddWarning('could not resolve shared framework "' + aFrameworkName + '": no such directory under "' + DotnetSharedRoot + '" -- types depending on it will be skipped.');
        exit;
      end;

      var versionDir := Path.Combine(frameworkRoot, aFrameworkVersion);
      if not Directory.Exists(versionDir) then begin
        var fallbackDir := PickBestFrameworkVersionDir(frameworkRoot, aFrameworkVersion);
        if fallbackDir = nil then begin
          aDiagnostics.AddWarning('could not resolve shared framework "' + aFrameworkName + '" version ' + aFrameworkVersion + ' (no same-major-version fallback installed under "' + frameworkRoot + '") -- types depending on it will be skipped.');
          exit;
        end;
        aDiagnostics.AddWarning('shared framework "' + aFrameworkName + '" ' + aFrameworkVersion + ' is not installed; falling back to ' + Path.GetFileName(fallbackDir) + '.');
        versionDir := fallbackDir;
      end;

      AddResolverDir(aPaths, versionDir);
    end;

  public
    class method Load(aAssemblyPath: String; aDiagnostics: DiagnosticList): RawAssembly;
    begin
      var fullPath := Path.GetFullPath(aAssemblyPath);
      var assemblyDir := Path.GetDirectoryName(fullPath);

      {
        Resolver search paths, in priority order (first-registered wins,
        see AddResolverFile): the target assembly itself, every other DLL
        sitting next to it (e.g. InertiaNetCore.dll copy-located beside
        the app's own assembly -- never discoverable before this fix,
        M3-dts-validation.md §3.1), each shared framework the target
        declares via its own runtimeconfig.json (e.g.
        Microsoft.AspNetCore.App -- also never discoverable before this
        fix, same report), and finally the .NET runtime directory hosting
        tsgen.exe itself (the original, pre-fix behavior, kept as a
        last-resort fallback for base BCL types).
      }
      var pathsByFileName := new Dictionary<String, String>;
      AddResolverFile(pathsByFileName, fullPath);
      AddResolverDir(pathsByFileName, assemblyDir);

      var runtimeConfigPath := Path.Combine(assemblyDir, Path.GetFileNameWithoutExtension(fullPath) + '.runtimeconfig.json');
      for each fw in ParseRuntimeConfigFrameworks(runtimeConfigPath, aDiagnostics) do
        AddFrameworkResolverPaths(pathsByFileName, fw.Name, fw.FrameworkVersion, aDiagnostics);

      var runtimeDir := RuntimeEnvironment.GetRuntimeDirectory();
      AddResolverDir(pathsByFileName, runtimeDir);

      var resolverPaths := new List<String>(pathsByFileName.Values);
      var resolver := new PathAssemblyResolver(resolverPaths);
      using mlc := new MetadataLoadContext(resolver) do begin
        var asm := mlc.LoadFromAssemblyPath(fullPath);
        result := new RawAssembly;
        var skippedCount: Int32 := 0;
        var failedCount: Int32 := 0;

        for each t in asm.GetTypes() do begin
          {
            Type-unit try/except (docs/DESIGN.md's "Pipeline stages report
            problems via Tsgen.Diagnostics" rule, CLAUDE.md): a single
            type's base-type/property/field resolution can throw
            FileNotFoundException deep inside System.Reflection.TypeLoading
            when some dependency assembly still isn't resolvable even
            after the resolver-path additions above (e.g. a third-party
            NuGet package this tool has no way to locate) -- that must
            skip only this one type, not crash the whole process
            (M3-dts-validation.md §3.1's root cause: this loop previously
            had no per-type guard at all).
          }
          var typeLabel := '(name unavailable)';
          try
            typeLabel := t.FullName;

            {
              A struct (Oxygene "record", docs/DESIGN.md §7 task 2,
              HANDOFF.md §35) is t.IsValueType and neither an enum nor a
              CLR-primitive (Int32/Boolean/... -- t.IsPrimitive is exactly
              .NET's own small fixed set of built-in value types; asm.GetTypes()
              only ever returns types the TARGET assembly itself declares,
              so this can never accidentally admit a BCL struct like
              System.DateTime -- those belong to a different assembly and
              never appear in this loop at all). Treated identically to a
              class from here on (RawTypeKind.ClassLike, same property/
              field reflection below) -- a struct's public instance
              properties/fields are read the exact same way as a class's.
            }
            var isStruct := t.IsValueType and (not t.IsEnum) and (not t.IsPrimitive);

            if (not t.IsPublic) or t.IsNested or t.IsGenericType or (not (t.IsClass or t.IsEnum or isStruct)) then begin
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
              rt.IsStruct := isStruct;

              for each p in t.GetProperties(BindingFlags.Public or BindingFlags.Instance) do begin
                var m := new RawMember;
                m.Name := p.Name;
                m.Kind := RawMemberKind.PropertyMember;
                m.TypeRef := BuildTypeRef(p.PropertyType);
                rt.Members.Add(m);
              end;

              for each fi in t.GetFields(BindingFlags.Public or BindingFlags.Instance) do begin
                var m := new RawMember;
                m.Name := fi.Name;
                m.Kind := RawMemberKind.Field;
                m.TypeRef := BuildTypeRef(fi.FieldType);
                rt.Members.Add(m);
              end;
            end;

            result.Types.Add(rt);
          except
            on E: Exception do begin
              inc(failedCount);
              aDiagnostics.AddWarning('skipped type "' + typeLabel + '": failed to resolve, likely an unresolvable dependency assembly (' + E.GetType().Name + ': ' + E.Message + ') -- its members will not appear in the output.');
            end;
          end;
        end;

        if skippedCount > 0 then
          aDiagnostics.AddWarning('skipped ' + skippedCount.ToString() + ' non-public/nested/generic/unsupported-kind type(s); their members will not appear in the output.');
        if failedCount > 0 then
          aDiagnostics.AddWarning('failed to resolve ' + failedCount.ToString() + ' type(s) due to unresolvable dependencies; see the individual warnings above for which ones.');
      end;
    end;
  end;

end.
