namespace Tsgen.Cli;

uses
  System,
  System.Collections.Generic,
  System.IO,
  Tsgen.Loading,
  Tsgen.Nrt,
  Tsgen.Ir,
  Tsgen.Inertia,
  Tsgen.Emit,
  Tsgen.Diagnostics;

type
  Program = class
  public
    class method Main(args: array of String): Int32;
    begin
      if (args.Length = 0) or (args[0] <> 'generate') then begin
        writeLn('Usage: tsgen generate --assembly <path.dll> --source <dir> --out <dir> [--mode assembly|inertia] [--enum-style numeric|union] [--nrt-unknown-policy nullable|non-null|mark-unknown]');
        exit(1);
      end;

      var assemblyPath: String := nil;
      var sourceDir: String := nil;
      var outDir: String := nil;
      var chosenEnumStyle := EnumStyle.Numeric;
      var unknownPolicy := NrtUnknownPolicy.TreatAsNullable;
      var inertiaMode := false;

      var i: Int32 := 1;
      var missingValueFor: String := nil;
      {
        Every branch below does inc(i) then reads args[i] as that flag's
        value -- without the (i < args.Length) guard, a flag with no value
        after it (e.g. "tsgen generate --assembly" with nothing following)
        indexed past the end of args and threw an unhandled
        IndexOutOfRangeException instead of a clean CLI error. Found during
        a self-review, not by any test -- no fixture exercises malformed
        CLI invocations, only malformed/edge-case Oxygene source.
      }
      while (i < args.Length) and (missingValueFor = nil) do begin
        var a := args[i];
        if a = '--assembly' then begin
          inc(i);
          if i < args.Length then assemblyPath := args[i] else missingValueFor := a;
        end
        else if a = '--source' then begin
          inc(i);
          if i < args.Length then sourceDir := args[i] else missingValueFor := a;
        end
        else if a = '--out' then begin
          inc(i);
          if i < args.Length then outDir := args[i] else missingValueFor := a;
        end
        else if a = '--enum-style' then begin
          inc(i);
          if i < args.Length then begin
            if args[i] = 'union' then chosenEnumStyle := EnumStyle.StringUnion
            else chosenEnumStyle := EnumStyle.Numeric;
          end
          else missingValueFor := a;
        end
        else if a = '--nrt-unknown-policy' then begin
          inc(i);
          if i < args.Length then begin
            if args[i] = 'non-null' then unknownPolicy := NrtUnknownPolicy.TreatAsNonNull
            else if args[i] = 'mark-unknown' then unknownPolicy := NrtUnknownPolicy.MarkUnknown
            else unknownPolicy := NrtUnknownPolicy.TreatAsNullable;
          end
          else missingValueFor := a;
        end
        else if a = '--mode' then begin
          inc(i);
          if i < args.Length then inertiaMode := (args[i] = 'inertia') else missingValueFor := a;
        end;
        inc(i);
      end;

      if missingValueFor <> nil then begin
        writeLn('Error: ' + missingValueFor + ' requires a value.');
        exit(1);
      end;

      if String.IsNullOrEmpty(assemblyPath) or String.IsNullOrEmpty(outDir) then begin
        writeLn('Error: --assembly and --out are required.');
        exit(1);
      end;
      if inertiaMode and String.IsNullOrEmpty(sourceDir) then begin
        writeLn('Error: --mode inertia requires --source (entry-point discovery scans source for Inertia.Render call sites; there is nothing to find without it).');
        exit(1);
      end;

      var diagnostics := new DiagnosticList;

      writeLn('Loading assembly: ' + assemblyPath);
      var raw := AssemblyLoader.Load(assemblyPath, diagnostics);
      writeLn('Loaded ' + raw.Types.Count.ToString() + ' type(s).');

      var nullability := new Dictionary<String, NullabilityKind>;
      if not String.IsNullOrEmpty(sourceDir) then begin
        writeLn('Scanning source for NRT info: ' + sourceDir);
        nullability := NullabilityScanner.Scan(sourceDir);
        writeLn('Found nullability info for ' + nullability.Count.ToString() + ' member(s).');
      end
      else
        diagnostics.AddWarning('--source not given; all members will fall back to --nrt-unknown-policy (no explicit NRT info available).');

      var ir: IrAssemblyLite;
      if inertiaMode then begin
        writeLn('Scanning source for Inertia.Render call sites: ' + sourceDir);
        var sharedData := new InertiaSharedData;
        var pages := InertiaScanner.Scan(sourceDir, raw, diagnostics, sharedData);
        writeLn('Found ' + pages.Count.ToString() + ' Inertia.Render call site(s) and ' +
                sharedData.Fields.Count.ToString() + ' shared-data field(s).');
        ir := InertiaIrBuilder.Build(raw, pages, sharedData, nullability);
      end
      else
        ir := IrBuilder.Build(raw, nullability);

      var dts := DtsEmitter.Emit(ir, chosenEnumStyle, unknownPolicy, diagnostics);

      if not Directory.Exists(outDir) then
        Directory.CreateDirectory(outDir);
      var outPath := Path.Combine(outDir, 'index.d.ts');
      File.WriteAllText(outPath, dts);

      writeLn('Wrote ' + outPath);

      {
        All warnings are printed together, at the end, to stderr -- not
        interleaved with the stdout progress lines above. Keeps
        AssemblyLoader.Load/DtsEmitter.Emit pure (they only return data +
        diagnostics; Program is the one place that actually prints) and
        means a warning about the same underlying issue across many
        members appears once, not scattered mid-run. See Tsgen.Diagnostics.
      }
      for each d in diagnostics.Items do
        Console.Error.WriteLine('Warning: ' + d.Message);

      exit(0);
    end;
  end;

end.
