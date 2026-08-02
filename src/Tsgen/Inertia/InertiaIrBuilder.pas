namespace Tsgen.Inertia;

uses
  System.Collections.Generic,
  System.Text,
  Tsgen.Loading,
  Tsgen.Nrt,
  Tsgen.Ir;

type
  {
    Entry-point-driven IR construction (docs/DESIGN.md §3.5, spiked in
    HANDOFF.md §22, implemented per §24). Unlike Tsgen.Ir.IrBuilder.Build
    (which converts every type in the assembly), this only includes: one
    synthesized interface per Inertia.Render call site found by
    InertiaScanner, plus the transitive closure of the target assembly's
    OWN types actually referenced (directly or via generic arguments/
    arrays) from those pages' fields -- reusing IrBuilder.BuildType for
    the per-type conversion so NRT resolution and everything else stays
    identical to the whole-assembly path.
  }
  InertiaIrBuilder = public static class
  private
    {
      Walks a RawTypeRef (unwrapping arrays/generic arguments) and, for
      any leaf that names one of the target assembly's own types not
      already in aReachable, adds it and enqueues it for the BFS in
      Build to walk its own members in turn.
    }
    class method CollectReferencedTypes(aTypeRef: RawTypeRef; aByFullName: Dictionary<String, RawType>;
                                         aReachable: HashSet<String>; aQueue: Queue<String>);
    begin
      if aTypeRef = nil then exit;

      if aTypeRef.IsArray then begin
        CollectReferencedTypes(aTypeRef.ElementType, aByFullName, aReachable, aQueue);
        exit;
      end;

      if aTypeRef.TypeArguments.Count > 0 then begin
        for each argRef in aTypeRef.TypeArguments do
          CollectReferencedTypes(argRef, aByFullName, aReachable, aQueue);
        exit;
      end;

      if aByFullName.ContainsKey(aTypeRef.FullName) and (not aReachable.Contains(aTypeRef.FullName)) then begin
        aReachable.Add(aTypeRef.FullName);
        aQueue.Enqueue(aTypeRef.FullName);
      end;
    end;

    {
      Page Props interface names are docs/DESIGN.md §7.4's still-open
      "exact naming/output-file convention is TBD" -- this is one
      reasonable v1 choice, not a settled decision: take the last
      "/"-separated segment of the component name (Inertia component
      names are commonly path-like, e.g. "pages/Profile"; the segment
      after the last slash is usually the unique, meaningful part), strip
      anything that isn't a letter/digit, and append "Props".
    }
    class method SanitizePropsTypeName(aComponentName: String): String;
    begin
      var name := aComponentName;
      var slashIdx := name.LastIndexOf('/');
      if slashIdx >= 0 then name := name.Substring(slashIdx + 1);

      var sb := new StringBuilder;
      for each ch in name do
        if Char.IsLetterOrDigit(ch) then sb.Append(ch);

      var sanitized := sb.ToString();
      if String.IsNullOrEmpty(sanitized) then sanitized := 'Unnamed';
      result := sanitized + 'Props';
    end;

  public
    class method Build(aRaw: RawAssembly; aPages: List<InertiaPageProps>; aNullability: Dictionary<String, NullabilityKind>): IrAssemblyLite;
    begin
      result := new IrAssemblyLite;
      var providers := IrBuilder.BuildProviders(aNullability);

      var byFullName := new Dictionary<String, RawType>;
      for each rt in aRaw.Types do
        byFullName[rt.FullName] := rt;

      var reachable := new HashSet<String>;
      var queue := new Queue<String>;

      for each page in aPages do
        for each field in page.Fields do
          CollectReferencedTypes(field.TypeRef, byFullName, reachable, queue);

      while queue.Count > 0 do begin
        var fullName := queue.Dequeue();
        var rt := byFullName[fullName];
        if rt.Kind = RawTypeKind.ClassLike then
          for each rm in rt.Members do
            CollectReferencedTypes(rm.TypeRef, byFullName, reachable, queue);
      end;

      {
        Emit in aRaw.Types order (not reachable's own iteration order --
        HashSet iteration order isn't a contract to rely on, same
        rationale as the "order" lists elsewhere in this codebase) so
        output is deterministic across runs.
      }
      for each rt in aRaw.Types do
        if reachable.Contains(rt.FullName) then
          result.Types.Add(IrBuilder.BuildType(rt, providers));

      {
        Synthesized Props interfaces have no real reflected member to
        look up in the NRT scan dictionary (they're assembled from
        source-level indexer assignments, not a real CLR type), so pass
        an empty type-name key -- OxygeneSourceScanProvider naturally
        returns Unknown for a key that can never match anything it
        scanned, and ValueTypeDefaultProvider still correctly resolves
        value-typed/Nullable<T> fields from their TypeRef alone.
      }
      for each page in aPages do begin
        var propsType := new IrTypeLite;
        {
          Always namespace-wrapped, never left at bare top level: DtsEmitter
          only omits the "declare namespace" wrapper for the "no namespace"
          bucket, which would emit a bare top-level "export interface"
          declaration for the Props type -- a bare top-level "export" turns
          the WHOLE .d.ts into an ES module rather than global ambient
          declarations, silently changing how every other namespace in the
          same file is consumed. "Props" is a placeholder grouping name,
          not a settled convention -- docs/DESIGN.md §7.4's "exact naming/
          output-file convention is TBD" note applies here too.
        }
        propsType.NamespaceName := 'Props';
        propsType.Name := SanitizePropsTypeName(page.ComponentName);
        propsType.Kind := IrTypeKindLite.ClassLike;

        for each field in page.Fields do begin
          var im := new IrMemberLite;
          im.Name := field.Name;
          im.TypeRef := field.TypeRef;
          im.Nullability := NullabilityProviderChain.Resolve(providers, '', field.Name, field.TypeRef);
          propsType.Members.Add(im);
        end;

        result.Types.Add(propsType);
      end;
    end;
  end;

end.
