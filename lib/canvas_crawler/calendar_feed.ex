# lib/canvas_crawler/calendar_feed.ex
defmodule CanvasCrawler.CalendarFeed do
  @moduledoc """
  Reads assignment due dates from the user's private Canvas calendar feed (.ics).
  The feed URL never expires, so due dates stay available even when the session
  cookie does not. It carries no submission status.
  """

  alias CanvasCrawler.HTTP

  @feed_url_path "/home/KO300/.config/canvas_calendar_feed.txt"
  @local_zone "America/Los_Angeles"

  @doc "Fetches and parses the feed into assignment maps."
  def fetch do
    with {:ok, url} <- read_feed_url(),
         {:ok, _headers, body} <- HTTP.get(url) do
      {:ok, parse(body)}
    end
  end

  @doc """
  Parses .ics text into maps with `"id"`, `"course_id"`, `"course"`, `"name"`,
  `"due_at"` (ISO 8601 UTC) and `"html_url"`. Non-assignment events are dropped.
  """
  def parse(ics) do
    ics
    |> unfold()
    |> String.split("BEGIN:VEVENT")
    |> Enum.drop(1)
    |> Enum.map(&parse_event/1)
    |> Enum.flat_map(&to_assignment/1)
  end

  defp read_feed_url do
    case File.read(@feed_url_path) do
      {:ok, content} ->
        case String.trim(content) do
          "" -> {:error, {:feed_url_file_empty, @feed_url_path}}
          url -> {:ok, url}
        end

      {:error, reason} ->
        {:error, {:feed_url_file_unreadable, @feed_url_path, reason}}
    end
  end

  # RFC 5545: long lines continue on the next line after a CRLF + single space/tab.
  defp unfold(ics), do: String.replace(ics, ~r/\r?\n[ \t]/, "")

  defp parse_event(block) do
    block
    |> String.split(~r/\r?\n/)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, ":", parts: 2) do
        [name_and_params, value] ->
          [name | params] = String.split(name_and_params, ";")
          Map.put_new(acc, name, {params, value})

        _ ->
          acc
      end
    end)
  end

  defp to_assignment(%{"UID" => {_, "event-assignment-" <> id}} = event) do
    with {_, summary} <- event["SUMMARY"],
         {params, dtstart} <- event["DTSTART"],
         {:ok, due_at} <- parse_due(params, dtstart) do
      {name, course} = split_summary(unescape(summary))
      course_id = course_id(event)

      [
        %{
          "id" => String.to_integer(id),
          "course_id" => course_id,
          "course" => course,
          "name" => name,
          "due_at" => DateTime.to_iso8601(due_at),
          "html_url" => "https://canvas.uw.edu/courses/#{course_id}/assignments/#{id}"
        }
      ]
    else
      _ -> []
    end
  end

  defp to_assignment(_event), do: []

  # Canvas exports an 11:59 pm deadline as an all-day event (date only), so treat
  # a bare date as 23:59:59 Pacific on that day.
  defp parse_due(params, value) do
    if "VALUE=DATE" in params do
      with {:ok, date} <- Date.from_iso8601(basic_to_extended_date(value)),
           {:ok, local} <- DateTime.new(date, ~T[23:59:59], @local_zone, Tz.TimeZoneDatabase) do
        DateTime.shift_zone(local, "Etc/UTC", Tz.TimeZoneDatabase)
      end
    else
      # Timed events are exported in UTC, e.g. 20261015T185000Z.
      case Regex.run(~r/^(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z$/, value) do
        [_, y, mo, d, h, mi, s] ->
          {:ok, dt, _} = DateTime.from_iso8601("#{y}-#{mo}-#{d}T#{h}:#{mi}:#{s}Z")
          {:ok, dt}

        _ ->
          {:error, {:unsupported_dtstart, value}}
      end
    end
  end

  defp basic_to_extended_date(<<y::binary-4, m::binary-2, d::binary-2>>), do: "#{y}-#{m}-#{d}"
  defp basic_to_extended_date(other), do: other

  # "Worksheet 2 [TMATH 126 B]" -> {"Worksheet 2", "TMATH 126 B"}
  defp split_summary(summary) do
    case Regex.run(~r/^(.*)\s\[([^\]]+)\]$/s, summary) do
      [_, name, course] -> {name, course}
      _ -> {summary, nil}
    end
  end

  defp course_id(event) do
    with {_, url} <- event["URL"],
         [_, id] <- Regex.run(~r/course_(\d+)/, url) do
      id
    else
      _ -> nil
    end
  end

  defp unescape(text) do
    text
    |> String.replace(~r/\\[nN]/, "\n")
    |> String.replace(~r/\\([,;\\])/, "\\1")
  end
end
