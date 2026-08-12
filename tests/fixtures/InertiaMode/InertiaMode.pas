namespace InertiaMode;

uses
  System,
  System.Collections.Generic;

// Fixture for --mode inertia (entry-point-driven type discovery,
// docs/DESIGN.md §3.5, spiked HANDOFF.md §22, implemented HANDOFF.md §24;
// Shared Data spiked/implemented HANDOFF.md §27).
// Inertia/InertiaProps/AppBuilder/HttpContext are minimal stand-ins for
// InertiaNetCore's real types -- just enough to compile a realistic call
// site, matching the same approach as the §22/§27 spike probes.

type
  InertiaProps = public class(Dictionary<String, Object>)
  end;

  HttpContext = public class
  end;

  // Stand-in for IApplicationBuilder -- a plain method rather than an
  // "extension class(IApplicationBuilder)" like InertiaNetCore's real
  // AddInertiaSharedData, since the scanner only cares about the call
  // shape "IDENT . AddInertiaSharedData (", not how the method was
  // declared (HANDOFF.md §27).
  AppBuilder = public class
  public
    method AddInertiaSharedData(middleware: Func<HttpContext, InertiaProps>): AppBuilder;
    begin
      result := self;
    end;
  end;

  Inertia = public static class
  public
    class method Render(component: String; props: InertiaProps): Object;
    begin
      result := nil;
    end;

    class method Share(key: String; value: Object);
    begin
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

  // Reachable only via the AddInertiaSharedData(...) registration below,
  // never from any page's own props -- proves the reachability BFS also
  // walks from shared-data field types, not just page fields.
  SharedUserDto = public class
  public
    property Email: not nullable String read write := '';
  end;

  // Registers app-global shared data via the real InertiaNetCore shape
  // (a statement-bodied lambda declaring its own InertiaProps and
  // `exit`ing it) -- proves AddInertiaSharedData(...) detection and the
  // "new props var declared inside the region" field-collection rule
  // (HANDOFF.md §27). "Flash" deliberately collides, after the default
  // camelCase naming policy, with SharedData's own hardcoded "flash"
  // floor key -- proves DtsEmitter.EmitType's same-interface duplicate-
  // member detection (HANDOFF.md §29/§30), not just that the floor keys
  // exist.
  Startup = public class
  public
    method Configure(app: AppBuilder);
    begin
      app.AddInertiaSharedData(ctx -> begin
        var shared := new InertiaProps;
        shared['Auth'] := new SharedUserDto;
        shared['AppName'] := 'InertiaModeFixture';
        shared['Flash'] := 'collides-with-floor-key';
        exit shared;
      end);
    end;
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
      // "Integer" (Oxygene's standard alias for Int32, docs/HANDOFF.md §32)
      // via an explicit-type-annotated local -- the only shape v1 resolves
      // (HANDOFF.md §24.6) -- proves ResolveTypeName recognizes it, not
      // just the literal "Int32" spelling real Oxygene code rarely uses.
      var age: Integer := 30;
      props['Age'] := age;
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
    // Also has a bare Inertia.Share(...) call, proving it's detected and
    // excluded (with a diagnostic) rather than folded into SharedData --
    // HANDOFF.md §27's conservative v1 classification policy.
    method Empty: Object;
    begin
      Inertia.Share('DebugTrace', 'trace-id-123');
      var props := new InertiaProps;
      result := Inertia.Render('pages/Empty', props);
    end;
  end;

end.
