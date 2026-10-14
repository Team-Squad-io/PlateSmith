# PlateSmith example module

This is a deliberately small, dependency-free third-party addon. It demonstrates
PlateSmith's public module API (`Docs/MODULES.md` in the PlateSmith download) without
touching PlateSmith's runtime files.

## Install

Copy the whole `PlateSmith_ExampleModule` folder beside `PlateSmith` in the game's
`Interface/AddOns` directory, then restart or reload the client. The TOC declares
`## Dependencies: PlateSmith`, so PlateSmith always loads first. (A copy nested inside
the `PlateSmith` folder, as it ships, is never loaded by the game.)

Blueprint Studio's preview and tree then list an **Example accent badge**. It is a
preview part only: nothing draws it on a real plate. Custom text can show the accent
with `{example.accent}`. Exported Blueprints include an `example.accent` field with
one of `blue`, `gold`, or `green`.

## Contract demonstrated

- Register one module ID in PlateSmith's ID grammar (`example`) with a tested
  `apiMin`/`apiMax` range; everything it adds is `example.<name>`.
- Call PlateSmith with a colon (`PlateSmith:RegisterModule`); the dot form works too.
- Allocate UI once, retain it, and update or reparent it instead of recreating it.
- Start behavior in `OnEnable` and completely hide owned UI in `OnDisable`.
- Give the module its own small SavedVariables table rather than writing private
  keys into PlateSmith's database.
- Parse Blueprint input against an allowlist. Imported text is data and is never
  executed as Lua.
- Register a text token (`{example.accent}`, the accent name) and a formatter
  (`{level:example.brackets}` shows `<14>`) for value templates, both declaring the
  tested `styleApiMin`/`styleApiMax`.
- Use no update loop. This example only reacts to lifecycle, editor, and import
  callbacks.

The preview part lasts for the UI session because PlateSmith's registry does not
unregister definitions. The module therefore makes its callbacks safe while disabled
and hides its retained child frame. A production module should follow the same
pattern unless a future API explicitly adds dynamic unregistration.
