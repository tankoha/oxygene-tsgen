namespace ExternalDependency.Vendor;

// Stand-in for a real third-party dependency assembly (e.g. InertiaNetCore
// sitting next to TeaTimeTracker.dll, or ASP.NET Core's own
// Microsoft.AspNetCore.Mvc.Controller) -- see M3-dts-validation.md §3.1 and
// oxygene-tsgen's own HANDOFF.md §31 for the bug this fixture guards
// against: AssemblyLoader.Load's resolver used to search only the .NET
// runtime directory + the single target DLL, so a base type living in a
// sibling DLL in the SAME folder as the target assembly could not be
// resolved and crashed the whole load with an unhandled
// FileNotFoundException.

type
  VendorBase = public class
  public
    property VendorId: not nullable String read write := '';
  end;

end.
