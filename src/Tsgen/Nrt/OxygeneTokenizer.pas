namespace Tsgen.Nrt;

uses
  System.Collections.Generic,
  RemObjects.Elements,
  RemObjects.Elements.Code,
  RemObjects.Elements.Oxygene,
  RemObjects.Elements.Code.Oxygene;

type
  ScanToken = public class
  public
    Id: Int32;
    Text: String;
  end;

  {
    Shared tokenizing entry point, extracted out of NullabilityScanner
    (HANDOFF.md §16) when Tsgen.Inertia.InertiaScanner needed the exact
    same token-stream setup -- both scan Oxygene source at the token
    level and neither needs anything heavier. Drives the real Oxygene
    tokenizer over a whole file at once via
    RemObjects.Elements.Code.TokenStream.
  }
  OxygeneTokenizer = public static class
  private
    const TOK_WHITESPACE = Token.TINT_WhiteSpace;
    const TOK_COMMENT = Token.TINT_Comment;
    const TOK_XMLDOC = Token.TINT_XmlDocComment;
    const TOK_EOF = Token.T_EOF;

    class var fLanguageRegistered: Boolean := false;

    {
      TokenStream's constructor resolves a language provider out of the
      global RemObjects.Elements.Languages registry, and merely referencing
      RemObjects.Elements.Oxygene.dll does not populate it -- without this,
      construction throws "Unsupported Language: Oxygene". Registering is a
      process-wide, one-time side effect, hence the guard.
    }
    class method EnsureLanguageRegistered;
    begin
      if not fLanguageRegistered then begin
        Languages.Register(new OxygeneLanguage);
        fLanguageRegistered := true;
      end;
    end;

  public
    class method Tokenize(aText: String): List<ScanToken>;
    begin
      result := new List<ScanToken>;
      if String.IsNullOrEmpty(aText) then exit;

      EnsureLanguageRegistered;

      var stream := new TokenStream(FragmentType.Oxygene, false);
      stream.SetText(aText);

      {
        Items is a capacity-sized array, so Count is what bounds the loop
        -- reading Items.Length would walk past the live fragments.
      }
      for i: Int32 := 0 to stream.Count - 1 do begin
        var frag := stream.Items[i];

        // Every stream ends with a zero-length T_EOF fragment.
        if frag.Token = TOK_EOF then continue;

        {
          IsWhitespace already covers whitespace and comment fragments; the
          explicit ID checks keep the exact filter the scanner had before
          this went through TokenStream, in case a trivia kind exists that
          IsWhitespace does not claim.
        }
        if frag.IsWhitespace then continue;
        if (frag.Token = TOK_WHITESPACE) or (frag.Token = TOK_COMMENT) or (frag.Token = TOK_XMLDOC) then continue;

        var st := new ScanToken;
        st.Id := frag.Token;
        {
          GetString() rather than slicing aText: for an &-escaped
          identifier (&class used as a member name) the tokenizer reports
          it as T_Identifier with the & already stripped, which is what the
          reflection side sees as the member name.
        }
        st.Text := frag.GetString();
        result.Add(st);
      end;
    end;
  end;

end.
