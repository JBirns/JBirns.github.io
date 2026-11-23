# My forest: a personal website built with Forester

This folder is a ready-to-go personal website made with [Forester](https://www.forester-notes.org)
(Jon Sterling and Kento Okura's tool for mathematical hypertext), set up so that:

- you write pages as small `.tree` files with LaTeX maths, on your own computer;
- you see a live preview in your browser while you type;
- `make publish` pushes your changes to GitHub, which rebuilds and hosts the site for free on GitHub Pages.

```
 your computer                                   GitHub (free)
 ─────────────                                   ─────────────
 trees/*.tree ── editor ──► live preview         repository ──► Actions builds ──► https://<you>.github.io
        │                   localhost:8080            ▲          with Forester
        └──────────── make publish (git push) ────────┘
```

It targets **Forester 6.0** (released November 2026), which writes plain HTML and bundles its own theme,
so there is no theme submodule to manage.

---

## 1. Install Forester (once per computer)

Forester is written in OCaml and installed with `opam`, OCaml's package manager.
Forester 6 needs OCaml 5.4 or newer; this guide uses 5.4.1, the same version the GitHub build uses.

**macOS** (with [Homebrew](https://brew.sh)):

```sh
brew install opam
```

**Linux** (Pop!_OS, Ubuntu, Debian):

```sh
sudo apt update
sudo apt install opam build-essential bubblewrap pkg-config unzip git curl
```

(Fedora: `sudo dnf install opam`; any distro: the official installer
`bash -c "sh <(curl -fsSL https://opam.ocaml.org/install.sh)"`.)

**Windows**: install [WSL](https://learn.microsoft.com/windows/wsl/install) (Ubuntu) and follow the Linux
steps inside it. Keep this folder inside WSL (e.g. `~/my-forest`).

Then, on every system:

```sh
opam init --yes                 # answer yes if it offers to update your shell config
opam switch create forester 5.4.1   # OCaml 5.4.1, same as the GitHub build (a few minutes)
eval $(opam env)                    # opam makes the new switch the default
opam install forester           # takes several minutes
forester --version              # should print 6.0 or later
```

You also need `git` and `python3` (both preinstalled on macOS and most Linux systems).

## 2. Make the site yours (once)

Unzip the download and run the script from inside the unzipped folder (it is already there; you
don't create it):

```sh
unzip my-forest.zip
cd my-forest
./scripts/personalize.sh "Your Name" your-github-username
```

This fills in your name and site address and renames `trees/yourname.tree` to your own page.
By default the site lives at `https://your-github-username.github.io/`. If you would rather use a
different repository name, add it as a third argument (`... your-github-username my-website`); the site
will then be at `https://your-github-username.github.io/my-website/`.

Try it locally:

```sh
make preview        # then open the address it prints, e.g. http://localhost:1313/
```

## 3. Put it online (once)

1. On GitHub, create a **new, empty, public** repository named `your-github-username.github.io`
   (or the name you passed to `personalize.sh`). Don't add a README or licence.
2. In that repository go to **Settings → Pages → Build and deployment → Source** and pick **GitHub Actions**.
3. Push this folder:

   ```sh
   git init -b main
   git add -A
   git commit -m "First version of my site"
   git remote add origin https://github.com/your-github-username/your-github-username.github.io.git
   git push -u origin main
   ```

   (With the GitHub CLI you can do steps 1 and 3 in one go:
   `gh repo create your-github-username.github.io --public --source=. --push`. Step 2 is still needed.)

4. Open the **Actions** tab. The first run compiles Forester and takes roughly 10–15 minutes; after that
   it is cached and each update goes live in about a minute. When it turns green, your site is up.

GitHub Pages is free for public repositories. Your `.tree` sources are public too, which is the norm for
Forester sites (readers can see how a page was written).

## 4. An editor with LaTeX support and live preview

Forester has a built-in *language server*. Editors that speak this protocol get error messages,
completion of page addresses, and, new in Forester 6, a **live preview at http://localhost:8080 that
re-renders as you type**, maths included.

### Recommended: Helix

[Helix](https://helix-editor.com) is a fast terminal editor with language-server support built in, and this
folder already contains its settings (`.helix/languages.toml`), so there is nothing to configure.

```sh
brew install helix               # macOS; on Linux use your package manager (the command is `hx`)
cd my-forest
hx trees/index.tree              # then open http://localhost:8080 in your browser
```

The basics: press `i` to type, `Esc` to stop typing, `:w` + Enter to save, `:q` to quit, `Space f` to
open another file. Run `hx --tutor` for a 20-minute tour.
Optional colours for `.tree` files: `./scripts/helix-highlighting.sh`.

### Neovim (0.11 or newer)

Add to your `init.lua`:

```lua
vim.filetype.add({ extension = { tree = "forester" } })
vim.lsp.config("forester", {
  cmd = { "forester", "lsp" },
  filetypes = { "forester" },
  root_markers = { "forest.toml" },
})
vim.lsp.enable("forester")
```

Open a `.tree` file inside this folder and visit http://localhost:8080.

### VS Code or any other editor

An official VS Code extension is being developed but is not out yet. Meanwhile, edit with any editor and run
`make preview` in a terminal: it rebuilds the site every time you save, and you refresh the browser to see it.
(Emacs users can look at the community package `forester.el` from the Topos Institute.)

## 5. Everyday use

```sh
make new TITLE="Compactness"                    # creates trees/xx-0001.tree with a template
make new TITLE="Tychonoff" TAXON=Theorem        # same, labelled as a Theorem
# ...write, watching the preview...
make publish MSG="Add notes on compactness"     # commit + push; the live site updates in ~1 minute
```

`make new` prints the `\transclude{...}` line to paste into `trees/notes.tree` so the new note appears on
your Notes page.

## Writing: the short version

Open `trees/note-0001.tree` (a cheat sheet) and `trees/note-0002.tree` (definition/theorem/proof) next
to their rendered pages. The essentials:

| You want | Write |
|---|---|
| Paragraph | `\p{...}` |
| Inline maths | `#{e^{i\pi} + 1 = 0}` |
| Display maths | `##{ \int_0^\infty e^{-x^2}\,dx = \frac{\sqrt\pi}{2} }` |
| Emphasis / bold / code | `\em{...}` `\strong{...}` `\code{...}` |
| Link to a page / to the web | `[text](note-0002)` `[text](https://...)` |
| Lists | `\ul{ \li{...} \li{...} }` (or `\ol` for numbered) |
| Include a whole page inside another | `\transclude{note-0002}` |
| Theorem with proof | `\subtree{ \taxon{Theorem} \title{...} \p{...} \proof{ \p{...} } }` |
| Your own LaTeX macros | add `\def\R{\mathbb{R}}` to `trees/macros.tree`, and `\import{macros}` at the top of a tree |

Maths in `#{...}` and `##{...}` is rendered in the browser and needs nothing extra installed.
Diagrams that need real LaTeX (TikZ, tikz-cd, written with `\tex{preamble}{body}`) are compiled to images
at build time: install LaTeX locally ([MacTeX](https://tug.org/mactex/) on macOS, `texlive` on Linux) to
preview them. The GitHub build installs LaTeX automatically whenever a tree uses `\tex`.

Images and PDFs go in `assets/`. For more (images, queries, bibliographies), see the
[Forester documentation](https://www.forester-notes.org) and Jon Sterling's own
[forest](https://www.jonmsterling.com) for examples.

## Troubleshooting

- **The site shows a 404:** check that Settings → Pages → Source is *GitHub Actions*, then re-run the
  workflow from the Actions tab (*Deploy site → Run workflow*).
- **The build failed:** open the failed run in the Actions tab; Forester's message names the file and
  line. Running `forester build` locally shows the same error.
- **Links or styles are broken online but fine locally:** the `url` in `forest.toml` must match the real
  address of the site, including the trailing `/`.
- **A custom domain:** Settings → Pages → Custom domain, then change `url` in `forest.toml` to match.
- **Upgrading Forester later:** `opam update && opam upgrade forester` locally, and change
  `FORESTER_VERSION` in `.github/workflows/deploy.yml`.

## What's in this folder

```
forest.toml                     site settings (address, folders, home page)
trees/                          your pages: index, your profile, notes, macros
assets/                         images, PDFs and other files copied as-is
scripts/                        personalize, new note, local preview, Helix colours
Makefile                        the `make ...` shortcuts above
.helix/languages.toml           Helix editor settings (language server + preview)
.github/workflows/deploy.yml    builds and publishes the site on every push to main
```
