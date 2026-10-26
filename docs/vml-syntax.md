# VML syntax: control flow, expressions, ids, inputs and imports

This page covers the parts of VML that follow V: structural `if` and `for`,
V expressions and assignments, ids that double as refs, input types, `watch`
and module imports. [VML components](vml-components.md) covers components,
slots and lifetime.

## `if`, `else if`, `else`

```vml
Column {
    if app.phase == "draft" {
        DraftBoard()
    } else if app.phase == "playing" {
        Board()
    } else {
        Label(text: "Game over")
    }
    if player := app.winner {
        Label(text: "${player.name} wins")
    }
}
```

A branch mounts its children when it is chosen and unmounts them when another
branch is: they get a new state each time they mount, and their motion
presence exit plays as they leave. `hidden:` still only hides an element and
keeps its state. `if name := option` chooses the branch while the option has a
value and binds `name` to it inside the branch; `else` covers `none`.

## `for`

```vml
for route in app.routes key route.id {
    RouteRow(route: route)
}
for index, card in app.hand key card.id {
    Card(card: card, x: index * 40)
}
```

A `for` iterates an array. The key is required and identifies each item
independently of its position: reordering moves the item's instance and its
state. The key reads the item only. The loop names are scoped to each item;
nested loops use distinct names, since a name cannot shadow another.

## Expressions

VML expressions are V expressions: indexing and chaining work after any value,
`app.board[r][c]`, `app.player().name.to_upper()`, `scores["a"]`, and `or`
supplies a value for an option, `app.winner or { default_player }`.

## Assignments

An action assigns to any place V can: a field, an index, a nested field, with
`=`, `+=`, `-=`, `*=`, `/=`, `%=` or `<<`. The root must be writable: `app`, a
component `state`, or a `bind` input. Loop names are read-only.

```vml
Button(on_click: app.board[r][c].claimed = true)
Button(on_click: { score += 10; app.log << "scored" })
```

## Ids are refs

An id is an unquoted local name. Calling one of its ref methods (`focus`,
`set_text`, `is_available`, `id`, `element`) or passing it to a function makes
it a ref; there is no separate declaration.

```vml
Column {
    TextInput(id: name_field)
    Button(text: "Focus", on_click: name_field.focus()!)
}
```

`name_field.width` and the other geometry fields read the element's frame. An
element inside a `for` is one per item and has no ref.

## Input types

A component input takes any V type: `[]T`, `map[K]V`, an optional `?T` and a
function `fn (A) R`. An optional input is `none` when the caller omits it and
cannot be bindable; a function input is called by name.

```vml
component ScoreCard(scores map[string]int, choice ?string, format fn (int) string) {
    Column {
        Label(text: format(scores["a"]))
        if name := choice { Label(text: name) }
    }
}
```

## `watch`

```vml
component Timer(seconds int) {
    watch old, now := seconds {
        app.log_change(old, now)
    }
    Label(text: "${seconds}")
}
```

A `watch` runs its body each time the watched value changes, with the old and
new values (`watch now := value { }` names the new value only). The first
value is recorded without running the body. The body runs as one action:
writes batch, and the document updates after it.

## Imports

Components of the document's own folder need no import: `RouteRow` is
`route_row.vml` or `RouteRow.vml` there, when that file declares
`component RouteRow(...)`. Components of other folders come from module
imports, as V names functions of other modules:

```vml
import widgets { Badge, Gauge }
import ui.kit
Column {
    Badge(text: "new")
    kit.Chip(text: "chip")
}
```

A module path `a.b` is the folder `a/b` under the project root (the nearest
folder above the document with a `v.mod`), then under `~/.vmodules`. A dotted
tag whose prefix is not an imported module names a V widget of that module
(`pkg.Gauge`, built from `pkg.GaugeProps`).

## The interpreter

`ui2 dev` interprets documents for instant preview. It supports `if`, `for`,
indexing, `or`, compound assignments to `app` fields, state and inputs, id
refs and `watch`. Method calls on values, assignments to nested places and
function inputs need compiled VML (`ui2 gen`); the interpreter reports them
when it loads the document.
