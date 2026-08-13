namespace Tsgen.Inertia;

uses
  System.Collections.Generic,
  System.IO,
  System.Text,
  RemObjects.Elements.Code.Oxygene,
  Tsgen.Loading,
  Tsgen.Nrt,
  Tsgen.Diagnostics;

type
  InertiaPropsField = public class
  public
    Name: String;
    TypeRef: RawTypeRef;
    {
      Non-Unknown only when the local this field's value was read from
      carried an explicit "nullable"/"not nullable" annotation in source
      (HANDOFF.md §40). This is the ONLY nullability signal a props field
      can ever carry: a props field is synthesized from indexer
      assignments, not reflected from a real type member, so
      InertiaIrBuilder has no type name to key an
      OxygeneSourceScanProvider lookup on -- it passes an empty one, which
      by construction never matches anything the source scan recorded.
      Without an annotation here, every reference-typed props field is
      Unknown and falls to whatever --nrt-unknown-policy says.
    }
    ExplicitNullability: NullabilityKind := NullabilityKind.Unknown;
  end;

  InertiaPageProps = public class
  public
    ComponentName: String;
    Fields: List<InertiaPropsField> := new List<InertiaPropsField>;
  end;

  {
    Accumulates fields registered via `app.AddInertiaSharedData(ctx ->
    ...)` across every scanned file -- the InertiaNetCore middleware
    registration that injects data into every page (docs/DESIGN.md §2.6
    item 2/§8.2, spiked before implementation; see HANDOFF.md §27).
    Mirrors InertiaPageProps deliberately: same Fields shape, so
    InertiaIrBuilder can reuse the exact same per-field IR conversion
    for both.
  }
  InertiaSharedData = public class
  public
    Fields: List<InertiaPropsField> := new List<InertiaPropsField>;
  end;

  {
    Source-level scanner for entry-point-driven type discovery
    (docs/DESIGN.md §3.5, spiked in HANDOFF.md §22, implemented here per
    §24). Finds `Inertia.Render(componentName, propsVar)` call sites and
    resolves the shape of `propsVar` -- NOT by resolving one argument's
    static type (InertiaNetCore's Render only ever takes an
    InertiaProps/Dictionary<string,object?>, uninformative on its own,
    §22.1), but by tracking `propsVar['key'] := valueExpr;` indexer
    assignments within the same method body and resolving each value
    expression's type. Confirmed in §22.3 that this sequential-assignment
    shape is the ONLY one real Oxygene code can produce -- Oxygene has no
    working object/collection-initializer syntax -- so this scanner does
    not need to handle an inline-literal alternative.

    Heuristic, not a full parser, matching NullabilityScanner's own
    scope discipline. Deliberately resolves only: literals (string/
    integer/real/boolean), a plain identifier referencing a tracked
    parameter or local variable's declared type, and non-generic
    `new NamedType(...)` expressions.

    A tracked local's declared type MAY be a generic one, but only in
    the explicit colon-annotation position -- "var records: List<Foo> :=
    ...;". That is the shape this repository's CLAUDE.md prescribes for
    every value handed to props (always receive it into an annotated
    local first), and the only one real controller code here uses.
    ParseTypeAnnotation resolves it recursively, so nested arguments
    work too, over the List/IList/IEnumerable/ICollection/IReadOnlyList/
    IReadOnlyCollection/HashSet/ISet family, the Dictionary/IDictionary/
    IReadOnlyDictionary family, and Nullable -- exactly the set
    Tsgen.Ir.TypeMapper knows how to render (see ResolveGenericDefName).
    Nothing downstream needed teaching: RawTypeRef is already a
    structural reference, TypeMapper.MapTypeRef already maps generic
    arguments recursively, and InertiaIrBuilder.CollectReferencedTypes
    already walks TypeArguments, so an element type reachable only
    through a generic argument still gets emitted by the reachability
    BFS.

    A colon annotation may also carry an explicit "nullable" or "not
    nullable" prefix, read by the same rule NullabilityScanner applies
    to a real type member (HANDOFF.md §40). The prefix is recorded
    against the local and travels to any props field whose value is
    that bare local identifier, as InertiaPropsField.ExplicitNullability
    -- the only way source can state a props field's nullability at all,
    since the provider chain structurally cannot see a synthesized
    props field (see that field's own doc comment).

    Deliberately NOT resolved this round (falls back to Unknown + a
    diagnostic naming the unresolved key, per §24 scope decision):
    `new class(...)` anonymous-literal values, a generic spelling
    anywhere OTHER than a local's colon annotation -- an inferred
    "var x := new List<Foo>;" local, a generic-typed method parameter,
    a "new NamedType<Foo>(...)" expression directly in props-value
    position -- the "array of T" spelling, dotted
    type names, conditional/branch-dependent key-setting, keys set via
    a helper-method call, `Inertia.Defer(...)`/`Inertia.Merge(...)`-
    wrapped values, dynamically computed keys, and props built in a
    different method/class than where `Render` is called. Nullability
    annotations on method PARAMETERS are likewise not read
    (ParseMethodParams is unchanged), and a "new NamedType" props value
    is not treated as implicitly non-null even though it can never be
    nil -- both are possible follow-ups, deliberately not bundled here.
  }
  InertiaScanner = public static class
  private
    const TOK_IDENTIFIER = Token.T_Identifier;
    const TOK_COLON = Token.T_Colon;
    const TOK_SEMICOLON = Token.T_SemiColon;
    const TOK_COMMA = Token.T_Comma;
    const TOK_OPENROUND = Token.T_OpenRound;
    const TOK_CLOSEROUND = Token.T_CloseRound;
    const TOK_OPENBLOCK = Token.T_OpenBlock;
    const TOK_CLOSEBLOCK = Token.T_CloseBlock;
    const TOK_DOT = Token.T_Dot;
    const TOK_LESS = Token.T_Less;
    const TOK_GREATER = Token.T_Greater;
    const TOK_ASSIGN = Token.T_Assignment;
    const TOK_BEGIN = Token.TI_begin;
    const TOK_TRY = Token.TI_try;
    const TOK_CASEKW = Token.TI_case;
    const TOK_END = Token.TI_end;
    const TOK_METHOD = Token.TI_method;
    const TOK_VAR = Token.TI_var;
    const TOK_NEW = Token.TI_new;
    const TOK_CLASS = Token.TI_class;
    const TOK_NULLABLE = Token.TI_nullable;
    const TOK_NOT = Token.TI_not;
    const TOK_STRING = Token.T_String;
    const TOK_INTEGER = Token.T_Integer;
    const TOK_REAL = Token.T_Real;
    const TOK_TRUE = Token.TI_true;
    const TOK_FALSE = Token.TI_false;

    class method MakeSimpleTypeRef(aFullName: String): RawTypeRef;
    begin
      result := new RawTypeRef;
      result.FullName := aFullName;
    end;

    {
      Resolves a single, undecorated type NAME as written in source
      (e.g. "UserDto", "Int32") to a RawTypeRef, or nil if unresolvable.
      Never sees a whole generic spelling: ParseTypeAnnotation splits one
      into its outer name plus arguments and calls this only for each
      LEAF name. Array and dotted spellings remain out of scope entirely
      (see the class-level doc comment). Checks Oxygene's built-in BCL
      aliases first, then
      aKnownTypes (the target assembly's own types, keyed by short Name --
      short-name lookup can collide across namespaces, last-registered
      wins, an accepted v1 heuristic limitation).
    }
    class method ResolveTypeName(aWrittenName: String; aKnownTypes: Dictionary<String, RawTypeRef>): RawTypeRef;
    begin
      if String.IsNullOrEmpty(aWrittenName) then begin
        result := nil;
        exit;
      end;

      if aWrittenName = 'String' then
        result := MakeSimpleTypeRef('System.String')
      else if aWrittenName = 'Boolean' then
        result := MakeSimpleTypeRef('System.Boolean')
      else if (aWrittenName = 'Int16') or (aWrittenName = 'Int32') or (aWrittenName = 'Int64')
           or (aWrittenName = 'UInt16') or (aWrittenName = 'UInt32') or (aWrittenName = 'UInt64')
           or (aWrittenName = 'Byte') or (aWrittenName = 'SByte') then
        result := MakeSimpleTypeRef('System.' + aWrittenName)
      else if (aWrittenName = 'Single') or (aWrittenName = 'Double') or (aWrittenName = 'Decimal') then
        result := MakeSimpleTypeRef('System.' + aWrittenName)
      else if (aWrittenName = 'DateTime') or (aWrittenName = 'DateTimeOffset') or (aWrittenName = 'Guid') then
        result := MakeSimpleTypeRef('System.' + aWrittenName)
      else if (aWrittenName = 'DateOnly') or (aWrittenName = 'TimeOnly') then
        result := MakeSimpleTypeRef('System.' + aWrittenName)
      {
        Oxygene's own "more Pascal-ish" standard-library aliases for
        exactly the same CLR value types already recognized by their
        direct CLR name above -- confirmed against
        https://docs.elementscompiler.com/API/StandardTypes/Integers/,
        not guessed (M3-dts-validation.md bug #1: real Oxygene code
        overwhelmingly writes "Integer" rather than "Int32", which is what
        originally exposed this gap -- ResolveTypeName silently returned
        nil for it, so a var like "var count: Integer" never registered
        in aLocalTypes and any props value read from it fell back to
        unknown). Deliberately does NOT add "Real" for Double despite that
        being a common historical Pascal/Delphi name: the current Elements
        Floats standard-types page
        (https://docs.elementscompiler.com/API/StandardTypes/Floats/) does
        not document it as a recognized Oxygene alias (only "float"/
        "Float32" for Single and "Float64" for Double), so it's left out
        rather than added on assumption -- see HANDOFF.md §32. Also
        deliberately does NOT add NativeInt/NativeUInt (aliased there to
        IntPtr/UIntPtr) -- platform pointer-sized ints have no
        TypeMapper.MapLeaf case anyway (System.IntPtr/System.UIntPtr
        aren't in its known-primitives list), and aren't realistic Inertia
        props types.
      }
      else if aWrittenName = 'Integer' then
        result := MakeSimpleTypeRef('System.Int32')
      else if aWrittenName = 'SmallInt' then
        result := MakeSimpleTypeRef('System.Int16')
      else if aWrittenName = 'ShortInt' then
        result := MakeSimpleTypeRef('System.SByte')
      else if aWrittenName = 'Word' then
        result := MakeSimpleTypeRef('System.UInt16')
      else if (aWrittenName = 'Cardinal') or (aWrittenName = 'LongWord') then
        result := MakeSimpleTypeRef('System.UInt32')
      else if aWrittenName = 'IntMax' then
        result := MakeSimpleTypeRef('System.Int64')
      else if aWrittenName = 'UIntMax' then
        result := MakeSimpleTypeRef('System.UInt64')
      else if aKnownTypes.ContainsKey(aWrittenName) then
        result := aKnownTypes[aWrittenName]
      else
        result := nil;
    end;

    {
      Maps a generic type's OUTER name as written in source, plus the
      number of type arguments actually parsed, to the CLR generic type
      DEFINITION name RawTypeRef.FullName expects -- e.g. "List" with one
      argument to the backtick-1 List definition under
      System.Collections.Generic. Returns an empty string for an
      unrecognized name OR a mismatched argument count; an arity mismatch
      is deliberately treated exactly like an unknown name, since a
      wrongly-shaped RawTypeRef would render something misleading
      downstream rather than nothing at all.

      KEEP THIS SET IN SYNC WITH Tsgen.Ir.TypeMapper's own
      IsCollectionGenericDef / IsDictionaryGenericDef: those two decide
      which generic definitions actually map to a TypeScript array or
      Record type, so recognizing a name here that TypeMapper does not
      know would resolve the local only for its props field to render
      "unknown" anyway -- worse than leaving it unresolved, because the
      existing "could not resolve type of Inertia props key" diagnostic
      would no longer fire to say why. Nullable is the one deliberate
      addition: TypeMapper handles the backtick-1 System.Nullable
      definition inside MapTypeRef directly, not via either predicate.
    }
    class method ResolveGenericDefName(aOuterName: String; aArgCount: Int32): String;
    begin
      var oneArg :=
        (aOuterName = 'List') or (aOuterName = 'IList') or (aOuterName = 'IEnumerable') or
        (aOuterName = 'ICollection') or (aOuterName = 'IReadOnlyList') or
        (aOuterName = 'IReadOnlyCollection') or (aOuterName = 'HashSet') or (aOuterName = 'ISet');
      var twoArgs :=
        (aOuterName = 'Dictionary') or (aOuterName = 'IDictionary') or (aOuterName = 'IReadOnlyDictionary');

      if oneArg and (aArgCount = 1) then
        result := 'System.Collections.Generic.' + aOuterName + '`1'
      else if twoArgs and (aArgCount = 2) then
        result := 'System.Collections.Generic.' + aOuterName + '`2'
      else if (aOuterName = 'Nullable') and (aArgCount = 1) then
        result := 'System.Nullable`1'
      else
        result := '';
    end;

    {
      Recursive-descent parser for a type annotation in the colon position
      of a local variable declaration, per the grammar: an identifier,
      optionally followed by an angle-bracketed, comma-separated list of
      further type annotations. Returns the resolved RawTypeRef, or nil
      when any part of it is unresolvable (unknown outer name, arity
      mismatch, or any argument itself unresolved) -- nil means "do not
      register this local", which lets the props field that reads it fall
      into the pre-existing "could not resolve type of Inertia props key"
      diagnostic path. No new diagnostic is raised here.

      aNextIdx always reports where parsing should resume, INCLUDING on
      failure: the balanced closing angle bracket is located by a depth
      count before the arguments are parsed at all, so an argument list
      this parser cannot make sense of still leaves the caller's resume
      position intact rather than desynchronizing the statement scan.
      Oxygene spells the shift operators "shl"/"shr", so there is no
      merged double-angle-bracket token to worry about the way a C-family
      tokenizer would have.

      Argument RawTypeRefs come straight from aKnownTypes where they are
      assembly types -- those instances are shared, and treated as
      read-only everywhere after construction, so no copy is made.
    }
    class method ParseTypeAnnotation(aTokens: List<ScanToken>; aStart: Int32; aKnownTypes: Dictionary<String, RawTypeRef>;
                                      out aNextIdx: Int32): RawTypeRef;
    begin
      result := nil;
      aNextIdx := aStart;
      if (aStart >= aTokens.Count) or (aTokens[aStart].Id <> TOK_IDENTIFIER) then exit;

      var outerName := aTokens[aStart].Text;
      var i := aStart + 1;

      if (i >= aTokens.Count) or (aTokens[i].Id <> TOK_LESS) then begin
        // Plain, undecorated name -- may still resolve to nil.
        aNextIdx := i;
        result := ResolveTypeName(outerName, aKnownTypes);
        exit;
      end;

      {
        Locate the balanced closing bracket first. A ';' or ':=' before it
        means this was never a well-formed annotation at all (or the
        source is mid-edit) -- stop there rather than scanning to EOF, and
        let the caller's own skip-to-semicolon loop take over.
      }
      var openIdx := i;
      var closeIdx: Int32 := -1;
      var depth: Int32 := 0;
      var j := openIdx;
      while j < aTokens.Count do begin
        var id := aTokens[j].Id;
        if id = TOK_LESS then
          inc(depth)
        else if id = TOK_GREATER then begin
          dec(depth);
          if depth = 0 then begin
            closeIdx := j;
            break;
          end;
        end
        else if (id = TOK_SEMICOLON) or (id = TOK_ASSIGN) then
          break;
        inc(j);
      end;

      if closeIdx < 0 then begin
        aNextIdx := j;
        exit;
      end;
      aNextIdx := closeIdx + 1;

      var args := new List<RawTypeRef>;
      var argCount: Int32 := 0;
      var allResolved := true;
      var k := openIdx + 1;
      while k < closeIdx do begin
        var argNextIdx: Int32;
        var argType := ParseTypeAnnotation(aTokens, k, aKnownTypes, out argNextIdx);
        inc(argCount);
        if argType = nil then
          allResolved := false
        else
          args.Add(argType);

        if argNextIdx <= k then begin
          // No progress -- an unexpected token where an argument belongs.
          allResolved := false;
          break;
        end;
        k := argNextIdx;

        if k >= closeIdx then break;
        if aTokens[k].Id = TOK_COMMA then
          inc(k)
        else begin
          allResolved := false;
          break;
        end;
      end;

      if (not allResolved) or (argCount = 0) then exit;

      var defName := ResolveGenericDefName(outerName, argCount);
      if defName = '' then exit;

      result := new RawTypeRef;
      result.FullName := defName;
      result.TypeArguments.AddRange(args);
    end;

    {
      Oxygene string literals are single-quoted with '' as the escaped
      quote (Pascal-style); GetString()/GetOriginalString() both return
      the raw, still-quoted source text (confirmed hands-on, HANDOFF.md
      §24) -- this strips the outer quotes and un-escapes '' to '.
    }
    class method UnquoteStringLiteral(aRaw: String): String;
    begin
      var s := aRaw;
      if (s.Length >= 2) and (s[0] = '''') and (s[s.Length - 1] = '''') then
        s := s.Substring(1, s.Length - 2);
      result := s.Replace('''''', '''');
    end;

    {
      Resolves the type of the value expression in aTokens[aStart..aEnd)
      (aEnd exclusive). Only recognizes the shapes documented in the
      class-level comment; anything else (including new class(...)
      anonymous literals) returns nil.
    }
    class method ResolveValueExprType(aTokens: List<ScanToken>; aStart: Int32; aEnd: Int32;
                                       aParamTypes: Dictionary<String, RawTypeRef>; aLocalTypes: Dictionary<String, RawTypeRef>;
                                       aKnownTypes: Dictionary<String, RawTypeRef>): RawTypeRef;
    begin
      result := nil;
      if aEnd <= aStart then exit;

      if aEnd - aStart = 1 then begin
        var t := aTokens[aStart];
        if t.Id = TOK_STRING then
          result := MakeSimpleTypeRef('System.String')
        else if t.Id = TOK_INTEGER then
          result := MakeSimpleTypeRef('System.Int32')
        else if t.Id = TOK_REAL then
          result := MakeSimpleTypeRef('System.Double')
        else if (t.Id = TOK_TRUE) or (t.Id = TOK_FALSE) then
          result := MakeSimpleTypeRef('System.Boolean')
        else if t.Id = TOK_IDENTIFIER then begin
          if aLocalTypes.ContainsKey(t.Text) then
            result := aLocalTypes[t.Text]
          else if aParamTypes.ContainsKey(t.Text) then
            result := aParamTypes[t.Text];
        end;
        exit;
      end;

      // "new NamedType" (no-arg constructor, no parens) or
      // "new NamedType ( ... )" -- either shape, non-generic only.
      if (aTokens[aStart].Id = TOK_NEW) and (aStart + 1 < aEnd) and (aTokens[aStart + 1].Id = TOK_IDENTIFIER) then begin
        if aEnd - aStart = 2 then
          result := ResolveTypeName(aTokens[aStart + 1].Text, aKnownTypes)
        else if (aStart + 2 < aEnd) and (aTokens[aStart + 2].Id = TOK_OPENROUND) and (aTokens[aEnd - 1].Id = TOK_CLOSEROUND) then
          result := ResolveTypeName(aTokens[aStart + 1].Text, aKnownTypes);
        exit;
      end;

      // "new class ( ... )" anonymous literal -- deliberately unresolved this round.
    end;

    {
      Parses a `method Name(params): ReturnType;` header starting at the
      `method` token, populating aParamTypes. Returns the index to resume
      scanning from. Deliberately skips (does not attempt to resolve)
      generic/array-spelled parameter types -- only captures the first
      identifier token right after each group's `:` as a candidate simple
      type name; a fresh parameter-name position is recognized by BOTH the
      preceding token being one of "(", ",", ";" AND the following token
      being ":" or "," -- requiring both avoids misreading a generic type's
      own argument (e.g. "Object" inside "Dictionary<String, Object>",
      preceded by "," and followed by ">") as a new parameter name.
    }
    class method ParseMethodParams(aTokens: List<ScanToken>; aMethodIdx: Int32; aKnownTypes: Dictionary<String, RawTypeRef>;
                                    aParamTypes: Dictionary<String, RawTypeRef>): Int32;
    begin
      var i := aMethodIdx + 1;
      while (i < aTokens.Count) and (aTokens[i].Id <> TOK_OPENROUND) and (aTokens[i].Id <> TOK_SEMICOLON) do
        inc(i);

      if (i >= aTokens.Count) or (aTokens[i].Id <> TOK_OPENROUND) then begin
        result := i;
        exit;
      end;

      var parenDepth := 1;
      inc(i);
      var pendingNames := new List<String>;
      var prevId: Int32 := TOK_OPENROUND;

      while (i < aTokens.Count) and (parenDepth > 0) do begin
        var t := aTokens[i];

        if t.Id = TOK_OPENROUND then
          inc(parenDepth)
        else if t.Id = TOK_CLOSEROUND then
          dec(parenDepth)
        else if (parenDepth = 1) and (t.Id = TOK_IDENTIFIER)
                and ((prevId = TOK_OPENROUND) or (prevId = TOK_COMMA) or (prevId = TOK_SEMICOLON))
                and (i + 1 < aTokens.Count) and ((aTokens[i + 1].Id = TOK_COLON) or (aTokens[i + 1].Id = TOK_COMMA)) then
          pendingNames.Add(t.Text)
        else if (parenDepth = 1) and (t.Id = TOK_COLON) then begin
          var writtenName := '';
          if (i + 1 < aTokens.Count) and (aTokens[i + 1].Id = TOK_IDENTIFIER) then
            writtenName := aTokens[i + 1].Text;
          var resolvedType := ResolveTypeName(writtenName, aKnownTypes);
          if resolvedType <> nil then
            for each nm in pendingNames do
              aParamTypes[nm] := resolvedType;
          pendingNames := new List<String>;
        end;

        prevId := t.Id;
        inc(i);
      end;

      result := i;
    end;

    {
      Parses `var IDENT := new TypeName [(...)];` or
      `var IDENT : TypeAnnotation [:= ...];` starting at the `var` token.
      The two branches resolve their type differently: the inferred
      (`:=`) branch still reads a single identifier after `new` and
      resolves it through ResolveTypeName, while the colon branch hands
      the whole annotation to ParseTypeAnnotation, so a generic one
      resolves structurally (see the class-level doc comment for the
      recognized families and for what stays out of scope).

      The colon branch also accepts an optional "nullable"/"not nullable"
      prefix ahead of the type, recording it in aLocalNullability under
      IDENT (HANDOFF.md §40). The prefix tokens are consumed only when a
      "nullable" keyword is actually present, so a lone "not" is left
      exactly where it was for the type parse to reject, as before.

      Populates aLocalTypes when a type resolved; additionally registers
      IDENT in aPropsFields (with an empty field list to accumulate into)
      when the name WRITTEN right after the colon -- past any nullability
      prefix -- or after `new` is
      exactly "InertiaProps" or "Dictionary", the only two shapes
      confirmed usable for Inertia props construction (§22.1/§22.3).
      That registration deliberately keys off the written outer name
      alone, unchanged by generic support: a props var declared as a
      Dictionary of String to Object still registers as a props var even
      though Object does not resolve, so its own type never lands in
      aLocalTypes -- exactly the pre-existing behavior. Returns the index
      to resume scanning from.
    }
    class method ParseVarDecl(aTokens: List<ScanToken>; aVarIdx: Int32; aKnownTypes: Dictionary<String, RawTypeRef>;
                               aLocalTypes: Dictionary<String, RawTypeRef>; aLocalNullability: Dictionary<String, NullabilityKind>;
                               aPropsFields: Dictionary<String, List<InertiaPropsField>>): Int32;
    begin
      var i := aVarIdx + 1;
      if (i >= aTokens.Count) or (aTokens[i].Id <> TOK_IDENTIFIER) then begin
        result := i;
        exit;
      end;
      var varName := aTokens[i].Text;
      inc(i);

      var writtenName := '';
      var annotated := false;
      var annotatedType: RawTypeRef := nil;
      var explicitKind := NullabilityKind.Unknown;
      if (i < aTokens.Count) and (aTokens[i].Id = TOK_ASSIGN) then begin
        // var IDENT := new TypeName ...
        inc(i);
        if (i + 1 < aTokens.Count) and (aTokens[i].Id = TOK_NEW) and (aTokens[i + 1].Id = TOK_IDENTIFIER) then
          writtenName := aTokens[i + 1].Text;
      end
      else if (i < aTokens.Count) and (aTokens[i].Id = TOK_COLON) then begin
        // var IDENT : [not] [nullable] TypeAnnotation [:= ...]
        inc(i);

        {
          Same rule as NullabilityScanner.ScanMemberDecl reads on a real
          type member: an optional "not", then "nullable". Looked ahead
          rather than consumed as it goes, so a bare "not" with no
          "nullable" behind it advances nothing and stays an ordinary
          (unresolvable) annotation, exactly as before this was added.
        }
        var isNot := (i < aTokens.Count) and (aTokens[i].Id = TOK_NOT);
        var nullableIdx := i;
        if isNot then nullableIdx := i + 1;
        if (nullableIdx < aTokens.Count) and (aTokens[nullableIdx].Id = TOK_NULLABLE) then begin
          if isNot then explicitKind := NullabilityKind.IsNotNullable
          else explicitKind := NullabilityKind.IsNullable;
          i := nullableIdx + 1;
        end;

        if (i < aTokens.Count) and (aTokens[i].Id = TOK_IDENTIFIER) then
          writtenName := aTokens[i].Text;
        annotated := true;
        var afterTypeIdx: Int32;
        annotatedType := ParseTypeAnnotation(aTokens, i, aKnownTypes, out afterTypeIdx);
        i := afterTypeIdx;
      end;

      // Skip to the statement's terminating top-level ';'.
      var innerParen := 0;
      while (i < aTokens.Count) do begin
        var t := aTokens[i];
        if t.Id = TOK_OPENROUND then inc(innerParen)
        else if t.Id = TOK_CLOSEROUND then begin
          if innerParen > 0 then dec(innerParen);
        end
        else if (innerParen = 0) and (t.Id = TOK_SEMICOLON) then begin
          inc(i);
          break;
        end;
        inc(i);
      end;
      result := i;

      var resolvedType: RawTypeRef;
      if annotated then
        resolvedType := annotatedType
      else
        resolvedType := ResolveTypeName(writtenName, aKnownTypes);
      if resolvedType <> nil then
        aLocalTypes[varName] := resolvedType;

      {
        Recorded even when the type itself did not resolve: the
        annotation is a fact about what the source says, independent of
        whether this scanner could map the type name, and an unresolved
        field renders as "unknown" either way.
      }
      if explicitKind <> NullabilityKind.Unknown then
        aLocalNullability[varName] := explicitKind;

      if (writtenName = 'InertiaProps') or (writtenName = 'Dictionary') then
        aPropsFields[varName] := new List<InertiaPropsField>;
    end;

    {
      Parses `IDENT [ 'key' ] := valueExpr ;` starting at IDENT (already
      confirmed present in aPropsFields), appending one field to
      aFieldList when the value resolves, or warning via aDiagnostics
      (naming aVarName and the key) when it doesn't. Returns the index to
      resume scanning from.

      A value that is exactly one identifier naming a local carries that
      local's explicit nullability annotation, if it had one, onto the
      field (HANDOFF.md §40). No other value shape can: a literal or a
      `new` expression has no annotated declaration to read one from.
    }
    class method ParsePropsAssignment(aTokens: List<ScanToken>; aIdentIdx: Int32; aKnownTypes: Dictionary<String, RawTypeRef>;
                                       aParamTypes: Dictionary<String, RawTypeRef>; aLocalTypes: Dictionary<String, RawTypeRef>;
                                       aLocalNullability: Dictionary<String, NullabilityKind>;
                                       aFieldList: List<InertiaPropsField>; aDiagnostics: DiagnosticList; aVarName: String): Int32;
    begin
      var i := aIdentIdx + 1; // at '['
      inc(i);
      var key := '';
      if (i < aTokens.Count) and (aTokens[i].Id = TOK_STRING) then begin
        key := UnquoteStringLiteral(aTokens[i].Text);
        inc(i);
      end;
      if (i < aTokens.Count) and (aTokens[i].Id = TOK_CLOSEBLOCK) then inc(i);
      if (i < aTokens.Count) and (aTokens[i].Id = TOK_ASSIGN) then inc(i);

      var exprStart := i;
      var innerParen := 0;
      while (i < aTokens.Count) do begin
        var t := aTokens[i];
        if t.Id = TOK_OPENROUND then inc(innerParen)
        else if t.Id = TOK_CLOSEROUND then begin
          if innerParen > 0 then dec(innerParen);
        end
        else if (innerParen = 0) and (t.Id = TOK_SEMICOLON) then
          break;
        inc(i);
      end;
      var exprEnd := i;
      if i < aTokens.Count then inc(i); // past the ';'
      result := i;

      if String.IsNullOrEmpty(key) then exit;

      var valueType := ResolveValueExprType(aTokens, exprStart, exprEnd, aParamTypes, aLocalTypes, aKnownTypes);
      if valueType = nil then begin
        aDiagnostics.AddWarning('could not resolve type of Inertia props key "' + key + '" on ' + aVarName + ' -- emitting "unknown" for this field');
        valueType := MakeSimpleTypeRef('(unresolved)');
      end;

      var field := new InertiaPropsField;
      field.Name := key;
      field.TypeRef := valueType;
      if (exprEnd - exprStart = 1) and (aTokens[exprStart].Id = TOK_IDENTIFIER)
         and aLocalNullability.ContainsKey(aTokens[exprStart].Text) then
        field.ExplicitNullability := aLocalNullability[aTokens[exprStart].Text];
      aFieldList.Add(field);
    end;

    {
      Parses `Inertia . Render ( 'component' [, propsExpr] ) ;` starting
      at the "Inertia" identifier. If propsExpr is a plain identifier
      already tracked in aPropsFields, emits an InertiaPageProps using its
      accumulated fields; if there's no second argument at all, emits an
      InertiaPageProps with zero fields (a legitimate props-less page);
      otherwise warns and skips (the props shape isn't something this
      scanner's scope can resolve -- see the class-level comment for what
      that covers). Returns the index to resume scanning from.
    }
    class method ParseRenderCall(aTokens: List<ScanToken>; aInertiaIdx: Int32; aPropsFields: Dictionary<String, List<InertiaPropsField>>;
                                  aResult: List<InertiaPageProps>; aDiagnostics: DiagnosticList): Int32;
    begin
      var i := aInertiaIdx + 4; // past "Inertia" "." "Render" "("
      result := i;

      if (i >= aTokens.Count) or (aTokens[i].Id <> TOK_STRING) then exit;
      var componentName := UnquoteStringLiteral(aTokens[i].Text);
      inc(i);

      var page := new InertiaPageProps;
      page.ComponentName := componentName;

      if (i < aTokens.Count) and (aTokens[i].Id = TOK_CLOSEROUND) then begin
        // Inertia.Render('component') -- no props at all, a legitimate empty page.
        result := i + 1;
        aResult.Add(page);
        exit;
      end;

      if (i < aTokens.Count) and (aTokens[i].Id = TOK_COMMA) then begin
        inc(i);
        if (i < aTokens.Count) and (aTokens[i].Id = TOK_IDENTIFIER) and aPropsFields.ContainsKey(aTokens[i].Text) then begin
          page.Fields.AddRange(aPropsFields[aTokens[i].Text]);
          inc(i);
          // Skip to the closing ')'.
          while (i < aTokens.Count) and (aTokens[i].Id <> TOK_CLOSEROUND) do inc(i);
          if i < aTokens.Count then inc(i);
          result := i;
          aResult.Add(page);
          exit;
        end;
      end;

      // Unresolvable props argument shape (method call, inline expression, etc.) -- skip this call site.
      aDiagnostics.AddWarning('could not resolve props for Inertia.Render("' + componentName + '", ...) -- skipping this page');
      var depth := 1;
      while (i < aTokens.Count) and (depth > 0) do begin
        if aTokens[i].Id = TOK_OPENROUND then inc(depth)
        else if aTokens[i].Id = TOK_CLOSEROUND then dec(depth);
        inc(i);
      end;
      result := i;
    end;

    {
      Parses `Inertia . Share ( ... ) ;` starting at "Inertia", for
      diagnostic purposes only -- v1 deliberately does NOT classify a
      bare Inertia.Share(...) call as shared data (HANDOFF.md §27's scope
      decision: unlike AddInertiaSharedData(...), a Share call's call
      shape alone can't distinguish "this is app-global shared data" from
      "this adds one prop to the current page", since InertiaNetCore uses
      the same API for both). Just warns and skips to the matching ')'.
      Returns the index to resume scanning from.
    }
    class method ParseShareCallExcluded(aTokens: List<ScanToken>; aInertiaIdx: Int32; aDiagnostics: DiagnosticList): Int32;
    begin
      aDiagnostics.AddWarning('found an Inertia.Share(...) call -- not included in the generated SharedData type under the current policy (only AddInertiaSharedData(...) middleware registrations are treated as shared data); see HANDOFF.md §27');
      var i := aInertiaIdx + 4; // past "Inertia" "." "Share" "("
      var depth := 1;
      while (i < aTokens.Count) and (depth > 0) do begin
        if aTokens[i].Id = TOK_OPENROUND then inc(depth)
        else if aTokens[i].Id = TOK_CLOSEROUND then dec(depth);
        inc(i);
      end;
      result := i;
    end;

    {
      Merges multiple raw `InertiaPageProps` entries that share the same
      `ComponentName` into one, unioning their `Fields` (HANDOFF.md §37,
      Fable5 review finding on the M3-dts-validation.md real-DLL run):
      real Oxygene apps commonly `Inertia.Render` the same component from
      more than one action (e.g. a GET action rendering a form and a POST
      action re-rendering the same form with validation errors), and
      before this fix each such call site produced its OWN
      `InertiaPageProps` entry, so `InertiaIrBuilder.Build` (which treats
      every entry in its `aPages` list as a distinct page, one Props +
      one FormErrors type each) emitted the SAME Props/FormErrors type
      twice. Harmless for `interface` (TypeScript's declaration merging
      tolerates a repeated identical `interface`), but a hard compile
      error for the `type XxxFormErrors = Partial<Record<...>>` alias
      DtsEmitter.EmitType emits for `FormErrorsLike` -- TypeScript does
      NOT allow redeclaring a `type` alias ("Duplicate identifier").

      Fixed here, in the Scanner, rather than in InertiaIrBuilder: this
      keeps `InertiaIrBuilder.Build`'s existing "one entry in aPages = one
      page" assumption correct and unchanged, and matches the existing
      responsibility split -- the Scanner's job is to collect and
      normalize what call-site parsing found (it already does the
      analogous cross-file accumulation for `aSharedData.Fields`),
      IrBuilder's job is to convert an already-resolved page list into
      IR, not to know anything about "the same component rendered from
      two call sites" being a possibility.

      A field name present at more than one call site for the same
      component keeps its FIRST-resolved type (call-site order = file
      enumeration order, then within-file token order, both already
      deterministic) and, if a LATER call site resolves that same field
      name to a different type, warns via aDiagnostics naming the
      component, the field, and both conflicting type display names,
      rather than silently picking one or trying to union the types
      (v1 has no TS union-type synthesis path for this). A field present
      at only one call site is still included -- the union, not the
      intersection -- since v1 has no way to know whether a field is
      genuinely conditional or just happens to be set from a different
      action; unioning and always treating every field as required
      matches the pre-existing "no optional-field support" scope
      decision (docs/DESIGN.md §5.4 / HANDOFF.md §24.6), not a new one
      made here.

      A field's ExplicitNullability rides along with the field object
      itself, so the same first-resolved-wins rule the TypeRef follows
      applies to it too. A later call site annotating the same key
      differently is not separately warned about -- the existing
      conflict diagnostic covers the case that actually breaks output
      (two incompatible TYPES for one key), and nullability disagreement
      alone still produces valid TypeScript.
    }
    class method MergePages(aRawPages: List<InertiaPageProps>; aDiagnostics: DiagnosticList): List<InertiaPageProps>;
    begin
      result := new List<InertiaPageProps>;
      var mergedByComponent := new Dictionary<String, InertiaPageProps>;
      var fieldIndexByComponent := new Dictionary<String, Dictionary<String, Int32>>;

      for each page in aRawPages do begin
        var merged: InertiaPageProps;
        var fieldIndex: Dictionary<String, Int32>;
        if mergedByComponent.ContainsKey(page.ComponentName) then begin
          merged := mergedByComponent[page.ComponentName];
          fieldIndex := fieldIndexByComponent[page.ComponentName];
        end
        else begin
          merged := new InertiaPageProps;
          merged.ComponentName := page.ComponentName;
          mergedByComponent[page.ComponentName] := merged;
          fieldIndex := new Dictionary<String, Int32>;
          fieldIndexByComponent[page.ComponentName] := fieldIndex;
          result.Add(merged);
        end;

        for each field in page.Fields do begin
          if fieldIndex.ContainsKey(field.Name) then begin
            var existingField := merged.Fields[fieldIndex[field.Name]];
            if existingField.TypeRef.DisplayName <> field.TypeRef.DisplayName then
              aDiagnostics.AddWarning('Inertia page "' + page.ComponentName + '" renders prop "' + field.Name +
                '" with conflicting types across multiple Render call sites (' + existingField.TypeRef.DisplayName +
                ' from an earlier call site vs ' + field.TypeRef.DisplayName +
                ' here) -- keeping the first-resolved type for the merged page.');
            // Otherwise identical types at both call sites -- nothing to do, already merged.
          end
          else begin
            fieldIndex[field.Name] := merged.Fields.Count;
            merged.Fields.Add(field);
          end;
        end;
      end;
    end;

    class method ScanFile(aTokens: List<ScanToken>; aKnownTypes: Dictionary<String, RawTypeRef>; aResult: List<InertiaPageProps>;
                           aSharedData: InertiaSharedData; aDiagnostics: DiagnosticList);
    begin
      var depth: Int32 := 0;
      var parenDepth: Int32 := 0;
      var inMethodBody := false;
      var methodBodyDepth: Int32 := -1;
      var paramTypes := new Dictionary<String, RawTypeRef>;
      var localTypes := new Dictionary<String, RawTypeRef>;
      var localNullability := new Dictionary<String, NullabilityKind>;
      var propsFields := new Dictionary<String, List<InertiaPropsField>>;

      {
        Tracks an active `app.AddInertiaSharedData(ctx -> ...)` call's
        argument-list span (HANDOFF.md §27): sharedRegionEntryParenDepth
        is parenDepth's value right BEFORE the call's own "(" is
        consumed, so the matching ")" is the first TOK_CLOSEROUND that
        brings parenDepth back down to it. sharedRegionKnownVars snapshots
        which props vars already existed at that point, so any props var
        that gets declared (var IDENT := new InertiaProps; ...) *inside*
        the lambda body is recognized as new when the region closes --
        deliberately a "new var inside the region" heuristic rather than
        parsing the lambda's `exit ...;` statement, since every real
        registration shape found in the spike declares its own props var
        inline and returns it directly (no case needed a var declared
        outside the call and merely referenced inside it).
      }
      var sharedRegionActive := false;
      var sharedRegionEntryParenDepth: Int32 := 0;
      var sharedRegionKnownVars: HashSet<String> := nil;

      var i: Int32 := 0;
      while i < aTokens.Count do begin
        var tok := aTokens[i];

        if tok.Id = TOK_METHOD then begin
          paramTypes := new Dictionary<String, RawTypeRef>;
          localTypes := new Dictionary<String, RawTypeRef>;
          localNullability := new Dictionary<String, NullabilityKind>;
          propsFields := new Dictionary<String, List<InertiaPropsField>>;
          inMethodBody := false;
          sharedRegionActive := false;
          sharedRegionKnownVars := nil;
          i := ParseMethodParams(aTokens, i, aKnownTypes, paramTypes);
          continue;
        end;

        if tok.Id = TOK_OPENROUND then
          inc(parenDepth)
        else if tok.Id = TOK_CLOSEROUND then begin
          if parenDepth > 0 then dec(parenDepth);
          if sharedRegionActive and (parenDepth = sharedRegionEntryParenDepth) then begin
            var addedCount: Int32 := 0;
            for each key in propsFields.Keys do
              if not sharedRegionKnownVars.Contains(key) then begin
                aSharedData.Fields.AddRange(propsFields[key]);
                addedCount := addedCount + propsFields[key].Count;
              end;
            if addedCount = 0 then
              aDiagnostics.AddWarning('found an AddInertiaSharedData(...) registration that resolved 0 shared keys -- if you used a "{ [''key''] := value }" initializer, note that Oxygene has no working object/collection-initializer syntax and the "{ }" is silently consumed as a comment (see HANDOFF.md §22.3/§27)');
            sharedRegionActive := false;
            sharedRegionKnownVars := nil;
          end;
        end
        else if tok.Id = TOK_BEGIN then begin
          inc(depth);
          if not inMethodBody then begin
            inMethodBody := true;
            methodBodyDepth := depth;
          end;
        end
        else if (tok.Id = TOK_TRY) or (tok.Id = TOK_CASEKW) then
          inc(depth)
        else if tok.Id = TOK_END then begin
          if inMethodBody and (depth = methodBodyDepth) then begin
            inMethodBody := false;
            methodBodyDepth := -1;
            paramTypes := new Dictionary<String, RawTypeRef>;
            localTypes := new Dictionary<String, RawTypeRef>;
            localNullability := new Dictionary<String, NullabilityKind>;
            propsFields := new Dictionary<String, List<InertiaPropsField>>;
            sharedRegionActive := false;
            sharedRegionKnownVars := nil;
          end;
          if depth > 0 then dec(depth);
        end
        else if inMethodBody and (tok.Id = TOK_VAR) then begin
          i := ParseVarDecl(aTokens, i, aKnownTypes, localTypes, localNullability, propsFields);
          continue;
        end
        else if inMethodBody and (tok.Id = TOK_IDENTIFIER) and propsFields.ContainsKey(tok.Text)
                and (i + 1 < aTokens.Count) and (aTokens[i + 1].Id = TOK_OPENBLOCK) then begin
          i := ParsePropsAssignment(aTokens, i, aKnownTypes, paramTypes, localTypes, localNullability, propsFields[tok.Text], aDiagnostics, tok.Text);
          continue;
        end
        else if inMethodBody and (tok.Id = TOK_IDENTIFIER) and (tok.Text = 'Inertia')
                and (i + 3 < aTokens.Count) and (aTokens[i + 1].Id = TOK_DOT) and (aTokens[i + 2].Text = 'Render')
                and (aTokens[i + 3].Id = TOK_OPENROUND) then begin
          i := ParseRenderCall(aTokens, i, propsFields, aResult, aDiagnostics);
          continue;
        end
        else if inMethodBody and (tok.Id = TOK_IDENTIFIER) and (tok.Text = 'Inertia')
                and (i + 3 < aTokens.Count) and (aTokens[i + 1].Id = TOK_DOT) and (aTokens[i + 2].Text = 'Share')
                and (aTokens[i + 3].Id = TOK_OPENROUND) then begin
          i := ParseShareCallExcluded(aTokens, i, aDiagnostics);
          continue;
        end
        else if inMethodBody and (not sharedRegionActive) and (tok.Id = TOK_IDENTIFIER) and (tok.Text = 'AddInertiaSharedData')
                and (i > 0) and (aTokens[i - 1].Id = TOK_DOT)
                and (i + 1 < aTokens.Count) and (aTokens[i + 1].Id = TOK_OPENROUND) then begin
          sharedRegionActive := true;
          sharedRegionEntryParenDepth := parenDepth;
          sharedRegionKnownVars := new HashSet<String>(propsFields.Keys);
        end;

        inc(i);
      end;
    end;

  public
    {
      aSharedData is an in/out accumulator (like aResult): caller passes
      an empty InertiaSharedData, this fills in its Fields from every
      AddInertiaSharedData(...) registration found across every scanned
      file (HANDOFF.md §27) -- not just the file containing it, since
      InertiaNetCore's registration is app-startup configuration that can
      live in any source file, not a fixed conventional one (confirmed in
      the spike report this implementation is based on).
    }
    class method Scan(aSourceDir: String; aRaw: RawAssembly; aDiagnostics: DiagnosticList; aSharedData: InertiaSharedData): List<InertiaPageProps>;
    begin
      result := new List<InertiaPageProps>;
      if not Directory.Exists(aSourceDir) then exit;

      {
        Propagates both IsEnum and IsStruct from RawType directly (not via
        AssemblyLoader.BuildTypeRef -- this dictionary is built from the
        already-loaded RawAssembly, not from a live System.Type), so a
        props/shared-data field typed as one of the target assembly's own
        enums or structs (e.g. "var mode: ThemeMode := ...; shared['Mode']
        := mode;" or "var badge: BadgeDto; props['Badge'] := badge;") is
        recognized as a non-nullable value type by ValueTypeDefaultProvider
        downstream, same as the reflection-based member-typing path
        already is (HANDOFF.md §33 for IsEnum, §35 follow-up for
        IsStruct).
      }
      var knownTypes := new Dictionary<String, RawTypeRef>;
      for each rt in aRaw.Types do begin
        var typeRef := MakeSimpleTypeRef(rt.FullName);
        typeRef.IsEnum := (rt.Kind = RawTypeKind.Enum);
        typeRef.IsStruct := rt.IsStruct;
        knownTypes[rt.Name] := typeRef;
      end;

      var rawPages := new List<InertiaPageProps>;
      for each filePath in Directory.GetFiles(aSourceDir, '*.pas', SearchOption.AllDirectories) do begin
        var text := File.ReadAllText(filePath);
        var tokens := OxygeneTokenizer.Tokenize(text);
        ScanFile(tokens, knownTypes, rawPages, aSharedData, aDiagnostics);
      end;

      {
        Dedup by ComponentName, unioning fields across call sites
        (HANDOFF.md §37) -- see MergePages's own doc comment for why this
        happens here rather than in InertiaIrBuilder.
      }
      result := MergePages(rawPages, aDiagnostics);
    end;
  end;

end.
