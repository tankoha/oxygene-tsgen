namespace Tsgen.Nrt;

uses
  System.Collections.Generic,
  System.IO,
  System.Text,
  RemObjects.Elements.Code.Oxygene;

type
  NullabilityKind = public enum (Unknown, IsNullable, IsNotNullable);

  {
    Heuristic scanner, not a full parser. Scoped to properties and fields
    declared directly inside a top-level type body (see HANDOFF.md §11 for
    the scope decision). Indexer-style properties ("property Item[Index:
    Int32]: ...") are supported -- the bracketed parameter list is skipped
    to find the colon that introduces the property's own type, matching
    reflection's view (PropertyInfo.Name = "Item", ignoring the index
    parameters). Multiple type declarations under one `type` section are
    supported too, since currentTypeName/typeDepth reset on each type's
    closing `end` regardless of how many types share the section.

    Known limitation, unchanged: nested types within a single file are not
    specifically supported -- currentTypeName/typeDepth are only assigned
    once, on the first class/record/interface open, so a nested type's own
    members are never attributed to the nested type itself. The
    (depth = typeDepth) guard on every member-scanning branch (added after
    a Fable5 review caught this, HANDOFF.md §20) means those members are
    now correctly IGNORED rather than misattributed to the outer type --
    earlier reasoning here claimed this gap was harmless because
    AssemblyLoader filters nested types out (t.IsNested) and DtsEmitter has
    no nested-interface output, so nested members "never reach the
    generated .d.ts regardless of what the scanner attributes them to". That
    was wrong: before the guard, a nested type's annotated member could
    silently overwrite an OUTER, same-named member's entry in the result
    dictionary (ScanMemberDecl writes unconditionally), corrupting output
    that DOES reach the .d.ts -- see tests/fixtures/NestedTypeCollision for
    the regression case. Supporting nested types FOR REAL (giving a nested
    type's own members their own output) still needs matching changes in
    AssemblyLoader and DtsEmitter, not just here -- see HANDOFF.md for the
    decision to leave that out of scope for now. The point is narrower than
    it used to be: only "ignore nested-type members without corrupting
    anything" is guaranteed today, not "attribute them correctly".

    Token IDs are read directly off RemObjects.Elements.Code.Oxygene.Token
    (the same public static constants the tokenizer itself uses) rather
    than hardcoded as local magic numbers, since Elements is a
    weekly-release product (HANDOFF.md §3) and these are compiler-internal
    ordinals that could renumber across versions.

    Tokenizing goes through Tsgen.Nrt.OxygeneTokenizer (extracted out to
    a shared unit, HANDOFF.md §24, once Tsgen.Inertia.InertiaScanner
    needed the identical token-stream setup), which drives the real
    Oxygene tokenizer over the whole file at once (see HANDOFF.md §16).
    Everything below this layer works off the ScanToken list, so the
    tokenizer stays swappable behind OxygeneTokenizer.Tokenize().
  }
  NullabilityScanner = public static class
  private
    const TOK_IDENTIFIER = Token.T_Identifier;
    const TOK_EQUAL = Token.T_Equal;
    const TOK_COLON = Token.T_Colon;
    const TOK_SEMICOLON = Token.T_SemiColon;
    const TOK_COMMA = Token.T_Comma;
    const TOK_OPENROUND = Token.T_OpenRound;
    const TOK_CLOSEROUND = Token.T_CloseRound;
    const TOK_OPENBLOCK = Token.T_OpenBlock;
    const TOK_CLOSEBLOCK = Token.T_CloseBlock;
    const TOK_DOT = Token.T_Dot;
    const TOK_CLASS = Token.TI_class;
    const TOK_RECORD = Token.TI_record;
    const TOK_INTERFACE = Token.TI_interface;
    const TOK_BEGIN = Token.TI_begin;
    const TOK_TRY = Token.TI_try;
    const TOK_CASEKW = Token.TI_case;
    const TOK_END = Token.TI_end;
    const TOK_PROPERTY = Token.TI_property;
    const TOK_NULLABLE = Token.TI_nullable;
    const TOK_NOT = Token.TI_not;
    const TOK_NAMESPACE = Token.TI_namespace;

    class method IsTypeOpen(aTokens: List<ScanToken>; aIndex: Int32): Boolean;
    begin
      result := false;
      var j := aIndex - 1;
      var steps := 0;
      while (j >= 0) and (steps < 64) do begin
        var id := aTokens[j].Id;
        if id = TOK_EQUAL then begin
          result := true;
          exit;
        end;
        if (id = TOK_SEMICOLON) or (id = TOK_BEGIN) or (id = TOK_END) then exit;
        dec(j);
        inc(steps);
      end;
    end;

    class method FindTypeNameBefore(aTokens: List<ScanToken>; aIndex: Int32): String;
    begin
      result := '';
      var j := aIndex - 1;
      while (j >= 0) and (aTokens[j].Id <> TOK_EQUAL) do
        dec(j);
      dec(j);
      if (j >= 0) and (aTokens[j].Id = TOK_IDENTIFIER) then
        result := aTokens[j].Text;
    end;

    class method ScanMemberDecl(aTokens: List<ScanToken>; aColonIndex: Int32; aTypeFullName: String; aMemberName: String; aResult: Dictionary<String, NullabilityKind>);
    begin
      var j := aColonIndex + 1;
      var isNot := false;
      if (j < aTokens.Count) and (aTokens[j].Id = TOK_NOT) then begin
        isNot := true;
        inc(j);
      end;

      var kind := NullabilityKind.Unknown;
      if (j < aTokens.Count) and (aTokens[j].Id = TOK_NULLABLE) then begin
        if isNot then kind := NullabilityKind.IsNotNullable
        else kind := NullabilityKind.IsNullable;
      end;

      if kind <> NullabilityKind.Unknown then begin
        var key := aTypeFullName + '.' + aMemberName;
        aResult[key] := kind;
      end;
    end;

    class method ScanFile(aTokens: List<ScanToken>; aResult: Dictionary<String, NullabilityKind>);
    begin
      var ns := '';
      var i: Int32 := 0;
      while i < aTokens.Count do begin
        if aTokens[i].Id = TOK_NAMESPACE then begin
          var sb := new StringBuilder;
          var j := i + 1;
          while (j < aTokens.Count) and ((aTokens[j].Id = TOK_IDENTIFIER) or (aTokens[j].Id = TOK_DOT)) do begin
            sb.Append(aTokens[j].Text);
            inc(j);
          end;
          ns := sb.ToString();
          break;
        end;
        inc(i);
      end;

      var depth: Int32 := 0;
      var parenDepth: Int32 := 0;
      var currentTypeName: String := '';
      var typeDepth: Int32 := -1;

      i := 0;
      while i < aTokens.Count do begin
        var tok := aTokens[i];

        if tok.Id = TOK_OPENROUND then
          inc(parenDepth)
        else if tok.Id = TOK_CLOSEROUND then begin
          if parenDepth > 0 then dec(parenDepth);
        end
        else if (tok.Id = TOK_BEGIN) or (tok.Id = TOK_TRY) or (tok.Id = TOK_CASEKW) then
          inc(depth)
        else if (tok.Id = TOK_CLASS) or (tok.Id = TOK_RECORD) or (tok.Id = TOK_INTERFACE) then begin
          if IsTypeOpen(aTokens, i) then begin
            inc(depth);
            if String.IsNullOrEmpty(currentTypeName) then begin
              var simpleName := FindTypeNameBefore(aTokens, i);
              if not String.IsNullOrEmpty(simpleName) then begin
                if String.IsNullOrEmpty(ns) then currentTypeName := simpleName
                else currentTypeName := ns + '.' + simpleName;
                typeDepth := depth;
              end;
            end;
          end;
        end
        else if tok.Id = TOK_END then begin
          if (depth = typeDepth) and (depth > 0) then begin
            currentTypeName := '';
            typeDepth := -1;
          end;
          if depth > 0 then dec(depth);
        end
        else if tok.Id = TOK_PROPERTY then begin
          {
            The (depth = typeDepth) guard matters: without it, a "property"
            token found while inside a NESTED type's body (typeDepth still
            points at the OUTER type, since currentTypeName/typeDepth are
            only assigned once per outer type) would get attributed to the
            outer type anyway. That doesn't just leave the nested member's
            own annotation unrecorded -- ScanMemberDecl's unconditional
            aResult[key] := kind can silently overwrite an OUTER member of
            the same name with the nested member's (opposite) nullability,
            corrupting output that DOES reach the emitted .d.ts. The field
            branches below already had this guard; this branch didn't.
          }
          if (not String.IsNullOrEmpty(currentTypeName)) and (depth = typeDepth) and (i + 1 < aTokens.Count)
             and (aTokens[i + 1].Id = TOK_IDENTIFIER) then begin
            var memberName := aTokens[i + 1].Text;
            var colonIndex := i + 2;
            if (colonIndex < aTokens.Count) and (aTokens[colonIndex].Id = TOK_OPENBLOCK) then begin
              {
                Indexer-style property, e.g.
                "property Item[Index: Int32]: nullable String read ... write ...;".
                Skip the bracketed parameter list to find the colon that
                introduces the property's own type -- reflection loads this
                as a property named "Item" (PropertyInfo.Name ignores the
                index parameters), so the member name stays the identifier
                before "[", not anything inside the brackets.
              }
              var bracketDepth := 1;
              inc(colonIndex);
              while (colonIndex < aTokens.Count) and (bracketDepth > 0) do begin
                if aTokens[colonIndex].Id = TOK_OPENBLOCK then inc(bracketDepth)
                else if aTokens[colonIndex].Id = TOK_CLOSEBLOCK then dec(bracketDepth);
                inc(colonIndex);
              end;
            end;
            if (colonIndex < aTokens.Count) and (aTokens[colonIndex].Id = TOK_COLON) then
              ScanMemberDecl(aTokens, colonIndex, currentTypeName, memberName, aResult);
          end;
        end
        else if (tok.Id = TOK_IDENTIFIER) and (parenDepth = 0) and (typeDepth >= 0) and (depth = typeDepth)
                and (i + 1 < aTokens.Count) and (aTokens[i + 1].Id = TOK_COLON) then
          ScanMemberDecl(aTokens, i + 1, currentTypeName, tok.Text, aResult)
        else if (tok.Id = TOK_IDENTIFIER) and (parenDepth = 0) and (typeDepth >= 0) and (depth = typeDepth)
                and (i + 1 < aTokens.Count) and (aTokens[i + 1].Id = TOK_COMMA) then begin
          {
            Multi-name field declaration, e.g. "A, B: nullable String;".
            Without this, only the identifier immediately before the colon
            (here "B") would be recorded and "A" would silently stay
            Unknown -- two fields declared together getting different
            nullability in the output.
          }
          var names := new List<String>;
          names.Add(tok.Text);
          var j := i + 1;
          while (j < aTokens.Count) and (aTokens[j].Id = TOK_COMMA) do begin
            inc(j);
            if (j < aTokens.Count) and (aTokens[j].Id = TOK_IDENTIFIER) then begin
              names.Add(aTokens[j].Text);
              inc(j);
            end
            else
              break;
          end;
          if (j < aTokens.Count) and (aTokens[j].Id = TOK_COLON) then begin
            for each nm in names do
              ScanMemberDecl(aTokens, j, currentTypeName, nm, aResult);
          end;
        end;

        inc(i);
      end;
    end;

  public
    class method Scan(aSourceDir: String): Dictionary<String, NullabilityKind>;
    begin
      result := new Dictionary<String, NullabilityKind>;
      if not Directory.Exists(aSourceDir) then exit;

      for each filePath in Directory.GetFiles(aSourceDir, '*.pas', SearchOption.AllDirectories) do begin
        var text := File.ReadAllText(filePath);
        var tokens := OxygeneTokenizer.Tokenize(text);
        ScanFile(tokens, result);
      end;
    end;
  end;

end.
