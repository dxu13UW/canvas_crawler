# CanvasCrawler

Elixir OTP service that watches my Canvas (canvas.uw.edu) courses and emails me
when an assignment is due within 24 hours and I haven't submitted it. Runs
locally in WSL; see `README.md` for setup and configuration. Built as CS490
Artifact 2 (spec: `Artifact_2.txt`).

## Layout

- `lib/canvas_crawler/server.ex`: GenServer that polls every 15 minutes and dedupes reminders
- `lib/canvas_crawler/calendar_feed.ex`: parses the Canvas iCal feed for due dates
- `lib/canvas_crawler/canvas_client.ex`: Canvas API calls for submission status (session-cookie auth)
- `lib/canvas_crawler/http.ex`: thin `:httpc` wrapper
- `lib/canvas_crawler/processor.ex`: decides which items need a reminder
- `lib/canvas_crawler/notifier.ex`: SMTP email via `gen_smtp`
- `run_crawler.sh`: restart loop around `mix run --no-halt`, logs to `crawler.log`

## Commands

- `mix test`: runs with `--no-start` (aliased in `mix.exs`), so it never hits Canvas or sends email
- `./run_crawler.sh`: start the service
- `pkill beam.smp`: restart after code changes (the loop relaunches and recompiles)
- `tail -f crawler.log`: a healthy sync logs `Synced N assignments ... submission status: :ok`

## Constraints

- UW disables student API tokens, so the API is authenticated with the browser
  `canvas_session` cookie. Canvas refreshes it on responses and the client
  writes it back to `~/.config/canvas_session.txt`. Don't break that save.
- If the cookie expires, reminders must still go out from the calendar feed
  (marked status unknown), plus one "cookie expired" email.
- Submitted-but-ungraded counts as done.
- Secrets live in `~/.config/` (feed URL, cookie, SMTP config). Never commit
  them. `canvas_data/*.json` contains grades and is git-ignored.
- Paths are hard-coded to `/home/KO300/...`.

## Working notes

- Record plans and changes in `LOG.md` as you go.
- `canvas_data/.venv` and `poller.log` are leftovers from the old Python poller.
