# Device Studio Framework

A playbook for building your own **native companion app for the keyboard and mouse on your desk**, the way E68 Studio was built, with an AI coding agent doing the typing.

It is harness-neutral: everything is plain Markdown plus two small Swift tools, so it works with Claude Code, OpenAI Codex, Cursor, Gemini CLI, Aider, Windsurf, or anything else that can read files and run a shell.

E68 Studio, the app in the parent folder, is the worked example. Every phase points at the file in this repo that solved the same problem.

## What you end up with

A macOS app (SwiftUI, no dependencies) that, depending on what your hardware allows:

- reads and remaps your keyboard's keys, knob, layers and macros (VIA/QMK boards, fully; others, as far as their protocol is known)
- drives the backlight from music, screen colours or your wallpaper
- remaps mouse buttons, gestures, scroll and pointer speed through macOS itself, so it works with any mouse
- shows battery levels, a key tester, per-app profiles, and a menu bar companion
- optionally: a 3D model of your own desk, rendered live

## How to use it

1. **Start a new, empty repository** and copy this `Framework/` folder into it.
2. **Wire it into your harness** (one file, see the table below).
3. **Plug in your devices** by USB if you can. USB exposes the most interfaces.
4. Tell the agent:

   > Read `Framework/START.md` and follow it. Start with phase 0.

The agent interviews you, probes your hardware read-only, writes a device profile, and then builds the app phase by phase. Each phase ends with checks it must pass before moving on. Progress is kept in `PROGRESS.md`, so any agent (or a new session) can pick up where the last one stopped.

| Harness | Wire-up |
|---|---|
| Claude Code | Copy `adapters/claude-code/SKILL.md` to `.claude/skills/device-studio/SKILL.md`, and copy `templates/AGENTS.md` to the repo root with a `CLAUDE.md` containing `@AGENTS.md` |
| Codex, Jules, Amp, Aider, opencode, Zed | Copy `templates/AGENTS.md` to the repo root (they read `AGENTS.md` natively) |
| Cursor | Copy `adapters/cursor/device-studio.mdc` to `.cursor/rules/` and `templates/AGENTS.md` to the root |
| Gemini CLI | Copy `templates/AGENTS.md` to the root as `GEMINI.md` (or point Gemini's context file setting at `AGENTS.md`) |
| Anything else | Paste the contents of `START.md` as the first message |

## What's inside

```text
START.md                     the orchestrator: rules, phase order, how to track progress
phases/
  00-interview.md            what to ask the owner; produces device-profile.yaml
  01-discover.md             read-only hardware discovery with the probe tools
  02-skeleton.md             SwiftPM app, folder layout, --selftest from day one
  03-keyboard.md             VIA/QMK keymap, macros, lighting; non-VIA boards
  04-mouse.md                pointer tuning and button remapping that work with any mouse
  05-lighting-sync.md        music, screen and wallpaper reactive lighting
  06-interface.md            SwiftUI app, menu bar, settings, permissions UX
  07-3d-desk.md              optional: your desk in 3D, verified with headless renders
  08-ship.md                 app bundle, signing, notarisation, README, licence
playbooks/
  hardware-safety.md         the rules that keep you from bricking a device
  protocol-discovery.md      what to do when the protocol is undocumented
  verification.md            how an agent proves its work without bothering you
  working-with-agents.md     handoffs, rules files, the "rejected" list, one writer at a time
templates/
  AGENTS.md                  drop-in rules file for the new repo
  device-profile.yaml        the hardware facts every phase reads
  PROGRESS.md                phase checklist the agent keeps current
  HANDOFF.md                 for passing work between sessions or tools
tools/
  hid-probe.swift            lists every HID device and interface (read-only)
  via-probe.swift            asks a VIA keyboard its version, layers and macro space (read-only)
adapters/                    harness-specific wrappers
```

## Requirements

- macOS 26 for the reference app. A new app can target macOS 14.2+ (the CoreAudio process tap's minimum) if it skips Liquid Glass styling.
- Xcode Command Line Tools (`xcode-select --install`)
- An agent that can run shell commands

## Honest limits

- **VIA/QMK keyboards** get full key, macro and lighting control. Most other keyboards speak an undocumented vendor protocol. The framework teaches safe discovery, but some features (per-key RGB on many boards, on-board mouse DPI) may only be reachable by capturing the vendor's own software. E68 Studio hit both walls; see `playbooks/protocol-discovery.md`.
- **Mouse features** are done through macOS (event taps and HID service properties), not the mouse's firmware, so they work for any mouse but only while the app runs.
- The app is not sandboxed, so it cannot go on the Mac App Store. Direct distribution with notarisation works.
