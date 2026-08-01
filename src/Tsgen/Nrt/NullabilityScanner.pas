namespace Tsgen.Nrt;

uses
  System.Collections.Generic,
  System.IO,
  System.Text,
  RemObjects.Elements.Oxygene,
  RemObjects.Elements.Code.Oxygene;

type
  NullabilityKind = public enum (Unknown, IsNullable, IsNotNullable);

  ScanToken = public class
  public
    Id: Int32;
    Text: String;
  end;

  {
    Heuristic scanner, not a full parser. Scoped to properties and fields
    declared directly inside a top-level type body (see HANDOFF.md §11 for
    the scope decision). Known limitation: nested types within a single
    file are not specifically supported -- the OUTER type's name is what
    "wins" for any member the scanner walks past while still inside a
    nested type's body (currentTypeName is only assigned once, on the
    first class/record/interface open), so a nested type's own members
    get incorrectly attributed to the outer type's key. Fine for the
    Inertia Page Props POCOs this targets (flat classes, no nesting), but
    should be hardened with real project fixtures before relying on it
    more broadly.

    Token IDs are read directly off RemObjects.Elements.Code.Oxygene.Token
    (the same public static constants the tokenizer itself uses) rather
    than hardcoded as local magic numbers, since Elements is a
    weekly-release product (HANDOFF.md §3) and these are compiler-internal
    ordinals that could renumber across versions.
  }
  NullabilityScanner = public static class
  private
    const TOK_WHITESPACE = Token.TINT_WhiteSpace;
    const TOK_COMMENT = Token.TINT_Comment;
    const TOK_XMLDOC = Token.TINT_XmlDocComment;
    const TOK_IDENTIFIER = Token.T_Identifier;
    const TOK_EQUAL = Token.T_Equal;
    const TOK_COLON = Token.T_Colon;
    const TOK_SEMICOLON = Token.T_SemiColon;
    const TOK_COMMA = Token.T_Comma;
    const TOK_OPENROUND = Token.T_OpenRound;
    const TOK_CLOSEROUND = Token.T_CloseRound;
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

    class method Tokenize(aText: String): List<ScanToken>;
    begin
      result := new List<ScanToken>;
      var offset: Int32 := 0;
      var safety: Int32 := aText.Length + 16;
      while (offset < aText.Length) and (safety > 0) do begin
        dec(safety);
        var remaining := aText.Substring(offset);
        var trimmedCheck := remaining.Trim;
        if (trimmedCheck.Length = 0) or (trimmedCheck = '.') then break;

        SimpleTokenizer.Parse(remaining);
        if SimpleTokenizer.Items.Count = 0 then break;
        var t := SimpleTokenizer.Items[0];
        if t.Length <= 0 then break;

        var text := remaining.Substring(t.StartPos, t.Length);
        if (t.Token <> TOK_WHITESPACE) and (t.Token <> TOK_COMMENT) and (t.Token <> TOK_XMLDOC) then begin
          var st := new ScanToken;
          st.Id := t.Token;
          st.Text := text;
          result.Add(st);
        end;
        offset := offset + t.StartPos + t.Length;
      end;
    end;

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
          if (not String.IsNullOrEmpty(currentTypeName)) and (i + 2 < aTokens.Count)
             and (aTokens[i + 1].Id = TOK_IDENTIFIER) and (aTokens[i + 2].Id = TOK_COLON) then
            ScanMemberDecl(aTokens, i + 2, currentTypeName, aTokens[i + 1].Text, aResult);
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
        var tokens := Tokenize(text);
        ScanFile(tokens, result);
      end;
    end;
  end;

end.
