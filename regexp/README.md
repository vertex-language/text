# text/regexp

Regular expressions as ECMAScript writes them, matched by backtracking over a string's Unicode scalars: what HTML's `pattern` attribute needs, and what a program reaches for.

```vertex
import "text/regexp"

let zip = regexp.Regexp.Compile("\\d{5}(-\\d{4})?", flags: "v")!
zip.MatchesWhole("12345-6789")   // true
```

## Syntax

Alternation; groups (capturing, `(?:…)`, named `(?<name>…)`); lookahead `(?=…)` `(?!…)` and lookbehind `(?<=…)` `(?<!…)`; backreferences `\1` and `\k<name>`; `*` `+` `?` `{n}` `{n,}` `{n,m}`, greedy or lazy; classes with ranges, negation and nested classes; `.` `\d` `\w` `\s` and their negations; `\p{…}` by general category (`L`, `Lu`, `Letter`), `Script=` or `Script_Extensions=`, or binary property (`Alphabetic`, `White_Space`, `Emoji`); `^` `$` `\b` `\B`; `\n` `\t` `\xHH` `\uHHHH` `\u{…}`. Flags: `i` (simple case folding), `m`, `s`; `u` and `v` (it is always in Unicode mode).

## Functions

- `Regexp.Compile(_ pattern: string, flags: string = "") -> Regexp?`: nil where the pattern isn't valid.
- `Matches(_ s: string) -> bool`: a match anywhere.
- `MatchesWhole(_ s: string) -> bool`: the whole string, as `^(?:pattern)$`.
- `Find(_ s: string) -> (start: int, end: int, groups: [string?])?`: the first match, in scalars, with each group's text.
- `GroupIndex(_ name: string) -> int?`: a named group's number.

A pattern that backtracks without end (`(a+)+b` against a long run of `a`) gives up after two million steps and answers no match.
