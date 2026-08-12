namespace ExternalDependency;

uses
  ExternalDependency.Vendor;

// Regression fixture for AssemblyLoader.Load's dependency-resolution fix
// (M3-dts-validation.md §3.1, HANDOFF.md §31): Widget inherits from
// VendorBase, a type defined in a SEPARATE assembly (VendorLib.dll) built
// as a sibling DLL in this fixture's own Bin\Release folder -- never
// discoverable via .NET's own runtime directory. Before the fix,
// AssemblyLoader's PathAssemblyResolver only searched the .NET runtime
// directory plus the single target DLL path, so resolving Widget's base
// type crashed the whole process with an unhandled FileNotFoundException
// (exactly what happened loading TeaTimeTracker.dll against
// InertiaNetCore.dll, see the report). This fixture proves the "target
// assembly's own folder" resolver-path addition specifically; the other
// half of the fix (shared-framework resolution via runtimeconfig.json) has
// no equivalent fixture here since library-only test assemblies never get
// a runtimeconfig.json -- verified by hand instead against
// TeaTimeTracker.dll, see HANDOFF.md §31.

type
  Widget = public class(VendorBase)
  public
    property Name: not nullable String read write := '';
  end;

end.
