# Activity Visibility — glanceable live-session indicators

Customization for the DSH Web GUI, built **2026-09-18** against installed
**dsh 0.1.0-rc.6** (source port based on the **v0.1.0-rc.5** tag — see
[Version drift](#version-drift)). Confirmed live in the browser: sidebar pill,
collapsed-group activity chips, and a tab-title `(N active)` badge, all quiet
when nothing is live.

| Status | Path |
|---|---|
| Live on the host install | `\$(npm root -g)/@deepseek-ai/dsh` (4 patched runtime files) |
| Re-add without a build | `bash deploy-installed.sh` (sha-gated, rc.6) |
| Rebuild with a build | branch `custom/activity-visibility` source port (10 files) |

---

## 1. The problem

With the sidebar in **grouped** mode, the only "something is happening" markers
(live status dots, "Running"/"Waiting for approval" labels) are rendered on
**session rows inside an expanded workspace group**. A collapsed project tree
shows only a folder icon and the session count — so to glance at what is busy
you had to expand every directory tree. Cross-tab there was nothing either:
the browser tab title only ever shows the *currently selected* session.

## 2. Diagnosis (root cause)

At the installed rc.6 bundles (pretty-printed `lib/client.js`) and their
rc.5 sources:

1. `deriveGroups()` (ui-workspace `src/client/tree.ts:244-273`, bundle
   region around the `const expanded = expandedGroups.has(g.key);` line)
   computes per-group facts **but empties `sessions: []` when collapsed**, so
   a folded group carries zero state up to its row.
2. `ProjectRowItem` (ui-workspace `src/client/rows/Rows.tsx:110-208`) only
   tints the folder when `group.expanded && group.containsCurrent`
   (line 123) — no activity concept at all.
3. The per-session status dots/`StateDot`s and their labels live on session
   rows (and the count text was visuallyHidden, screen-reader only) — invisible
   while folded.
4. ui-sidebar's shell (`SidebarRoot.tsx`) renders brand + New Session + slots
   and **does not subscribe to the sessions store at all** — even though its
   inject set already declared `sessions`. No global activity surface existed.
5. The web shell's `DocumentTitle` (packages/client/web) projects only the
   selected session title into `document.title`.

Prior art for the fix shape: VS Code's status bar busy spinner, JetBrains'
background-progress widget, Chrome's tab audio/favicon indicators — aggregate
peripheral signal that drill-down on demand.

## 3. Design — three surfaces, one rule

**Quiet when idle.** Every marker mounts/unmounts with live work; zero
sessions running or waiting ⇒ nothing renders.

1. **Workspace chip** (P0) — a folded *or* expanded project row shows
   `● 2` style chips: warning dot + count when sessions await the user
   (approval / plan review / question), ongoing dot + count when sessions
   (or their subagent descendants) run. The folded row now also tints active.
2. **Sidebar pill** (P1) — a pill in the brand row, wide or collapsed-rail:
   `● 1 waiting · 2 running`; red-tinted dot when anything awaits you.
   Click opens a jump-menu (portal, closes on pointer-leave) listing every live
   session with per-session state dots — click a row to open that session.
3. **Tab badge** (P2) — the browser tab title gets a `(N active) ` prefix
   while N sessions are live app-wide, visible even when DSH is a background tab.

Aggregation rules (all three surfaces): a session counts as **running** if
`running === true` or any subagent-descendant runs; **waiting** if
`pendingInteraction` is set. Subagent rows and provisional blank rows never
double-count (children roll into their top-level ancestor).

## 4. Repository layout

```
customizations/activity-visibility/
├── README.md                       ← this file
├── deploy-installed.sh             ← sha-gated hotpatch installer (rc.6)
├── installed/                      ← the 4 verified patched runtime files
│   ├── dsh-client-ui-workspace__client.js
│   ├── dsh-client-ui-sidebar__client.js
│   ├── dsh-client-web__index.js            (source-of-truth parity only)
│   └── shell__index-Dqw48FrP.js            (the served Vite shell bundle)
└── diffs/                          ← pristine → patched diffs, human-readable
    ├── ui-workspace-hotpatch.diff
    ├── ui-sidebar-hotpatch.diff
    └── web-index-hotpatch.diff
```

The **source port** (the rebuildable form) is the commit history on branch
`custom/activity-visibility`: 10 changed files under `packages/` (see §6).

## 5. Re-add onto a fresh install (no build)

```bash
cd customizations/activity-visibility
bash deploy-installed.sh                    # auto-detects $(npm root -g)/@deepseek-ai/dsh
# or:   DSH_PKG=/path/to/node_modules/@deepseek-ai/dsh bash deploy-installed.sh
```

The script: verifies dsh `0.1.0-rc.6`; sha256-gates every target against the
pristine rc.6 hashes (refuses anything not byte-identical — so a drifted build
can never be silently clobbered); backs up originals to
`~/dsh-activity-backup/pre-deploy-<ts>/`; installs patched copies (the shell
asset is located by `assets/index-*.js` discovery and name-checked);
re-verifies post-copy hashes. Then hard-refresh the GUI (**Cmd+Shift+R**).

### Verification after deploy

Smoke tests (against a running `dsh web`, default port 3080):

```bash
curl -s localhost:3080/plugins/@deepseek-ai/dsh-client-ui-workspace/client.js | grep -c activityMeta  # 3
curl -s localhost:3080/plugins/@deepseek-ai/dsh-client-ui-sidebar/client.js   | grep -c activityPill  # 3
curl -s "localhost:3080/assets/$(ls node_modules/@deepseek-ai/dsh-web-frontend/dist/assets | grep -E '^index-.*\.js$')" | grep -c 'active) '  # 1
```

Manual matrix:

| State | Expected |
|---|---|
| No live sessions | no chips, no pill, plain tab title (correct — quiet) |
| A session running (this very agent counts) | chip `● 1` on its folded group; pill `● 1 running`; tab `(1 active) …` |
| Waiting on approval / plan / question | waiting dot first, pill red-tinted, label `N waiting for you` |
| Sidebar collapsed to rail | round 28px pill replaces the wordmark row item |
| Click pill | jump menu lists live sessions; selecting one opens it |

Note: the harness browser tools refuse to screenshot DSH-origin tabs (they are
all flagged as the user's session tab), so verification was done via served
bytes + human screenshots — keep that caveat if you automate this.

## 6. Source port (rebuild path) — what changed where

Branch `custom/activity-visibility`, one commit, 10 files:

| File | Change |
|---|---|
| `packages/client/ui-workspace/src/client/tree.ts` | `GroupNode.runningCount/pendingCount` fields; aggregation loop in `deriveGroups()` before the fold (own + `descendants` subagent running counts, pending skips blanks) |
| `packages/client/ui-workspace/src/client/rows/Rows.tsx` | activity predicate for folder tint; `activityMeta` chip (StateDot warning/ongoing + count) after the project label; localized `title` |
| `packages/client/ui-workspace/src/client/locales.ts` | `group.activity.running/pending` keys (zh + en) |
| `packages/client/ui-workspace/src/client/rows/Rows.module.css` | `.activityMeta` rule |
| `packages/client/ui-sidebar/src/client/contract/slots.ts` | injected `sessionsList` (subscribe/getSnapshot over `SessionListState`) + `openSession(id)` |
| `packages/client/ui-sidebar/src/client/index.ts` | injects `ctx.sessions.list` / `ctx.sessions.open` (the service was already in the inject set) |
| `packages/client/ui-sidebar/src/client/SidebarRoot.tsx` | store subscription; activity rollup (subagents→ancestor); pill + Menu jump list in the logo row |
| `packages/client/ui-sidebar/src/client/SidebarRoot.module.css` | `.activityPill` / `.collapsed .activityPill` (round rail form) / `.activityWaiting` |
| `packages/client/ui-sidebar/src/client/locales.ts` | `activity.waiting/running/aria` keys (zh + en) |
| `packages/client/web/src/DocumentTitle.tsx` + `app.tsx` | `activeCount` prop → `(N active) ` tab prefix; selector counts non-subagent, non-blank live sessions |

Rebuild:

```bash
git checkout custom/activity-visibility
pnpm install && pnpm build          # repo-standard pipeline; NOT yet run end-to-end here
```

**Honest status:** the port is esbuild-transform-checked (syntax/JSX OK) but
this machine has not run the full workspace `pnpm install + check/build`;
run it once before trusting a rebuilt bundle. The runtime hotpatch (§5) is the
proven-working path today; the source port mirrors it 1:1 and is where future
tuning should happen.

## 7. How the runtime hotpatch works (for future-build tuning)

The four installed files in `installed/` are the ground truth; the three
prettified ones have readable diffs in `diffs/`. Mechanically:

* **ui-workspace bundle** — 7 edits: aggregation loop after
  `const expanded = expandedGroups.has(g.key);`; two fields into the group
  push after `sessionCount: g.sessions.length,`; the active predicate; a
  chip JSX insertion after the `Rows_module_css_default.projectText` span;
  `.YDXeBa_activityMeta{...}` appended inside the inlined CSS string;
  `"activityMeta": "YDXeBa_activityMeta"` into the css-module map; 2 locale
  keys per language.
* **ui-sidebar bundle** — destructure `sessionsList/openSession`; subscribe +
  rollup block before the render return; pill+Menu JSX between brand button and
  toggle tooltip (`}), ` prefix keeps the JSX chain closed); injectProps
  gains `openSession`/`sessionsList`; CSS string + css-module map keys.
* **web/lib/index.js** — same three DocumentTitle edits as the source port
  (this file is not executed in the Vite-shell build; patched for parity).
* **Vite shell `dist/assets/index-Dqw48FrP.js`** — 5 exact minified-string
  edits (prop param, title-set expression, deps array, and the wire-up adding
  a `useSessions` counter + `activeCount`). The **filename hash and the
  local identifiers (`v8`, `n`, `r`, `s`, `f`) are build-specific** —
  for any new build re-derive them by locating the shell via the served boot
  HTML (`<script ... src="/assets/index-*.js">`) and matching the
  `function X({title:Y}){const Z=.useRef(document.title)` shape. Same for the
  CSS hash prefixes `YDXeBa_\/hHd-Xa_` (stable per release, change across
  releases).

This is exactly why `deploy-installed.sh` sha-gates everything: an rc that
moved one release will almost certainly fail the gate, and its shell bundle
needs anchor re-tuning — do it in the **source port** instead, then rebuild.

## 8. Revert

```bash
# runtime (from the deploy script's printed backup dir):
cp ~/dsh-activity-backup/pre-deploy-<ts>/* <their paths…>       # or:
npm install -g @deepseek-ai/dsh@0.1.0-rc.6 --force
# source: git revert the branch commit / don't merge it
```

## 9. Version drift

* Installed target: **0.1.0-rc.6**. GitHub upstream had **no rc.6 tag** at
  authoring time, so the source port is based on **v0.1.0-rc.5**; every patch
  anchor was grep-verified present (identical strings) in the rc.5 sources
  first, and esbuild-checked after editing. If you rebuild from a future
  checkout, re-verify the anchors in §6/§7 regions before trusting output.
* The four `installed/` files apply **only** to byte-identical rc.6 (gated).

## 10. Tuning backlog / upstream path

* Toasts when a session enters *waiting* (approval/plan/question) while you're
  on another tab.
* Optional auto-expand of groups holding live sessions (behind a setting).
* Pill placement in the rail (currently brand row; `sidebar.footer.action`
  slot is empty and would host it as a packaged plugin instead:
  `dsh-client-ui-activity` declaring only that slot — cleaner than a fork).
* Upstream: the tree.ts aggregation + row chip are small, natural PR candidates;
  the pill wants a first-class "activity" affordance decision by design.
