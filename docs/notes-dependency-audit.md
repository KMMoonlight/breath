# Notes editor dependency and asset audit

Audit date: 2026-07-29

The distributable editor resources include a generated
`THIRD_PARTY_NOTICES.txt`. `npm run notices` derives it from the locked
dependency graph, includes discovered license text for every package, and the
release test rejects any package/version missing from the notice file.

The Notes editor is built from `Web/NotesEditor/package-lock.json`. Every
runtime and build dependency is pinned to an exact version. The generated
JavaScript retains esbuild legal comments, and the application loads the
editor, CSS, fonts, KaTeX, Mermaid, syntax definitions, and themes only from
the application resource bundle.

## Direct dependencies

| Package | Version | License |
| --- | ---: | --- |
| `@tiptap/core` and the selected Tiptap extensions | 3.29.2 | MIT |
| `diff` | 8.0.4 | BSD-3-Clause |
| `dompurify` | 3.4.12 | MPL-2.0 or Apache-2.0 |
| `highlight.js` | 11.11.1 | BSD-3-Clause |
| `katex` (including its bundled fonts) | 0.18.1 | MIT |
| `lowlight` | 3.3.0 | MIT |
| `mermaid` | 11.16.0 | MIT |
| `esbuild` (build-only) | 0.25.12 | MIT |

The lockfile's transitive packages declare MIT, BSD-3-Clause, ISC,
Apache-2.0, or Unlicense terms. `khroma@2.1.0` omits its license metadata from
the npm archive; the source tag contains its
[MIT license](https://raw.githubusercontent.com/fabiospampinato/khroma/v2.1.0/license).

## Theme and visual assets

GitHub, Gothic, Newsprint, Night, Pixyll, and Whitey are Breath-authored CSS
implementations that reproduce the corresponding built-in theme categories.
No Typora theme file, logo, image, font, or proprietary application asset is
copied into Breath. System fonts are referenced by name and are not
redistributed.

## Verification

- `npm audit --audit-level=low`: 0 vulnerabilities.
- The HTML content security policy uses `default-src 'none'`, permits scripts
  only from `self`, and disables direct network connections.
- Remote Markdown images are rewritten to the native
  `breath-note-resource` boundary; local paths are canonicalized and checked
  against the selected Note Library.
- No CDN, runtime package download, theme import, custom CSS, or automatic
  theme update path exists.
