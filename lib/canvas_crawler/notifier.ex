# lib/canvas_crawler/notifier.ex
defmodule CanvasCrawler.Notifier do
  @moduledoc """
  Dispatches email notifications using the stored JSON SMTP credentials.
  """
  require Logger

  @config_path "/home/KO300/.config/canvas_email_config.json"

  def send_due_alerts([]), do: :ok

  def send_due_alerts(assignments) do
    subject = "[Canvas] #{length(assignments)} Assignment(s) Due Within 24 Hours"

    with :ok <- deliver(subject, format_email_body(assignments)) do
      Logger.info("Sent due date alert for #{length(assignments)} item(s).")
    end
  end

  def send_auth_alert(status_code) do
    subject = "[ACTION REQUIRED] Canvas Crawler: Session Cookie Expired"

    with :ok <- deliver(subject, format_auth_body(status_code)) do
      Logger.info("Sent auth failure alert (status #{status_code}).")
    end
  end

  defp deliver(subject, body) do
    with {:ok, config} <- load_config() do
      email_raw =
        """
        From: #{config["sender_email"]}
        To: #{config["recipient_email"]}
        Subject: #{subject}
        MIME-Version: 1.0
        Content-Type: text/plain; charset=utf-8

        #{body}
        """

      # Pass sockopts to ssl:connect to satisfy OTP 26+ certificate validation
      smtp_opts = [
        relay: String.to_charlist(config["smtp_server"]),
        port: config["smtp_port"],
        ssl: Map.get(config, "use_ssl", true),
        tls: :never,
        tls_options: [verify: :verify_none],
        sockopts: [verify: :verify_none],
        username: String.to_charlist(config["sender_email"]),
        password: String.to_charlist(config["sender_password"]),
        auth: :always
      ]

      case :gen_smtp_client.send_blocking(
             {config["sender_email"], [config["recipient_email"]], email_raw},
             smtp_opts
           ) do
        receipt when is_binary(receipt) ->
          :ok

        {:error, _type, _msg} = error ->
          Logger.error("Failed to send email \"#{subject}\": #{inspect(error)}")
          error

        {:error, _reason} = error ->
          Logger.error("Failed to send email \"#{subject}\": #{inspect(error)}")
          error
      end
    end
  end

  defp load_config do
    with {:ok, content} <- File.read(@config_path),
         {:ok, json} <- Jason.decode(content) do
      {:ok, json}
    else
      err ->
        Logger.error("Could not load email configuration at #{@config_path}: #{inspect(err)}")
        {:error, err}
    end
  end

  defp format_email_body(assignments) do
    items_text =
      Enum.map_join(assignments, "\n", fn item ->
        due_display =
          (item["due_at"] || "")
          |> String.slice(0, 16)
          |> String.replace("T", " ")

        status =
          case item["workflow_state"] do
            "unknown" -> "unknown (Canvas session cookie expired)"
            state -> state
          end

        """
        - #{item["name"]}
          Course: #{item["course"]}
          Status: #{status}
          Due At: #{due_display} UTC
          Points: #{item["points_possible"] || "-"}
          Link:   #{item["html_url"]}
        """
      end)

    unknown_note =
      if Enum.any?(assignments, &(&1["workflow_state"] == "unknown")) do
        "\nItems marked \"unknown\" may already be done: submission status can't be checked " <>
          "until the session cookie is refreshed.\n"
      else
        ""
      end

    """
    Canvas Homework Reminder
    ========================
    The following items are due in less than 24 hours and have not been completed/graded:

    #{items_text}#{unknown_note}
    Remember to verify final submission directly in external tools such as WebAssign.
    """
  end

  defp format_auth_body(status_code) do
    """
    Canvas Session Expired for Canvas Crawler
    =========================================
    Status Code Encountered: #{status_code}
    Timestamp: #{DateTime.utc_now() |> DateTime.to_iso8601()}

    The crawler can't read submission status because the session cookie has expired or was revoked.
    Due-date reminders still arrive (from the calendar feed), but every upcoming item is
    reported as "status unknown", even ones you've already submitted, until the cookie is replaced.

    HOW TO EXTRACT AND UPDATE THE COOKIE:
    -------------------------------------
    1. Open Google Chrome/Brave/Edge and navigate to:
       https://canvas.uw.edu
       (Ensure you are fully logged in).

    2. Press F12 (or right-click -> Inspect) to open Developer Tools.

    3. Navigate to:
       Application (tab) -> Storage -> Cookies -> https://canvas.uw.edu

    4. In the filter box at the top, type:
       canvas_session

    5. Double-click the "Value" cell and copy the entire continuous string.

    6. In your Debian WSL terminal, update the secret file by running:
       echo -n "PASTE_COPIED_COOKIE_HERE" > /home/KO300/.config/canvas_session.txt

    The running service picks up the new cookie on its next check (within 15 minutes).
    To check immediately:
       cd /home/KO300/ELIXIR/canvas_crawler && mix run --no-start -e 'Application.ensure_all_started([:inets, :ssl]); CanvasCrawler.CanvasClient.sync() |> elem(2) |> IO.inspect()'
    It should print :ok.
    """
  end
end
