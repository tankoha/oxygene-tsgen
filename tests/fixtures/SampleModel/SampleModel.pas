namespace SampleModel;

type
  Status = public enum (Active, Inactive, Pending);

  // Oxygene "record" (a CLR struct/value type, docs/DESIGN.md §7 task 2,
  // HANDOFF.md §35) -- mirrors TeaTimeTracker's own Rating record exactly
  // (three Integer properties), the real-world shape this fixture exists
  // to prove tsgen handles: emitted as an ordinary `export interface`,
  // referenced by full name from User.CurrentRating below rather than
  // falling back to `unknown`.
  Rating = public record
  public
    property Aroma: Integer read write;
    property Taste: Integer read write;
    property Overall: Integer read write;
  end;

  User = public class
  public
    property Id: not nullable String read write := '';
    property DisplayName: nullable String read write;
    property Age: Int32 read write;
    property IsAdmin: Boolean read write;

    // Unannotated reference type: stays genuinely Unknown even after the
    // ValueTypeDefaultProvider addition (that provider only resolves
    // value types), so this is what keeps --nrt-unknown-policy actually
    // discriminating something in this fixture -- Age/IsAdmin no longer
    // do, now that they resolve to not-nullable unconditionally.
    property Notes: String read write;

    // Unannotated enum-typed property, deliberately no nullable/not
    // nullable annotation -- HANDOFF.md §33: enums are CLR value types,
    // so this must resolve to non-null via ValueTypeDefaultProvider's
    // RawTypeRef.IsEnum check, exactly like Age/IsAdmin, not fall back to
    // --nrt-unknown-policy's default like Notes does. Reuses the Status
    // enum already declared above, which no member referenced before this
    // fixture addition.
    property CurrentStatus: Status read write;

    // System.DateOnly (docs/DESIGN.md §7 task 1, HANDOFF.md §34):
    // unannotated, value-typed -- like Age/IsAdmin/CurrentStatus above,
    // must resolve to non-null via ValueTypeDefaultProvider, mapped to TS
    // `string` (ISO "yyyy-MM-dd") by TypeMapper.
    property RegisteredOn: DateOnly read write;

    // Struct-typed (record) property, unannotated -- must resolve to a
    // fully-qualified named-type reference (SampleModel.Rating), not
    // `unknown`, proving AssemblyLoader.Load's struct-admission fix
    // reaches the IR/Emitter end to end (HANDOFF.md §35).
    property CurrentRating: Rating read write;

    FirstName, LastName: nullable String;
  end;

end.
