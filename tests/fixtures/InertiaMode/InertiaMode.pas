namespace InertiaMode;

uses
  System.Collections.Generic;

// Fixture for --mode inertia (entry-point-driven type discovery,
// docs/DESIGN.md §3.5, spiked HANDOFF.md §22, implemented HANDOFF.md §24).
// Inertia/InertiaProps are minimal stand-ins for InertiaNetCore's real
// types -- just enough to compile a realistic call site, matching the
// same approach as the §22 spike probe.

type
  InertiaProps = public class(Dictionary<String, Object>)
  end;

  Inertia = public static class
  public
    class method Render(component: String; props: InertiaProps): Object;
    begin
      result := nil;
    end;
  end;

  // Reachable only transitively, via UserDto.Role -- never referenced
  // directly by any props field. Proves the BFS reachability walk, not
  // just direct-reference resolution.
  RoleDto = public class
  public
    property Name: not nullable String read write := '';
  end;

  UserDto = public class
  public
    property Email: not nullable String read write := '';
    property Role: RoleDto read write;
  end;

  // Constructed inline via "new MetaDto" (no parens -- a no-arg
  // constructor call) as a props value, not via a parameter. Proves the
  // no-parens "new NamedType" value-expression shape.
  MetaDto = public class
  public
    property Title: not nullable String read write := '';
  end;

  // Deliberately never reachable from any page -- must NOT appear in
  // the output. Proves the reachability filter actually filters.
  UnusedDto = public class
  public
    property Nothing: not nullable String read write := '';
  end;

  Controller = public class
  public
    method Profile(aUser: UserDto): Object;
    begin
      var props := new InertiaProps;
      props['User'] := aUser;
      props['IsAdmin'] := true;
      props['Bio'] := 'hello';
      props['Meta'] := new MetaDto;
      props['Note'] := SomeHelper();
      result := Inertia.Render('pages/Profile', props);
    end;

    method SomeHelper: String;
    begin
      result := 'x';
    end;

    // Props-less page (declared, never assigned) -- a legitimate case
    // per InertiaScanner.pas's ParseRenderCall comment. Exercises the
    // FormErrorsLike `never`-fallback in DtsEmitter.EmitType, since a
    // zero-field page can't produce a valid union of string literals.
    method Empty: Object;
    begin
      var props := new InertiaProps;
      result := Inertia.Render('pages/Empty', props);
    end;
  end;

end.
