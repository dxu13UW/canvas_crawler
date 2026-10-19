# Log

Plans and changes, newest last. Reconstructed on 2026-10-18 from git history,
file timestamps, and the aider chat history; kept by hand from here on.

## 2026-10-08: First version (Python + Elixir hybrid)

**Plan:** get an email when a Canvas assignment is close to due and unsubmitted.

- A Python script (venv in `canvas_data/.venv`, using `requests`) called the
  Canvas API and wrote assignments to JSON in `canvas_data/`.
- An Elixir server read that JSON and sent SMTP reminders.
- `run_crawler.sh` added to run the service in a restart loop.
- This version wasn't committed to git.

## 2026-10-12: Move everything to Elixir

**Plan** (from my aider prompt): "currently the program runs a hybrid system
where python portion does a get api call and takes output as json, and elixir
runs a server to check this json and email me ... I want to change it so all
is done on elixir."

**Changes** (commit `df56238`):
- Replaced the Python poller with Elixir modules: `CalendarFeed`, `CanvasClient`,
  `Http`, `Processor`, `Notifier`, `Server`.
- Due dates now come from the Canvas calendar feed, which doesn't expire and
  covers every course. Date-only (11:59 pm) events are treated as 11:59:59 pm Pacific.
- Submission status comes from the API using the `canvas_session` cookie,
  because UW disables student API tokens.
- The refreshed cookie Canvas sends back is saved, to keep the session alive.
- Reminders go out for all courses. If the cookie expires, reminders still go
  out marked "status unknown", plus a single expired-cookie email.
- Submitted-but-ungraded work counts as done.
- Added tests (`mix test` runs with `--no-start`).
- An `erl_crash.dump` from this session is in the working tree (git-ignored).

**Then** (commit `baf43c6`): rewrote the README with how it works, config
files, running, and tests.

## 2026-10-18: Check and document

- Service was running. `crawler.log` shows a sync every 15 minutes:
  `Synced 106 assignments from 3 course(s); submission status: :ok`.
- `mix test`: 1 doctest, 5 tests, 0 failures.
- Added `CLAUDE.md` and this log. Linked the repo from the Artifact 2 card on my portfolio.

## Next

**Plan:** improve what the crawler already does rather than add new
features. Two examples:

- **More reminder windows.** Today there's one reminder at 24 hours. Add
  more (for example 3 days and 3 hours before), and make them configurable
  per course.
- **A daily digest email.** Today each email covers one assignment. Also
  send one morning email listing everything due in the next 7 days, with
  its submission status, using the data each sync already collects.

Cleanup:
- Move the hard-coded `/home/KO300/...` paths into config.
- Delete the leftover Python venv and `poller.log`.
