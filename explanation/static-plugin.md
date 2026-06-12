---
layout: default
title: The built-in static plugin
parent: Explanation
nav_order: 2
---

# The built-in static plugin

GHC supports two ways of supplying a Core plugin:

- **Dynamic plugins** are ordinary packages named on the command line (or in a
  project's configuration) with `-fplugin`. GHC loads them at run time. This is
  how `plutus-tx-plugin` is normally used.
- **Static plugins** are compiled *into* a GHC binary. They run as part of the
  compilation pipeline without the user having to request them.

## Why bake the plugin in?

This fork ships the Plinth plugin as a built-in *static* plugin. The result,
`uplc-ghc`, behaves like a regular GHC but always runs the Plinth pass, so it
emits Plutus Core for Plinth modules **without any extra plugin configuration
on the user's side** &mdash; no `-fplugin` flags, no plugin package to add as a
dependency.

This matters because the Plinth-to-Plutus-Core translation is sensitive to how
GHC compiles the surrounding code (optimisation passes, inlining, and so on).
Pinning the plugin to a specific GHC build keeps the compiler and the plugin in
lockstep, which makes the generated Plutus Core reproducible and lets the fork
be validated as a single unit (see
[Test and benchmark the compiler]({% link how-to/test.md %})).

## What it means in practice

To a user, `uplc-ghc` is just a compiler: point cabal at it with `-w` and build
as usual (see [Use uplc-ghc in a project]({% link how-to/use.md %})). The Plinth
machinery is invisible until a module actually defines Plinth code, at which
point the corresponding Plutus Core appears alongside the normal outputs.
