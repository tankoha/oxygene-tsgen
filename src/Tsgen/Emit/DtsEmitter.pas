namespace Tsgen.Emit;

uses
  System.Text,
  System.Collections.Generic,
  Tsgen.Ir,
  Tsgen.Nrt,
  Tsgen.Diagnostics;

type
  EnumStyle = public enum (Numeric, StringUnion);

  {
    docs/DESIGN.md §5.1 always described this as a general "simulate the
    JsonNamingPolicy setting" concern, applicable regardless of --mode --
    it was simply never implemented for either mode until now (found via
    the Inertia Shared Data spike, HANDOFF.md §27/§28: InertiaNetCore's
    default JsonSerializerOptions camelCases both dictionary keys and
    POCO property names, so Page Props output emitted verbatim
    Oxygene-source casing didn't match the real wire payload). Only
    affects object member/property names and FormErrorsLike's Record<>
    key literals -- NOT type names (interface/type identifiers are a
    TypeScript-side choice, not a JSON property) and NOT enum value names
    (System.Text.Json's enum string conversion is controlled separately,
    by JsonStringEnumConverter's own naming policy, not
    PropertyNamingPolicy).
  }
  NamingPolicy = public enum (AsWritten, CamelCase);

  {
    Single-file emitter for the MVP (docs/DESIGN.md §7.3 also describes a
    split-file / ES-module layout, deferred -- see HANDOFF.md §11).

    Also where Stage 3 (type mapping) and --nrt-unknown-policy get
    applied -- the IR carries a raw TypeRef/Nullability so this is the
    first point where a policy choice is actually made.

    Emit is a pure data transform: aAssembly in, the .d.ts string + a
    DiagnosticList out. It never writes to the console directly -- see
    Tsgen.Diagnostics.
  }
  DtsEmitter = public static class
  private
    class method ResolveNullableSuffix(aKind: NullabilityKind; aUnknownPolicy: NrtUnknownPolicy): Boolean;
    begin
      if aKind = NullabilityKind.IsNullable then
        result := true
      else if aKind = NullabilityKind.IsNotNullable then
        result := false
      else // Unknown: MarkUnknown renders bare (see ShouldMarkUnknown for
           // the comment that distinguishes it from a real not-nullable)
        result := (aUnknownPolicy = NrtUnknownPolicy.TreatAsNullable);
    end;

    {
      TypeScript's type system has no way to express "nullability
      undetermined" as a distinct type from a plain, non-nullable one --
      so under MarkUnknown, a genuinely Unknown member renders with the
      same bare type as TreatAsNonNull, plus this trailing comment to
      keep it visually/grep-ably distinct from an explicit `not nullable`.
      Only applies to genuinely Unknown members; explicitly-annotated ones
      never reach here with this true (same rule CLAUDE.md documents for
      why NRT fixtures need a non-null case: policy must only touch
      Unknown, never override an explicit annotation).
    }
    class method ShouldMarkUnknown(aKind: NullabilityKind; aUnknownPolicy: NrtUnknownPolicy): Boolean;
    begin
      result := (aKind = NullabilityKind.Unknown) and (aUnknownPolicy = NrtUnknownPolicy.MarkUnknown);
    end;

    {
      A simplified, ASCII-first-letter-only stand-in for
      System.Text.Json's real JsonNamingPolicy.CamelCase.ConvertName:
      lowercases just the first character. Correct for every ordinary
      PascalCase Oxygene identifier (the common case, and the only shape
      this codebase's own fixtures/DTOs use), but does NOT replicate the
      real algorithm's acronym-run handling (e.g. a property literally
      named "ID" or "URLPath") -- a deliberate, accepted v1 gap rather
      than porting that logic, same risk-tolerance as this codebase's
      other documented heuristic limitations (e.g. InertiaScanner's
      short-name collision note).
    }
    class method ToCamelCase(aName: String): String;
    begin
      if String.IsNullOrEmpty(aName) then
        result := aName
      else
        result := Char.ToLowerInvariant(aName[0]).ToString() + aName.Substring(1);
    end;

    class method ApplyNamingPolicy(aName: String; aNamingPolicy: NamingPolicy): String;
    begin
      if aNamingPolicy = NamingPolicy.CamelCase then
        result := ToCamelCase(aName)
      else
        result := aName;
    end;

    class method EmitType(aSb: StringBuilder; aType: IrTypeLite; aEnumStyle: EnumStyle; aUnknownPolicy: NrtUnknownPolicy;
                           aNamingPolicy: NamingPolicy; aPad: String;
                           aUnmapped: Dictionary<String, List<String>>; aUnmappedOrder: List<String>; aKnownTypes: HashSet<String>;
                           aDiagnostics: DiagnosticList);
    begin
      if aType.Kind = IrTypeKindLite.EnumLike then begin
        if aEnumStyle = EnumStyle.Numeric then begin
          aSb.AppendLine(aPad + 'export enum ' + aType.Name + ' {');
          for each ev in aType.EnumValues do
            aSb.AppendLine(aPad + '  ' + ev.Name + ' = ' + ev.NumericValue.ToString() + ',');
          aSb.AppendLine(aPad + '}');
        end
        else begin
          var namesSb := new StringBuilder;
          for i: Int32 := 0 to aType.EnumValues.Count - 1 do begin
            if i > 0 then namesSb.Append(' | ');
            namesSb.Append('"' + aType.EnumValues[i].Name + '"');
          end;
          aSb.AppendLine(aPad + 'export type ' + aType.Name + ' = ' + namesSb.ToString() + ';');
        end;
      end
      else if aType.Kind = IrTypeKindLite.FormErrorsLike then begin
        {
          docs/DESIGN.md §5.4: field names only, sourced from the same
          Members list already assembled for the paired Props type (see
          InertiaIrBuilder.Build) -- member types/nullability are ignored
          here, only Name is read. An empty field list (a legitimate
          props-less page, see InertiaScanner.pas) can't produce a valid
          union of zero string literals, so it falls back to `never`
          (`Partial<Record<never, string>>` is valid TS for "no keys").
        }
        var keysSb := new StringBuilder;
        if aType.Members.Count = 0 then
          keysSb.Append('never')
        else
          for i: Int32 := 0 to aType.Members.Count - 1 do begin
            if i > 0 then keysSb.Append(' | ');
            keysSb.Append('''' + ApplyNamingPolicy(aType.Members[i].Name, aNamingPolicy) + '''');
          end;
        aSb.AppendLine(aPad + 'export type ' + aType.Name + ' = Partial<Record<' + keysSb.ToString() + ', string>>;');
      end
      else begin
        {
          BaseTypeNames is only populated for the Inertia Shared Data
          feature (HANDOFF.md §27): each page's Props interface extends
          the shared "SharedData" interface instead of duplicating its
          members, so a key collision is a TypeScript compile error
          rather than a silently-wrong type -- a deliberate choice given
          shared data overwrites same-named page props at runtime
          (confirmed in the spike this is based on).
        }
        var header := aPad + 'export interface ' + aType.Name;
        if aType.BaseTypeNames.Count > 0 then begin
          header := header + ' extends ';
          for i: Int32 := 0 to aType.BaseTypeNames.Count - 1 do begin
            if i > 0 then header := header + ', ';
            header := header + aType.BaseTypeNames[i];
          end;
        end;
        aSb.AppendLine(header + ' {');
        {
          Tracks names already emitted for THIS interface, after the
          naming-policy transform -- e.g. a discovered Shared Data field
          (HANDOFF.md §27) whose transformed name collides with one of
          SharedData's own hardcoded floor keys ("flash"/"timestamp"/
          "errors"). Deliberately scoped to one EmitType call (one
          interface's own Members list), NOT across the `extends`
          boundary between a page's Props and Props.SharedData -- that
          cross-interface collision is meant to surface as a TypeScript
          compile error instead (see the BaseTypeNames comment above);
          only a collision within a single interface's own member list
          would otherwise silently produce invalid duplicate-property
          TypeScript. Since floor keys are added to Members before any
          discovered field (InertiaIrBuilder.Build), skipping the later
          duplicate here also matches InertiaNetCore's real runtime
          precedence for this specific case: Response.GetFinalProps
          applies AddFlash(...)/AddTimeStamp() (which write "flash"/
          "timestamp") AFTER merging in registered shared data, so the
          framework-injected value wins over a same-named registered
          field at runtime too (confirmed in the §27 spike).
        }
        var emittedNames := new HashSet<String>;
        for each m in aType.Members do begin
          var tsType := TypeMapper.MapTypeRef(m.TypeRef, aKnownTypes);
          if tsType = 'unknown' then begin
            var typeDisplayName := m.TypeRef.DisplayName;
            if not aUnmapped.ContainsKey(typeDisplayName) then begin
              aUnmapped[typeDisplayName] := new List<String>;
              aUnmappedOrder.Add(typeDisplayName);
            end;
            aUnmapped[typeDisplayName].Add(aType.Name + '.' + m.Name);
          end;

          var opt := '';
          if ResolveNullableSuffix(m.Nullability, aUnknownPolicy) then opt := ' | null';
          var unknownComment := '';
          if ShouldMarkUnknown(m.Nullability, aUnknownPolicy) then unknownComment := ' // nrt: unknown';
          {
            The unmapped-type diagnostic above deliberately still names
            m.Name (the as-written Oxygene source name), not the
            naming-policy-transformed one -- diagnostics point back to
            where the user should look in their own source, not to the
            emitted JSON/TS name.
          }
          var emittedName := ApplyNamingPolicy(m.Name, aNamingPolicy);
          if emittedNames.Contains(emittedName) then begin
            aDiagnostics.AddWarning('duplicate member "' + emittedName + '" on ' + aType.Name +
              ' after naming-policy transform (source name "' + m.Name + '") -- keeping the first occurrence, skipping this one, to avoid invalid duplicate TypeScript properties');
            continue;
          end;
          emittedNames.Add(emittedName);
          aSb.AppendLine(aPad + '  ' + emittedName + ': ' + tsType + opt + ';' + unknownComment);
        end;
        aSb.AppendLine(aPad + '}');
      end;
    end;

  public
    class method Emit(aAssembly: IrAssemblyLite; aEnumStyle: EnumStyle; aUnknownPolicy: NrtUnknownPolicy;
                       aNamingPolicy: NamingPolicy; aDiagnostics: DiagnosticList): String;
    begin
      var sb := new StringBuilder;
      sb.AppendLine('// AUTO-GENERATED by oxygene-tsgen. Do not edit by hand.');
      sb.AppendLine();

      {
        Keyed by the unmapped type's display name (RawTypeRef.DisplayName,
        e.g. "List<Foo>") so every member sharing one unmapped type (a
        common case -- e.g. a custom POCO with no TypeMapper rule used
        across many properties) collapses into a single diagnostic instead
        of one per occurrence. aUnmappedOrder preserves first-seen order
        for deterministic output, same rationale as "order" below for
        namespaces -- Dictionary iteration order isn't a contract to rely on.
      }
      var unmapped := new Dictionary<String, List<String>>;
      var unmappedOrder := new List<String>;

      {
        Every type this Emit call will itself output, keyed by its full
        "Namespace.Name" -- lets TypeMapper.MapTypeRef resolve a member
        whose type is one of OUR OWN types (docs/DESIGN.md §2.2 chain step
        "③e. User-defined types") to a reference by name, instead of
        falling to 'unknown' just because it isn't a recognized BCL
        primitive. See TypeMapper's own doc comment for why this is always
        fully namespace-qualified.
      }
      var knownTypes := new HashSet<String>;
      for each t in aAssembly.Types do begin
        if String.IsNullOrEmpty(t.NamespaceName) then
          knownTypes.Add(t.Name)
        else
          knownTypes.Add(t.NamespaceName + '.' + t.Name);
      end;

      var byNamespace := new Dictionary<String, List<IrTypeLite>>;
      var order := new List<String>;
      for each t in aAssembly.Types do begin
        var key := t.NamespaceName;
        if String.IsNullOrEmpty(key) then key := '';
        if not byNamespace.ContainsKey(key) then begin
          byNamespace[key] := new List<IrTypeLite>;
          order.Add(key);
        end;
        byNamespace[key].Add(t);
      end;

      for each ns in order do begin
        var types := byNamespace[ns];
        var hasNs := not String.IsNullOrEmpty(ns);
        var pad := '';
        if hasNs then begin
          sb.AppendLine('declare namespace ' + ns + ' {');
          pad := '  ';
        end;

        for each t in types do
          EmitType(sb, t, aEnumStyle, aUnknownPolicy, aNamingPolicy, pad, unmapped, unmappedOrder, knownTypes, aDiagnostics);

        if hasNs then sb.AppendLine('}');
      end;

      for each typeDisplayName in unmappedOrder do begin
        var locations := unmapped[typeDisplayName];
        var msg := 'no type mapping for ' + typeDisplayName + ', emitting "unknown" (' +
                   locations.Count.ToString() + ' member(s), e.g. ' + locations[0] + ')';
        aDiagnostics.AddWarning(msg);
      end;

      result := sb.ToString();
    end;
  end;

end.
