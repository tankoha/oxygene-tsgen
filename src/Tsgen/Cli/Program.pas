namespace Tsgen.Cli;

uses
  System,
  System.Collections.Generic,
  System.IO,
  Tsgen.Loading,
  Tsgen.Nrt,
  Tsgen.Ir,
  Tsgen.Emit,
  Tsgen.Diagnostics;

type
  Program = class
  public
    class method Main(args: array of String): Int32;
    begin
      if (args.Length = 0) or (args[0] <> 'generate') then begin
        writeLn('Usage: tsgen generate --assembly <path.dll> --source <dir> --out <dir> [--enum-style numeric|union] [--nrt-unknown-policy nullable|non-null|mark-unknown]');
        exit(1);
      end;

      var assemblyPath: String := nil;
      var sourceDir: String := nil;
      var outDir: String := nil;
      var chosenEnumStyle := EnumStyle.Numeric;
      var unknownPolicy := NrtUnknownPolicy.TreatAsNullable;

      var i: Int32 := 1;
      while i < args.Length do begin
        var a := args[i];
        if a = '--assembly' then begin
          inc(i);
          assemblyPath := args[i];
        end
        else if a = '--source' then begin
          inc(i);
          sourceDir := args[i];
        end
        else if a = '--out' then begin
          inc(i);
          outDir := args[i];
        end
        else if a = '--enum-style' then begin
          inc(i);
          if args[i] = 'union' then chosenEnumStyle := EnumStyle.StringUnion
          else chosenEnumStyle := EnumStyle.Numeric;
        end
        else if a = '--nrt-unknown-policy' then begin
          inc(i);
          if args[i] = 'non-null' then unknownPolicy := NrtUnknownPolicy.TreatAsNonNull
          else if args[i] = 'mark-unknown' then unknownPolicy := NrtUnknownPolicy.MarkUnknown
          else unknownPolicy := NrtUnknownPolicy.TreatAsNullable;
        end;
        inc(i);
      end;

      if String.IsNullOrEmpty(assemblyPath) or String.IsNullOrEmpty(outDir) then begin
        writeLn('Error: --assembly and --out are required.');
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

      var ir := IrBuilder.Build(raw, nullability);
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
