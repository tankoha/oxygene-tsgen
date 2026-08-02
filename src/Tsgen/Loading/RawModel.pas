namespace Tsgen.Loading;

uses
  System.Collections.Generic,
  System.Text;

type
  {
    Structural representation of a CLR type reference. Arrays and generic
    instantiations carry their element/argument types recursively, so
    Stage 3 (Tsgen.Ir.TypeMapper) can resolve things like List<Foo>,
    Dictionary<K,V>, T[], Nullable<T> without string-parsing
    System.Type.FullName's mangled, assembly-qualified generic-argument
    syntax (e.g. "System.Collections.Generic.List`1[[Foo, MyAsm,
    Version=...]]"). Built from System.Type via
    AssemblyLoader.BuildTypeRef, which uses GetElementType() /
    GetGenericArguments() directly -- never the raw FullName -- for the
    array/generic cases.
  }
  RawTypeRef = public class
  public
    FullName: String;  // Simple types: e.g. "System.String". Generic types: the generic type DEFINITION's FullName, e.g. "System.Collections.Generic.List`1". Empty for arrays.
    IsArray: Boolean;
    ElementType: RawTypeRef;                                  // set when IsArray
    TypeArguments: List<RawTypeRef> := new List<RawTypeRef>;  // non-empty when this is a generic instantiation

    // Human-readable form for diagnostics (e.g. "List<Foo>", "Foo[]") -- not used for type-mapping logic itself.
    method DisplayName: String;
    begin
      if IsArray then
        result := ElementType.DisplayName + '[]'
      else if TypeArguments.Count > 0 then begin
        var sb := new StringBuilder;
        sb.Append(FullName);
        sb.Append('<');
        for i: Int32 := 0 to TypeArguments.Count - 1 do begin
          if i > 0 then sb.Append(', ');
          sb.Append(TypeArguments[i].DisplayName);
        end;
        sb.Append('>');
        result := sb.ToString();
      end
      else
        result := FullName;
    end;
  end;

  RawMemberKind = public enum (Field, PropertyMember);

  RawMember = public class
  public
    Name: String;
    Kind: RawMemberKind;
    TypeRef: RawTypeRef;
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
