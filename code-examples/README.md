# Code Examples

Each example is a `.md` walkthrough plus a runnable script — `.sh` for
macOS/Linux and `.ps1` for Windows PowerShell.

| Example | Linux | macOS | Windows |
| --- | :---: | :---: | :---: |
| [Agentic AI](agentic-ai.md) | ✅ | ✅ | ✅ |
| [Agentic GraphRAG](agentic-graphrag.md) | ✅ | ✅ | ✅ |
| [AI Memory](ai-memory.md) | ✅ | ✅ | ✅ |

## Testing

One harness per platform, each covering all three examples. Both run the
examples **one at a time** and tear them down before and after: every demo
binds fixed host ports (`ai-memory` and `agentic-graphrag` both publish Bolt on
7687, `agentic-ai` publishes 7688), so parallel runs would collide. Both also
hide `OPENAI_API_KEY` from the examples, so `agentic-graphrag` stops after its
three atomic pipelines instead of blocking on the optional Streamlit app.

### macOS / Linux — `test.sh`

Asserts on what each example actually printed — the ranked plan, the retrieved
neighbourhood, the recalled memory — because an exit code of 0 alone would not
catch a pipeline that returned no rows. It also checks that the endpoints an
example advertises really answer, and that `clean` removes every container and
work directory afterwards.

```bash
./test.sh                       # all three, one at a time
./test.sh ai-memory             # just one (or several, space separated)
./test.sh --keep agentic-ai     # leave the containers up for inspection
./test.sh clean                 # tear down every example, run nothing
```

Needs what the examples need — Docker, git, and Python 3.10-3.13 — plus `curl`,
to check that the MCP endpoint really answers. Nothing else: GNU `timeout` (or
Homebrew's `gtimeout`) is used when present, otherwise a built-in watchdog
enforces the same per-example ceiling. Before running anything it checks that
the host ports the selected examples publish (7687, 7688, 7444, 8000) are free
and, if not, names the container or process holding them — a dev Memgraph of
your own on 7687 would otherwise fail every example with the same "port is
already allocated" error. `--keep` takes a single example, for the port reason
above. Per-example logs land in `test-logs-unix/`.

### Windows — `test.ps1`

Smoke-tests every example: one passes when it exits 0 **and** prints its
success banner.

```powershell
.\test.ps1                     # all examples
.\test.ps1 -Only ai-memory     # one (repeatable: -Only a,b)
.\test.ps1 -KeepUp             # leave the last example's containers running
.\test.ps1 -CleanOnly          # tear every example down
```

Prerequisites an example needs but the machine lacks (Docker not running, no
`git`, no Python 3.10–3.13) are reported as `SKIP` rather than `FAIL`.
Per-example logs land in `test-logs-windows\`; on failure the tail is printed
inline.
