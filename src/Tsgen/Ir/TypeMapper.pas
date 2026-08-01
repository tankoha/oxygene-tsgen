namespace Tsgen.Ir;

type
  {
    Stand-in for the pluggable Stage 3 type-mapping chain (docs/DESIGN.md
    §2), which is deferred past the MVP per docs/DESIGN.md §10.2 item 8.
  }
  TypeMapper = public static class
  public
    class method MapClrTypeName(aClrTypeName: String): String;
    begin
      if aClrTypeName = 'System.String' then
        result := 'string'
      else if aClrTypeName = 'System.Boolean' then
        result := 'boolean'
      else if (aClrTypeName = 'System.Int16') or (aClrTypeName = 'System.Int32') or (aClrTypeName = 'System.Int64')
           or (aClrTypeName = 'System.UInt16') or (aClrTypeName = 'System.UInt32') or (aClrTypeName = 'System.UInt64')
           or (aClrTypeName = 'System.Byte') or (aClrTypeName = 'System.SByte')
           or (aClrTypeName = 'System.Single') or (aClrTypeName = 'System.Double') or (aClrTypeName = 'System.Decimal') then
        result := 'number'
      else if (aClrTypeName = 'System.DateTime') or (aClrTypeName = 'System.DateTimeOffset') then
        result := 'string'
      else if aClrTypeName = 'System.Guid' then
        result := 'string'
      else
        result := 'unknown';
    end;
  end;

end.
