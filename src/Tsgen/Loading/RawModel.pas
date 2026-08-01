namespace Tsgen.Loading;

uses
  System.Collections.Generic;

type
  RawMemberKind = public enum (Field, PropertyMember);

  RawMember = public class
  public
    Name: String;
    Kind: RawMemberKind;
    ClrTypeName: String;
  end;

  RawEnumValue = public class
  public
    Name: String;
    Value: Int64;
  end;

  RawTypeKind = public enum (ClassLike, Enum);

  RawType = public class
  public
    FullName: String;
    NamespaceName: String;
    Name: String;
    Kind: RawTypeKind;
    Members: List<RawMember> := new List<RawMember>;
    EnumValues: List<RawEnumValue> := new List<RawEnumValue>;
  end;

  RawAssembly = public class
  public
    Types: List<RawType> := new List<RawType>;
  end;

end.
