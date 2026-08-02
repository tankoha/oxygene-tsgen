namespace Tsgen.Diagnostics;

uses
  System.Collections.Generic;

type
  DiagnosticSeverity = public enum (Warning);

  Diagnostic = public class
  public
    Severity: DiagnosticSeverity;
    Message: String;
  end;

  {
    Collects diagnostics produced while running a pipeline stage, instead
    of each stage writing straight to the console. Keeps AssemblyLoader.Load
    and DtsEmitter.Emit pure data transforms (aRaw/aAssembly in, result +
    diagnostics out) -- only Program.pas (the CLI entry point) actually
    prints anything, and it does so once, after every stage has run, so
    repeated warnings about the same underlying issue (e.g. the same
    unmapped CLR type used by many members) can be deduplicated into one
    line instead of scattering one per occurrence.
  }
  DiagnosticList = public class
  private
    fItems: List<Diagnostic> := new List<Diagnostic>;
  public
    property Items: List<Diagnostic> read fItems;

    method AddWarning(aMessage: String);
    begin
      var d := new Diagnostic;
      d.Severity := DiagnosticSeverity.Warning;
      d.Message := aMessage;
      fItems.Add(d);
    end;
  end;

end.
