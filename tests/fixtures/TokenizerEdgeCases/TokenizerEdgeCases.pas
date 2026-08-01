namespace TokenizerEdgeCases;

// Fixture for the tokenizer-sensitive cases the NRT scanner has to get
// right (HANDOFF.md §16). Every member below is named for what it proves.
// Deliberately ends with "end." and NO trailing newline -- that exact input
// is what used to crash the previous SimpleTokenizer-based scanner.

type
  Tricky = public class
  public
    // nullable -- this comment must not annotate the property below it.
    property AfterCommentSayingNullable: String read write;

    { not nullable -- a block comment must not annotate the one below either. }
    property AfterBlockComment: String read write;

    /// <summary>nullable</summary>
    property AfterXmlDocComment: String read write;

    // The default value is a string literal containing NRT keywords; they
    // must be lexed as one string token, not leak onto the next member.
    property WithKeywordDefault: not nullable String read write := 'not nullable';
    property AfterKeywordDefault: String read write;

    // Genuinely annotated, to prove the scanner still fires normally here.
    property ExplicitlyNullable: nullable String read write;
    property ExplicitlyNotNullable: not nullable String read write := '';

    // Multi-identifier declaration: both names must get the annotation.
    FirstName, LastName: nullable String;
  end;

end.