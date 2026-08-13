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
    class method SanitizeComponentBaseName(aComponentName: String): String;
    begin
      var name := aComponentName;
      var slashIdx := name.LastIndexOf('/');
      if slashIdx >= 0 then name := name.Substring(slashIdx + 1);

      var sb := new StringBuilder;
      for each ch in name do
        if Char.IsLetterOrDigit(ch) then sb.Append(ch);

      var sanitized := sb.ToString();
      if String.IsNullOrEmpty(sanitized) then sanitized := 'Unnamed';
      result := sanitized;
    end;

    class method SanitizePropsTypeName(aComponentName: String): String;
    begin
      result := SanitizeComponentBaseName(aComponentName) + 'Props';
    end;

    {
      docs/DESIGN.md §5.4 / §2.6 item 3: field names for the useForm()
      error shape are sourced from the same field discovery as the
      corresponding Page Props type (not a separate DTO scan -- see
      HANDOFF.md for the scope decision), so the name is just the same
      base name with a different suffix, keeping the two types visibly
      paired (e.g. "ProfileProps" / "ProfileFormErrors").
    }
    class method SanitizeFormErrorsTypeName(aComponentName: String): String;
    begin
      result := SanitizeComponentBaseName(aComponentName) + 'FormErrors';
    end;

    class method MakeSimpleTypeRef(aFullName: String): RawTypeRef;
    begin
      result := new RawTypeRef;
      result.FullName := aFullName;
    end;

    {
      Nullability for one synthesized props/shared-data field.

      An explicit source annotation wins outright over the provider
      chain, and that ordering is not a new policy -- it is the same one
      real type members already follow, reached by the only route
      available here. For a reflected member, an explicit "nullable"/
      "not nullable" reaches Provider 1 (OxygeneSourceScanProvider) and
      short-circuits the chain before ValueTypeDefaultProvider or
      --nrt-unknown-policy ever see it. A props field cannot use that
      route at all: it is synthesized from indexer assignments rather
      than reflected, so there is no declaring type name to key the scan
      dictionary on, and the empty string passed below can never match
      anything the scan recorded. Applying InertiaScanner's own captured
      annotation here is what restores Provider 1's role for these
      fields (HANDOFF.md §40). --nrt-unknown-policy is untouched by
      this: it only ever decided what an UNKNOWN field renders as, and
      an annotated field is not unknown.
    }
    class method ResolveFieldNullability(aProviders: List<INullabilityProvider>; aField: InertiaPropsField): NullabilityKind;
    begin
      if aField.ExplicitNullability <> NullabilityKind.Unknown then
        result := aField.ExplicitNullability
      else
        result := NullabilityProviderChain.Resolve(aProviders, '', aField.Name, aField.TypeRef);
    end;

    class method MakeStringToStringDictionaryTypeRef: RawTypeRef;
    begin
      result := new RawTypeRef;
      result.FullName := 'System.Collections.Generic.Dictionary`2';
      result.TypeArguments.Add(MakeSimpleTypeRef('System.String'));
      result.TypeArguments.Add(MakeSimpleTypeRef('System.String'));
    end;

  public
    class method Build(aRaw: RawAssembly; aPages: List<InertiaPageProps>; aSharedData: InertiaSharedData;
                        aNullability: Dictionary<String, NullabilityKind>): IrAssemblyLite;
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
      for each field in aSharedData.Fields do
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
        docs/DESIGN.md §2.6 item 2 / §8.2 (spiked before implementation,
        see HANDOFF.md §27): "flash"/"timestamp"/"errors" are injected
        into every page's payload by InertiaNetCore's own
        Response.GetFinalProps regardless of whether the app registers
        any AddInertiaSharedData(...) middleware -- confirmed against
        InertiaNetCore's own source in the spike, not assumed. Always
        emitted for this reason, never gated behind whether a
        registration was actually found. User-registered fields
        (aSharedData.Fields, populated only from AddInertiaSharedData(...)
        call sites -- a bare Inertia.Share(...) call is deliberately NOT
        classified as shared data, see InertiaScanner.ParseShareCallExcluded)
        are appended after the three framework-injected ones.

        These three Names are set to their real wire form directly and
        are unaffected by --naming-policy either way (Fable5 review
        question, HANDOFF.md §29/§30) -- not by oversight, but because
        neither naming-policy value changes them: "as-written" has no
        Oxygene source declaration to preserve the casing OF (these
        fields are synthetic, not scanned), and DtsEmitter's camelCase
        transform lowercases only a leading uppercase run, which is a
        no-op on an already-all-lowercase single word like "flash" --
        true for any realistic JsonSerializerOptions.DictionaryKeyPolicy
        an app might actually configure (None or CamelCase both leave
        these three exact literal strings unchanged; only a policy that
        uppercases already-lowercase keys, which no built-in
        JsonNamingPolicy does, would disagree).
      }
      var sharedType := new IrTypeLite;
      sharedType.NamespaceName := 'Props';
      sharedType.Name := 'SharedData';
      sharedType.Kind := IrTypeKindLite.ClassLike;

      var flashMember := new IrMemberLite;
      flashMember.Name := 'flash';
      flashMember.TypeRef := MakeStringToStringDictionaryTypeRef();
      flashMember.Nullability := NullabilityKind.IsNotNullable;
      sharedType.Members.Add(flashMember);

      var timestampMember := new IrMemberLite;
      timestampMember.Name := 'timestamp';
      timestampMember.TypeRef := MakeSimpleTypeRef('System.DateTime');
      timestampMember.Nullability := NullabilityKind.IsNotNullable;
      sharedType.Members.Add(timestampMember);

      {
        Known, unreconciled type-representation tension (Fable5 review,
        HANDOFF.md §29/§30): this `errors` member and the per-page
        `XxxFormErrors` type (§26) both describe the same runtime
        payload key (InertiaNetCore's `AddErrors(...)`, read by the
        frontend's `useForm()` hook), but as two different, incompatible
        shapes -- `Record<string, string>` here (any key) vs.
        `Partial<Record<'field1' | 'field2', string>>` there (only that
        page's own Props field names). Not unified: `SharedData` is one
        interface shared by every page, while `XxxFormErrors` is
        page-specific, and `Record<string, string>`'s implicit index
        signature isn't cleanly narrowable to a fixed-key `Partial<Record<...>>`
        as a TypeScript interface-member override. Left as an open
        question for a future pass rather than guessed at under a commit
        deadline.
      }
      var errorsMember := new IrMemberLite;
      errorsMember.Name := 'errors';
      errorsMember.TypeRef := MakeStringToStringDictionaryTypeRef();
      errorsMember.Nullability := NullabilityKind.IsNotNullable;
      sharedType.Members.Add(errorsMember);

      for each field in aSharedData.Fields do begin
        var sm := new IrMemberLite;
        sm.Name := field.Name;
        sm.TypeRef := field.TypeRef;
        sm.Nullability := ResolveFieldNullability(providers, field);
        sharedType.Members.Add(sm);
      end;

      result.Types.Add(sharedType);

      {
        Synthesized Props interfaces have no real reflected member to
        look up in the NRT scan dictionary (they're assembled from
        source-level indexer assignments, not a real CLR type), so the
        empty type-name key ResolveFieldNullability passes down means
        OxygeneSourceScanProvider naturally returns Unknown for a key
        that can never match anything it scanned, while
        ValueTypeDefaultProvider still correctly resolves value-typed/
        Nullable<T> fields from their TypeRef alone. An explicit source
        annotation is applied ahead of that chain -- see
        ResolveFieldNullability for why that is the same ordering real
        members already get, not a special case.
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
        {
          Fully qualified even though SharedData lives in the same
          "Props" namespace, matching TypeMapper's own "always fully
          namespace-qualified" convention for cross-references (see its
          doc comment) rather than special-casing "same namespace as the
          reference site".
        }
        propsType.BaseTypeNames.Add('Props.SharedData');

        for each field in page.Fields do begin
          var im := new IrMemberLite;
          im.Name := field.Name;
          im.TypeRef := field.TypeRef;
          im.Nullability := ResolveFieldNullability(providers, field);
          propsType.Members.Add(im);
        end;

        result.Types.Add(propsType);

        {
          docs/DESIGN.md §2.6 item 3 / §5.4: one Partial<Record<...,
          string>> form-error-shape type per page, reusing the exact same
          field-name list as the Props type above (not a separate DTO
          scan -- see the scope decision in HANDOFF.md). TypeRef/
          Nullability aren't meaningful for this kind, so only Name is
          set on each member; DtsEmitter.EmitType ignores the rest for
          IrTypeKindLite.FormErrorsLike.
        }
        var formErrorsType := new IrTypeLite;
        formErrorsType.NamespaceName := 'Props';
        formErrorsType.Name := SanitizeFormErrorsTypeName(page.ComponentName);
        formErrorsType.Kind := IrTypeKindLite.FormErrorsLike;

        for each field in page.Fields do begin
          var im := new IrMemberLite;
          im.Name := field.Name;
          formErrorsType.Members.Add(im);
        end;

        result.Types.Add(formErrorsType);
      end;
    end;
  end;

end.
