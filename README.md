Plinth Standalone Compiler
==========================

About this fork
===============

This is a fork of GHC that embeds the [Plinth][plinth] compiler, used to write
smart contracts for the [Cardano][cardano] blockchain. Plinth (formerly known
as Plutus Tx) is a subset of Haskell compiled to Plutus Core via a GHC Core
plugin shipped here as a built-in static plugin.

See the Plinth documentation:

 - [Plinth user guide][plinth]
 - [Plutus / Plinth GitHub repository][plutus-repo]
 - [Plinth project template][plinth-template]

Installing via ghcup
====================

The Plinth compiler `uplc-ghc` is distributed as a custom [ghcup][ghcup] tool
named `plinth`. It installs *alongside* your normal GHC (it never replaces the
`ghc` on your `PATH`). This needs **ghcup >= 0.2.1.0** (which added support for
third-party tools); upgrade with `ghcup upgrade` if needed.

Add the release channel once, then install and select a version:

    $ ghcup config add-release-channel https://input-output-hk.github.io/ghc-plinth/ghcup-plinth.yaml
    $ ghcup install plinth latest
    $ ghcup set plinth latest          # puts uplc-ghc on PATH

This provides `uplc-ghc`, both unversioned and version-suffixed
(`uplc-ghc-<version>`). The bindist's other tools (`ghc-pkg`, `haddock`, ...)
stay inside the installation directory rather than being linked onto your `PATH`,
so they cannot shadow the ones from your normal GHC. Point `cabal` at the
compiler to build a Plinth project:

    $ cabal build -w uplc-ghc

`ghcup list -t plinth` shows the available versions. Prebuilt bindists are
published as GitHub Releases for x86_64/aarch64 Linux (glibc and musl), macOS
(Apple Silicon), and Windows; ghcup picks the right one for your platform.

  [ghcup]: https://www.haskell.org/ghcup/ "ghcup"

The text below is the upstream GHC README.

This is the source tree for [GHC][1], a compiler and interactive
environment for the Haskell functional programming language.

For more information, visit [GHC's web site][1].

Information for developers of GHC can be found on the [GHC issue tracker][2], and you can also view [proposals for new GHC features][13].


Building from source
====================

Clone the repository together with its submodules (the `plutus` submodule
provides `plutus-tx`, `plutus-tx-plugin`, and `plutus-core`):

    $ git clone --recurse-submodules git@github.com:input-output-hk/ghc-plinth.git

If you already cloned without `--recurse-submodules`, fetch them with:

    $ git submodule update --init --recursive

Then build with the `plinth-build.sh` script at the root of the repository:

    $ ./plinth-build.sh

The script bootstraps GHC and then builds the Plinth-enabled compiler,
`uplc-ghc`. It expects a boot `ghc-9.6.7` and `cabal >= 3.14.2.0` on `PATH`
(`happy` and `alex` are built locally if missing). Useful environment knobs:

 - `REBUILD=1` forces a full rebuild.
 - `RELEASE=1` builds a release flavour including documentation.

A binary distribution archive (`ghc-<version>-<platform>.tar.xz`) is produced
under `_build/bindist/`.


How to use it?
==============

The build produces `uplc-ghc`, a GHC that ships the Plinth plugin as a built-in
static plugin. Use it as the compiler for a Plinth project, for example by
pointing `cabal` at it:

    $ cabal build -w _build/stage1/bin/uplc-ghc

Compiling a module that defines Plinth code then yields Plutus Core in addition
to the usual GHC outputs. For a ready-made project layout to start from, see the
[Plinth project template][plinth-template], and consult the
[Plinth user guide][plinth] for how to write and compile Plinth code.


How to test it?
===============

After building, run the `plinth-test.sh` script at the root of the repository:

    $ ./plinth-test.sh

It builds the example Plinth project under `plinth/test/` with `uplc-ghc` and
regenerates its expected outputs. Set `CLEAN=1` to force a clean rebuild:

    $ CLEAN=1 ./plinth-test.sh

There is also `plinth-bench.sh`, which builds and runs the `plutus-benchmark`
test-suites with `uplc-ghc` and reports any diffs against the golden files
committed under `plutus/plutus-benchmark/` (it requires the `plutus` submodule):

    $ ./plinth-bench.sh


  [1]:  http://www.haskell.org/ghc/            "www.haskell.org/ghc/"
  [2]:  https://gitlab.haskell.org/ghc/ghc/issues
          "gitlab.haskell.org/ghc/ghc/issues"
  [3]:  https://gitlab.haskell.org/ghc/ghc/wikis/building
          "https://gitlab.haskell.org/ghc/ghc/wikis/building"
  [4]:  http://www.haskell.org/happy/          "www.haskell.org/happy/"
  [5]:  http://www.haskell.org/alex/           "www.haskell.org/alex/"
  [6]:  http://www.haskell.org/haddock/        "www.haskell.org/haddock/"
  [7]: https://gitlab.haskell.org/ghc/ghc/wikis/building/getting-the-sources#cloning-from-github
          "https://gitlab.haskell.org/ghc/ghc/wikis/building/getting-the-sources#cloning-from-github"
  [8]:  https://gitlab.haskell.org/ghc/ghc/wikis/building/preparation
          "https://gitlab.haskell.org/ghc/ghc/wikis/building/preparation"
  [9]:  http://www.haskell.org/cabal/          "http://www.haskell.org/cabal/"
  [10]: https://gitlab.haskell.org/ghc/ghc/issues
          "https://gitlab.haskell.org/ghc/ghc/issues"
  [11]: http://www.haskell.org/pipermail/glasgow-haskell-users/
          "http://www.haskell.org/pipermail/glasgow-haskell-users/"
  [12]: https://gitlab.haskell.org/ghc/ghc/wikis/team-ghc
          "https://gitlab.haskell.org/ghc/ghc/wikis/team-ghc"
  [13]: https://github.com/ghc-proposals/ghc-proposals
          "https://github.com/ghc-proposals/ghc-proposals"
  [plinth]: https://plutus.cardano.intersectmbo.org/docs/
          "Plinth and Plutus Core Documentation"
  [cardano]: https://cardano.org/
          "cardano.org"
  [plutus-repo]: https://github.com/IntersectMBO/plutus
          "github.com/IntersectMBO/plutus"
  [plinth-template]: https://github.com/IntersectMBO/plinth-template
          "github.com/IntersectMBO/plinth-template"
