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
    `new NamedType(...)` expressions. Deliberately NOT resolved this
    round (falls back to Unknown + a diagnostic naming the unresolved
    key, per §24 scope decision): `new class(...)` anonymous-literal
    values, generic-typed parameters/locals, conditional/branch-dependent
    key-setting, keys set via a helper-method call,
    `Inertia.Defer(...)`/`Inertia.Merge(...)`-wrapped values, dynamically
    computed keys, and props built in a different method/class than
    where `Render` is called.
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
    const TOK_ASSIGN = Token.T_Assignment;
    const TOK_BEGIN = Token.TI_begin;
    const TOK_TRY = Token.TI_try;
    const TOK_CASEKW = Token.TI_case;
    const TOK_END = Token.TI_end;
    const TOK_METHOD = Token.TI_method;
    const TOK_VAR = Token.TI_var;
    const TOK_NEW = Token.TI_new;
    const TOK_CLASS = Token.TI_class;
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
      Resolves a type NAME as written in source (e.g. "UserDto", "Int32")
      -- never a generic/array spelling, those are out of scope for v1
      (see the class-level doc comment) -- to a RawTypeRef, or nil if
      unresolvable. Checks Oxygene's built-in BCL aliases first, then
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
      else if aKnownTypes.ContainsKey(aWrittenName) then
        result := aKnownTypes[aWrittenName]
      else
        result := nil;
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
      `var IDENT : TypeName [:= ...];` starting at the `var` token.
      Populates aLocalTypes always; additionally registers IDENT in
      aPropsFields (with an empty field list to accumulate into) when its
      resolved type is named exactly "InertiaProps" or "Dictionary" --
      the only two shapes confirmed usable for Inertia props construction
      (§22.1/§22.3). Returns the index to resume scanning from.
    }
    class method ParseVarDecl(aTokens: List<ScanToken>; aVarIdx: Int32; aKnownTypes: Dictionary<String, RawTypeRef>;
                               aLocalTypes: Dictionary<String, RawTypeRef>; aPropsFields: Dictionary<String, List<InertiaPropsField>>): Int32;
    begin
      var i := aVarIdx + 1;
      if (i >= aTokens.Count) or (aTokens[i].Id <> TOK_IDENTIFIER) then begin
        result := i;
        exit;
      end;
      var varName := aTokens[i].Text;
      inc(i);

      var writtenName := '';
      if (i < aTokens.Count) and (aTokens[i].Id = TOK_ASSIGN) then begin
        // var IDENT := new TypeName ...
        inc(i);
        if (i + 1 < aTokens.Count) and (aTokens[i].Id = TOK_NEW) and (aTokens[i + 1].Id = TOK_IDENTIFIER) then
          writtenName := aTokens[i + 1].Text;
      end
      else if (i < aTokens.Count) and (aTokens[i].Id = TOK_COLON) then begin
        // var IDENT : TypeName [:= ...]
        inc(i);
        if (i < aTokens.Count) and (aTokens[i].Id = TOK_IDENTIFIER) then
          writtenName := aTokens[i].Text;
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

      var resolvedType := ResolveTypeName(writtenName, aKnownTypes);
      if resolvedType <> nil then
        aLocalTypes[varName] := resolvedType;

      if (writtenName = 'InertiaProps') or (writtenName = 'Dictionary') then
        aPropsFields[varName] := new List<InertiaPropsField>;
    end;

    {
      Parses `IDENT [ 'key' ] := valueExpr ;` starting at IDENT (already
      confirmed present in aPropsFields), appending one field to
      aFieldList when the value resolves, or warning via aDiagnostics
      (naming aVarName and the key) when it doesn't. Returns the index to
      resume scanning from.
    }
    class method ParsePropsAssignment(aTokens: List<ScanToken>; aIdentIdx: Int32; aKnownTypes: Dictionary<String, RawTypeRef>;
                                       aParamTypes: Dictionary<String, RawTypeRef>; aLocalTypes: Dictionary<String, RawTypeRef>;
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

    class method ScanFile(aTokens: List<ScanToken>; aKnownTypes: Dictionary<String, RawTypeRef>; aResult: List<InertiaPageProps>;
                           aSharedData: InertiaSharedData; aDiagnostics: DiagnosticList);
    begin
      var depth: Int32 := 0;
      var parenDepth: Int32 := 0;
      var inMethodBody := false;
      var methodBodyDepth: Int32 := -1;
      var paramTypes := new Dictionary<String, RawTypeRef>;
      var localTypes := new Dictionary<String, RawTypeRef>;
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
            propsFields := new Dictionary<String, List<InertiaPropsField>>;
            sharedRegionActive := false;
            sharedRegionKnownVars := nil;
          end;
          if depth > 0 then dec(depth);
        end
        else if inMethodBody and (tok.Id = TOK_VAR) then begin
          i := ParseVarDecl(aTokens, i, aKnownTypes, localTypes, propsFields);
          continue;
        end
        else if inMethodBody and (tok.Id = TOK_IDENTIFIER) and propsFields.ContainsKey(tok.Text)
                and (i + 1 < aTokens.Count) and (aTokens[i + 1].Id = TOK_OPENBLOCK) then begin
          i := ParsePropsAssignment(aTokens, i, aKnownTypes, paramTypes, localTypes, propsFields[tok.Text], aDiagnostics, tok.Text);
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

      var knownTypes := new Dictionary<String, RawTypeRef>;
      for each rt in aRaw.Types do
        knownTypes[rt.Name] := MakeSimpleTypeRef(rt.FullName);

      for each filePath in Directory.GetFiles(aSourceDir, '*.pas', SearchOption.AllDirectories) do begin
        var text := File.ReadAllText(filePath);
        var tokens := OxygeneTokenizer.Tokenize(text);
        ScanFile(tokens, knownTypes, result, aSharedData, aDiagnostics);
      end;
    end;
  end;

end.
