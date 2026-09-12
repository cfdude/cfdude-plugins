# cross-session-messaging

A skill for working with Claude Code's [cross-session
messaging](https://code.claude.com/docs/en/cross-session-messaging) — the feature that
lets one of your sessions discover and message another.

It loads before the first `SendMessage` or `ListAgents` of a session, and again whenever a
message arrives and Claude is about to reply. **Replying is sending**, and that is the case
people forget, because answering feels like continuing a conversation rather than starting
one.

## Install

```
/plugin marketplace add cfdude/cfdude-plugins
/plugin install cross-session-messaging@cfdude-plugins
```

## What it covers

- **Addressing.** The name is the address; the `[ref]` is a tiebreaker, not a requirement —
  and that reversed between 2.1.227 and 2.1.232, so the file carries version stamps.
- **`success: true` is not delivery.** Five ways a send reports success and is never read,
  with the version each one was fixed in.
- **Permission-class partitioning**, including the asymmetry people miss: a bypassing
  recipient holds everything, a prompting recipient holds almost nothing.
- **Determining your own permission mode** with `$PPID`, and the three cases where that
  method is unsound.
- **Permission laundering** — what the harness actually enforces, and what is only an
  instruction.
- **A QA rule**: test it, never reason about it.

## The boundary section is a template

The skill opens with a trust-boundary policy deciding whether one session may message
another at all. **Replace it.** The tests in it are shaped like mine with the specifics
removed; yours will differ.

Keep the structure, which is the part that generalizes: multiple independent signals, no
single test treated as authoritative, and anything unclear routed to a human rather than
defaulting to permitted. That shape exists because two earlier single-signal versions were
each confidently wrong, in exactly the direction their evidence hadn't come from.

Your boundary policy belongs in `CLAUDE.md`, where it is always in context. This skill only
restates it so it can't be missed at send time.

## License

MIT
