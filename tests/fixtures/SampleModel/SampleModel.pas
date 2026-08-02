namespace SampleModel;

type
  Status = public enum (Active, Inactive, Pending);

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

    FirstName, LastName: nullable String;
  end;

end.
