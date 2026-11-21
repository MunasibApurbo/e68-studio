# Working with AI agents on a project this size

E68 Studio is about 40,000 lines of Swift written across many sessions and more than one AI tool. These habits kept it coherent.

## Keep state in files, not in a chat

- `AGENTS.md` (root): rules, build commands, what the owner rejected. Every harness reads it, or can be pointed at it.
- `PROGRESS.md`: phase checklist with evidence. The single source of "where are we".
- `device-profile.yaml`: hardware facts and quirks.
- `HANDOFF.md`: written at the end of any session that leaves work half done. What's done, what's next in order, rules, how to check. `Docs/Archive/ANTIGRAVITY_HANDOFF.md` is a real one from this project.

A fresh session that reads these four files should be able to continue without asking anything.

## The "Rejected" list

When the owner says no to something ("too cartoonish", "remove the spotlight"), write it in `AGENTS.md` under **Rejected**, in their words. Agents otherwise reintroduce rejected ideas in later sessions, which costs trust fast.

## Parallel work

Once the skeleton exists, keyboard, mouse and lighting phases are independent. Run them in separate sessions or worktrees, one per folder. Never let two agents edit the same files; merge one at a time and run `--selftest` after each merge.

## Commits

Commit at the end of every phase, and before any large refactor. Uncommitted work piled up twice in this project (100+ files each time), which made review and rollback hard. Small, named commits ("Phase 3: macro write and verify") make it easy to see what each session did.

## Asking the owner

Batch questions, recommend an answer for each, and only ask what is theirs to decide: features, looks, money (Developer ID), downloads, risky writes. Everything else, decide and note the decision in `PROGRESS.md`.

## Memory across sessions

If your harness has persistent memory (Claude Code's memory, Cursor's memories), store non-obvious, hard-won facts there too: "the G7 web driver bundle does not contain the protocol; capture traffic instead". Facts that are already in the repo don't need to be stored twice.
