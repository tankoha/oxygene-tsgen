namespace Tsgen.Ir;

uses
  System.Collections.Generic,
  Tsgen.Loading;

type
  {
    Stand-in for the pluggable Stage 3 type-mapping chain (docs/DESIGN.md
    §2), which is deferred past the MVP per docs/DESIGN.md §10.2 item 8.
    Recursive over RawTypeRef so generic arguments/array element types are
    resolved the same way as top-level members -- e.g. List<Foo> maps by
    recursively mapping Foo, not by string-matching the whole "List<Foo>"
    shape.

    aKnownTypes (built once per Emit call by DtsEmitter, from every
    IrTypeLite's Namespace.Name) is docs/DESIGN.md §2.2 chain step "③e.
    User-defined types" in miniature: a leaf CLR type that isn't a
    recognized BCL primitive but IS one of our own emitted types (e.g. a
    property of type Node inside the Node/Tag assembly itself, or
    List<Node>'s element type) resolves to a reference by that type's own
    Namespace.Name rather than falling to 'unknown'. Always fully
    namespace-qualified (not the bare short name) because TypeScript's
    "declare namespace A.B" blocks accept dotted namespace paths as a
    reference regardless of which namespace block the reference appears
    in, so this stays correct without tracking "am I inside the same
    namespace as the referenced type." Named-type references are never
    structurally expanded (Node's own List<Node> member just says
    "Node[]", it doesn't inline Node's shape again), so self- and
    mutually-referential types don't cause infinite recursion here --
    this is also why full Tarjan-SCC cycle detection was judged
    unnecessary for DtsEmitter specifically this round (docs/DESIGN.md
    §3.3 already says as much for the non-structurally-expanding case).
  }
  TypeMapper = public static class
  private
    class method IsCollectionGenericDef(aFullName: String): Boolean;
    begin
      result :=
        (aFullName = 'System.Collections.Generic.List`1') or
        (aFullName = 'System.Collections.Generic.IList`1') or
        (aFullName = 'System.Collections.Generic.IEnumerable`1') or
        (aFullName = 'System.Collections.Generic.ICollection`1') or
        (aFullName = 'System.Collections.Generic.IReadOnlyList`1') or
        (aFullName = 'System.Collections.Generic.IReadOnlyCollection`1') or
        (aFullName = 'System.Collections.Generic.HashSet`1') or
        (aFullName = 'System.Collections.Generic.ISet`1');
    end;

    class method IsDictionaryGenericDef(aFullName: String): Boolean;
    begin
      result :=
        (aFullName = 'System.Collections.Generic.Dictionary`2') or
        (aFullName = 'System.Collections.Generic.IDictionary`2') or
        (aFullName = 'System.Collections.Generic.IReadOnlyDictionary`2');
    end;

    class method MapLeaf(aClrTypeName: String): String;
    begin
      if aClrTypeName = 'System.String' then
        result := 'string'
      else if aClrTypeName = 'System.Boolean' then
        result := 'boolean'
      else if (aClrTypeName = 'System.Int16') or (aClrTypeName = 'System.Int32') or (aClrTypeName = 'System.Int64')
           or (aClrTypeName = 'System.UInt16') or (aClrTypeName = 'System.UInt32') or (aClrTypeName = 'System.UInt64')
           or (aClrTypeName = 'System.Byte') or (aClrTypeName = 'System.SByte')
           or (aClrTypeName = 'System.Single') or (aClrTypeName = 'System.Double') or (aClrTypeName = 'System.Decimal') then
        result := 'number'
      else if (aClrTypeName = 'System.DateTime') or (aClrTypeName = 'System.DateTimeOffset') then
        result := 'string'
      {
        System.DateOnly/System.TimeOnly (docs/DESIGN.md §7 task 1,
        HANDOFF.md §34): both serialize to a plain ISO string under
        System.Text.Json's default converters -- DateOnly as "yyyy-MM-dd",
        TimeOnly as "HH:mm:ss[.fffffff]" -- same TS representation as
        DateTime/DateTimeOffset above, for the same reason (JSON has no
        native date/time type).
      }
      else if (aClrTypeName = 'System.DateOnly') or (aClrTypeName = 'System.TimeOnly') then
        result := 'string'
      else if aClrTypeName = 'System.Guid' then
        result := 'string'
      else
        result := 'unknown';
    end;

  public
    class method MapTypeRef(aTypeRef: RawTypeRef; aKnownTypes: HashSet<String>): String;
    begin
      if aTypeRef.IsArray then begin
        result := MapTypeRef(aTypeRef.ElementType, aKnownTypes) + '[]';
        exit;
      end;

      if aTypeRef.TypeArguments.Count > 0 then begin
        {
          Nullable<T> / Task<T> / ValueTask<T> (docs/DESIGN.md §2.2 "special
          cases") unwrap to their single type argument's mapping.
          Nullable<T>'s nullability itself is a Tsgen.Nrt concern
          (ValueTypeDefaultProvider), not this layer's -- mapping it here
          too would double up with the "| null" suffix DtsEmitter already
          adds from the resolved NullabilityKind.
        }
        if (aTypeRef.FullName = 'System.Nullable`1') or (aTypeRef.FullName = 'System.Threading.Tasks.Task`1')
           or (aTypeRef.FullName = 'System.Threading.Tasks.ValueTask`1') then begin
          result := MapTypeRef(aTypeRef.TypeArguments[0], aKnownTypes);
          exit;
        end;

        if (aTypeRef.TypeArguments.Count = 1) and IsCollectionGenericDef(aTypeRef.FullName) then begin
          result := MapTypeRef(aTypeRef.TypeArguments[0], aKnownTypes) + '[]';
          exit;
        end;

        if (aTypeRef.TypeArguments.Count = 2) and IsDictionaryGenericDef(aTypeRef.FullName) then begin
          var keyMapped := MapTypeRef(aTypeRef.TypeArguments[0], aKnownTypes);
          if (keyMapped = 'string') or (keyMapped = 'number') then begin
            result := 'Record<' + keyMapped + ', ' + MapTypeRef(aTypeRef.TypeArguments[1], aKnownTypes) + '>';
            exit;
          end;
          // Non-string/number keys have no clean JSON-shaped TS equivalent -- fall through to 'unknown'.
        end;

        result := 'unknown';
        exit;
      end;

      if aKnownTypes.Contains(aTypeRef.FullName) then
        result := aTypeRef.FullName
      else
        result := MapLeaf(aTypeRef.FullName);
    end;
  end;

end.
