namespace MultiTypeAndIndexer;

// Fixture for two scanner behaviors HANDOFF.md's §12.6/§16.4 limitations
// list flagged as untested: (1) multiple type declarations sharing one
// `type` section correctly reset currentTypeName between types instead of
// leaking into the next type's members, and (2) indexer-style properties
// ("property Item[...]: ...") are detected instead of being silently
// skipped.

type
  Kind = public enum (Foo, Bar);

  // Alpha and Beta both declare a "Name" property with OPPOSITE
  // nullability right after each other in the same `type` section -- if
  // currentTypeName ever leaked from one type into the next, one of these
  // would silently pick up the other's annotation.
  Alpha = public class
  public
    property Name: nullable String read write;
  end;

  Beta = public class
  public
    property Name: not nullable String read write := '';

    // Indexer-style property: reflection loads this as a property named
    // "Item" (PropertyInfo.Name ignores the index parameter), so the
    // scanner needs to skip past "[aIndex: Int32]" to find the colon that
    // introduces the property's own (not nullable) type.
    property Item[aIndex: Int32]: not nullable String read GetItem write SetItem;

    // Unannotated, to keep this member distinguishable from Item's
    // explicit not-nullable under both --nrt-unknown-policy settings.
    property Count: Int32 read write;
  private
    method GetItem(aIndex: Int32): not nullable String;
    begin
      result := '';
    end;
    method SetItem(aIndex: Int32; aValue: not nullable String);
    begin
    end;
  end;

end.
