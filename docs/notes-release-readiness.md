# Notes release readiness

Last updated: 2026-07-29

## Automated gates

The following gates are part of the repository and must pass before release:

- Notes domain tests cover library selection, hidden files and symlinks,
  opening, explicit save, BOM/CRLF preservation, dirty recovery, missing
  files, external conflicts, atomic moves and relative-link rewrites,
  creation/import/delete/undo, attachments, preferences, search, tab title
  disambiguation, index degradation, failed-switch rollback, CommonMark link
  forms, descendant-move rejection, and Agent persistence privacy.
- Application tests cover debounced-edit flushing, Note Agent terminal
  identity and lifetime (including exit-during-launch), conflict queues,
  concurrent typing during save, two-phase termination, Note Agent hook event
  isolation, and a real WebKit contract for source fidelity, active HTML
  removal, code-literal preservation, KaTeX, and Mermaid.
- Persistence tests cover upgrade from a pre-Notes database, private database
  permissions, isolation of a corrupt Notes state, and per-draft recovery
  salvage.
- JavaScript tests cover unchanged-byte fidelity, CRLF/trailing-space
  preservation after a local edit, retention of unknown Markdown syntax, and
  sequential distant edits without normalization of untouched source.
- The generated `THIRD_PARTY_NOTICES.txt` is shipped in the editor resource
  bundle. A release test requires an entry for every package and version in
  `package-lock.json`.
- `npm audit --audit-level=low`, `swift build`, the full Swift test suite, and
  `swift build -c release` are release blockers.

## Performance budgets

`NotesPerformanceTests` uses a real 500-document directory and SQLite FTS
index. On the reference Apple Silicon development machine, the 2026-07-29
debug run measured:

| Operation | Measured | Gate |
| --- | ---: | ---: |
| Initial scan and index | 83 ms | 5 s |
| Open document | 2 ms | 500 ms |
| Atomic save and index refresh | 74 ms | 5 s |
| Full-library phrase search | 6 ms | 1 s |

Documents above the reviewed byte or structural thresholds open completely in
source mode. Users can explicitly try the WYSIWYG canvas without changing the
source buffer. The editor uses one shared `WKWebView` for all Note Tabs.

## Manual native interaction checklist

- Verify Chinese and English copy, keyboard focus, VoiceOver names, and
  non-color status indicators for the Activity Bar entry, library chooser,
  file tree, outline, tabs, conflicts, search, settings, and Agent drawer.
- Verify the 180–420 pt sidebar and 340–min(720 pt, 45%) Agent drawer at the
  minimum supported window size and after restart.
- Verify IME composition in WYSIWYG and source modes, tab drag/reorder,
  inline rename, Finder drop conflict choices, Trash undo, and the single
  dirty/bulk-close confirmation.
- Verify application quit with dirty tabs plus a running Note Agent for Save
  All, Discard All, and Cancel.
- Verify editing, save, search, six themes, KaTeX, and Mermaid with networking
  disabled.

## Accepted limitations

- Notes are local-only. There is no account, sync, collaboration, version
  history, backlinks, `[[wikilinks]]`, Git UI, search replacement, theme
  import, custom CSS, or automatic theme update.
- File monitoring converges from a one-second filesystem snapshot poll rather
  than exposing event-by-event history. The FTS index publishes ready,
  rebuilding, or degraded state and retries after a failed rebuild.
- Remote images can fail quietly when HTTPS, redirect, MIME, size, timeout, or
  proxy validation rejects them; this never blocks editing or saving.
- Large-document thresholds are conservative and can be tuned from measured
  telemetry that contains timings and sizes only, never note content.
- The complete Markdown source is authoritative. Syntax that Tiptap cannot
  model as an editable rich-text node remains byte-preserved and is editable
  in source mode; switching modes without editing remains byte-exact.
