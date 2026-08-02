namespace Generics;

// Fixture exercising generics support (docs/DESIGN.md §10.2 item 1):
// List<T> (both a named-type element and a self-referential element),
// Dictionary<String,T> -> Record<string,T>, Nullable<T> -> unwrapped
// leaf type + auto-detected nullability, and a plain array. Node is
// self-referential via List<Node> to confirm named-reference generics
// (as opposed to structurally *expanding* generics) don't cause an
// infinite loop -- the reason full cycle detection (Tarjan SCC) was
// deferred this round (see HANDOFF.md).

type
  Tag = public class
  public
    property Label: not nullable String read write := '';
  end;

  Node = public class
  public
    property Value: not nullable String read write := '';
    property Children: List<Node> read write;
    property Tags: List<Tag> read write;
    property Scores: List<Int32> read write;
    property Lookup: Dictionary<String, Int32> read write;
    property MaybeCount: nullable Int32 read write;
    property Numbers: array of Int32 read write;
  end;

end.
