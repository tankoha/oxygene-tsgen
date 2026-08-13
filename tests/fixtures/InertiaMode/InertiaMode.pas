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

  // A record (CLR struct), not a class -- proves the source-scan path
  // (InertiaScanner.Scan's aKnownTypes construction) propagates
  // RawType.IsStruct the same way it already propagates IsEnum
  // (HANDOFF.md §33): an unannotated struct-typed local passed to props
  // must resolve non-null, not "| null", since that propagation is this
  // task's second call site (the enum version of this same fix was only
  // ever proven against a real DLL, never pinned by a snapshot -- see
  // HANDOFF.md §35's follow-up finding).
  BadgeDto = public record
  public
    property Points: Integer read write;
  end;

  // Reachable ONLY as the element type of a "var tags: List<TagDto>"
  // annotated local -- never named directly by a props field, and not a
  // member of any other reachable type either. Same spirit as RoleDto's
  // transitive-only reachability above, one level further out: it proves
  // InertiaIrBuilder.CollectReferencedTypes walks a generic
  // RawTypeRef's TypeArguments, which only produces an edge at all once
  // InertiaScanner.ParseTypeAnnotation builds a structural generic type
  // ref for the colon annotation.
  TagDto = public class
  public
    property Label: not nullable String read write := '';
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
      // System.DateOnly (docs/DESIGN.md §7 task 1, HANDOFF.md §34): proves
      // InertiaScanner.ResolveTypeName's own DateOnly branch, not just
      // TypeMapper/ValueTypeDefaultProvider's (already covered by
      // SampleModel's reflection-based RegisteredOn property).
      var joined: DateOnly := new DateOnly(2024, 1, 1);
      props['Joined'] := joined;
      // Struct-typed (record) local, unannotated declaration with no
      // initializer -- a real pattern (a value-typed local defaults to
      // its zero value without assignment). Proves InertiaScanner's
      // source-scan path resolves an unannotated struct-typed field to
      // non-null (HANDOFF.md §35 follow-up), not "| null".
      var badge: BadgeDto;
      props['Badge'] := badge;
      // Generic colon annotation -- the exact shape TeaTimeTracker's own
      // RecordsController.Index uses ("var records:
      // List<TastingRecordSummary> := fRepository.GetAll();") and the
      // only generic spelling InertiaScanner.ParseTypeAnnotation
      // resolves. TagDto is reachable only as this list's element type.
      var tags: List<TagDto> := new List<TagDto>;
      props['Tags'] := tags;
      // Two type arguments, both resolving -- maps to a TS Record type
      // downstream. Reuses RoleDto rather than introducing a second new
      // type, keeping this fixture's type count down.
      var lookup: Dictionary<String, RoleDto> := new Dictionary<String, RoleDto>;
      props['Lookup'] := lookup;
      // Explicit nullability annotations on props locals (HANDOFF.md
      // §40). These two exist to prove the annotation beats
      // --nrt-unknown-policy in BOTH directions, which is the whole
      // point of having them: a props field is invisible to the
      // provider chain, so without an annotation its nullability is
      // whatever the policy flag happens to say.
      //   - SureTags must stay non-null in the DEFAULT case, where the
      //     policy is "nullable" and every other unannotated
      //     reference-typed field here renders "| null".
      //   - MaybeNote must keep its "| null" in the NON-NULL case,
      //     where the policy strips it off every unannotated one.
      var sureTags: not nullable List<TagDto> := new List<TagDto>;
      props['SureTags'] := sureTags;
      var maybeNote: nullable String := 'maybe';
      props['MaybeNote'] := maybeNote;
      result := Inertia.Render('pages/Profile', props);
    end;

    method SomeHelper: String;
    begin
      result := 'x';
    end;

    // Second Inertia.Render call site for the SAME component
    // ("pages/Profile", also rendered from Profile above) -- the real-DLL
    // pattern found in TeaTimeTracker (a GET action + a POST action both
    // re-rendering the same page, e.g. on validation failure) that
    // originally produced a duplicate `ProfileProps`/`ProfileFormErrors`
    // declaration and, for the type-alias `ProfileFormErrors` specifically,
    // an invalid "Duplicate identifier" .d.ts (HANDOFF.md §37). Exercises
    // all three merge cases InertiaScanner.MergePages handles:
    //   - "Bio": same key, same resolved type (String) as Profile's own
    //     "Bio" -- merges silently, no warning.
    //   - "IsAdmin": same key, but String here vs Boolean in Profile --
    //     a genuine type conflict, must warn and keep Profile's Boolean
    //     (first-resolved) rather than silently overwriting it.
    //   - "SavedAt": a key ONLY this call site sets -- must still appear
    //     in the merged ProfileProps/ProfileFormErrors (union, not
    //     intersection).
    method SaveProfile: Object;
    begin
      var props := new InertiaProps;
      props['Bio'] := 'saved-bio';
      props['IsAdmin'] := 'yes';
      props['SavedAt'] := 'now';
      result := Inertia.Render('pages/Profile', props);
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
