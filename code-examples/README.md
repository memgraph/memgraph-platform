# Code Examples

Each example is a `.md` walkthrough plus a runnable script — `.sh` for
macOS/Linux and `.ps1` for Windows PowerShell.

| Example | Linux | macOS | Windows |
| --- | :---: | :---: | :---: |
| [Agentic AI](agentic-ai.md) | ✅ | ✅ | ✅ |
| [Agentic GraphRAG](agentic-graphrag.md) | ✅ | ✅ | ✅ |
| [AI Memory](ai-memory.md) | ✅ | ✅ | ✅ |

## Testing

`test.ps1` smoke-tests every example on Windows. Each demo binds fixed ports
(`ai-memory` and `agentic-graphrag` both publish Bolt on 7687), so they are run
one at a time and torn down before and after. An example passes only when it
exits 0 **and** prints its success banner:

```powershell
.\test.ps1                     # all examples
.\test.ps1 -Only ai-memory     # one (repeatable: -Only a,b)
.\test.ps1 -KeepUp             # leave the last example's containers running
.\test.ps1 -CleanOnly          # tear every example down
```

Logs land in `.test-logs\`. Prerequisites an example needs but the machine
lacks (Docker not running, no `git`, no Python 3.10–3.13) are reported as
`SKIP` rather than `FAIL`. `OPENAI_API_KEY` is hidden from the child processes
so `agentic-graphrag`'s optional Streamlit app does not block the run.
