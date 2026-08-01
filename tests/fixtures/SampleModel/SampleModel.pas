namespace SampleModel;

type
  Status = public enum (Active, Inactive, Pending);

  User = public class
  public
    property Id: not nullable String read write := '';
    property DisplayName: nullable String read write;
    property Age: Int32 read write;
    property IsAdmin: Boolean read write;

    FirstName, LastName: nullable String;
  end;

end.
