# CanvasCrawler

An Elixir service that watches my Canvas (canvas.uw.edu) courses and emails me
when an assignment is due within 24 hours and I haven't submitted it yet.

## How it works

Every 15 minutes `CanvasCrawler.Server`:

1. **Reads due dates from the Canvas calendar feed** (`CalendarFeed`). The feed
   URL never expires and covers every enrolled course. Assignments due at
   11:59 pm appear as date-only events and are treated as 11:59:59 pm Pacific.
2. **Reads submission status from the Canvas API** (`CanvasClient`),
   authenticated with a browser `canvas_session` cookie, since student API
   tokens are disabled at UW. Canvas returns a refreshed cookie on its
   responses; the crawler saves it back to disk to keep the session alive.
3. **Emails reminders** (`Notifier`) for items due in the next 24 hours that
   aren't submitted, pending review, or graded. Each item is emailed once.

If the cookie expires, reminders still go out from the feed alone, marked
*status unknown*, and a single "session cookie expired" email explains how to
replace it.

Each sync also writes `canvas_data/assignments_latest.json` (git-ignored) for
debugging.

## Requirements

- Elixir 1.14+ on Erlang/OTP 25+ (developed on Elixir 1.18 / OTP 27, in WSL)
- An SMTP account to send from (e.g. Gmail with an app password)

## Configuration

Three files in `~/.config/`, all kept out of the repo. Keep them owner-only
(`chmod 600`).

| File | Contents |
| --- | --- |
| `canvas_calendar_feed.txt` | Calendar feed URL: in Canvas, **Calendar → Calendar Feed** (bottom right). |
| `canvas_session.txt` | The `canvas_session` cookie value (see below). Rewritten by the crawler as Canvas refreshes it. |
| `canvas_email_config.json` | SMTP settings (see below). |

`canvas_email_config.json`:

```json
{
  "smtp_server": "smtp.gmail.com",
  "smtp_port": 465,
  "use_ssl": true,
  "sender_email": "sender@example.com",
  "sender_password": "app-password",
  "recipient_email": "me@example.com"
}
```

**Getting the session cookie:** log in to https://canvas.uw.edu, open DevTools
(F12) → **Application → Cookies → https://canvas.uw.edu**, copy the value of
`canvas_session`, then:

```zsh
echo -n "PASTE_COOKIE_HERE" > ~/.config/canvas_session.txt
```

> File paths are currently hard-coded to `/home/KO300/...` in
> `lib/canvas_crawler/*.ex` and `run_crawler.sh`; change them if you run this
> elsewhere.

## Running

```zsh
mix deps.get
./run_crawler.sh      # runs `mix run --no-halt` in a restart loop, logging to crawler.log
```

On my machine a Windows Task Scheduler task launches `run_crawler.sh` in WSL at
logon.

**Check it's running:**

```zsh
pgrep -af "run_crawler|beam.smp"
tail -f crawler.log   # look for "Synced N assignments ... submission status: :ok"
```

**Apply code changes:** `pkill beam.smp`; the loop restarts it within 5 s and
`mix run` recompiles.

**Check the cookie without starting the service** (prints `:ok` if valid):

```zsh
mix run --no-start -e 'Application.ensure_all_started([:inets, :ssl]); CanvasCrawler.CanvasClient.sync() |> elem(2) |> IO.inspect()'
```

## Tests

```zsh
mix test
```

Tests run with `--no-start`, so they never contact Canvas or send email.
