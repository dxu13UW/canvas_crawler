# lib/canvas_crawler/canvas_client.ex
defmodule CanvasCrawler.CanvasClient do
  @moduledoc """
  Builds the assignment list from two sources and writes a snapshot to disk:

    * the calendar feed (always available) supplies assignments and due dates;
    * the Canvas API, authenticated with the stored `canvas_session` cookie,
      supplies submission status when the cookie is still valid.
  """
  require Logger

  alias CanvasCrawler.{CalendarFeed, HTTP}

  @api_base "https://canvas.uw.edu/api/v1"
  @session_path "/home/KO300/.config/canvas_session.txt"
  @snapshot_path "/home/KO300/ELIXIR/canvas_crawler/canvas_data/assignments_latest.json"

  @doc """
  Returns `{:ok, assignments, submission_status}` where `submission_status` is
  `:ok`, `{:auth_expired, status}`, or `{:error, reason}`. When it isn't `:ok`,
  every assignment's `"workflow_state"` is `"unknown"`. Returns `{:error, reason}`
  only if the calendar feed itself can't be read.
  """
  def sync do
    with {:ok, feed_items} <- CalendarFeed.fetch() do
      course_ids =
        feed_items |> Enum.map(& &1["course_id"]) |> Enum.reject(&is_nil/1) |> Enum.uniq()

      {submissions, submission_status} =
        case fetch_submissions(course_ids) do
          {:ok, subs} -> {subs, :ok}
          {:error, {:auth_expired, _} = expired} -> {%{}, expired}
          {:error, reason} -> {%{}, {:error, reason}}
        end

      assignments =
        Enum.map(feed_items, &merge(&1, Map.get(submissions, &1["id"]), submission_status))

      write_snapshot(assignments, submission_status)

      Logger.info(
        "Synced #{length(assignments)} assignments from #{length(course_ids)} course(s); " <>
          "submission status: #{inspect(submission_status)}."
      )

      {:ok, assignments, submission_status}
    end
  end

  @doc false
  def merge(feed_item, submission, submission_status)

  def merge(feed_item, _submission, status) when status != :ok do
    Map.merge(feed_item, %{
      "workflow_state" => "unknown",
      "score" => nil,
      "points_possible" => nil
    })
  end

  # Assignment exists in the feed but not in the API response (e.g. hidden from the API).
  def merge(feed_item, nil, :ok) do
    Map.merge(feed_item, %{
      "workflow_state" => "unknown",
      "score" => nil,
      "points_possible" => nil
    })
  end

  def merge(feed_item, submission, :ok), do: Map.merge(feed_item, submission)

  @doc false
  def normalize(item) do
    sub = item["submission"] || %{}

    %{
      "points_possible" => item["points_possible"],
      "workflow_state" => Map.get(sub, "workflow_state", "unsubmitted"),
      "score" => sub["score"],
      "submitted_at" => sub["submitted_at"],
      "graded_at" => sub["graded_at"]
    }
  end

  # Returns %{assignment_id => normalized submission fields} across all courses.
  defp fetch_submissions(course_ids) do
    with {:ok, cookie} <- read_session_cookie() do
      result =
        Enum.reduce_while(course_ids, {:ok, %{}, cookie}, fn course_id, {:ok, acc, cookie} ->
          case fetch_all(initial_url(course_id), cookie, []) do
            {:ok, raw, cookie} ->
              {:cont, {:ok, Enum.into(raw, acc, &{&1["id"], normalize(&1)}), cookie}}

            error ->
              {:halt, error}
          end
        end)

      case result do
        {:ok, subs, latest_cookie} ->
          if latest_cookie != cookie, do: save_session_cookie(latest_cookie)
          {:ok, subs}

        error ->
          error
      end
    end
  end

  defp initial_url(course_id) do
    query =
      URI.encode_query([{"include[]", "submission"}, {"per_page", 100}, {"order_by", "due_at"}])

    "#{@api_base}/courses/#{course_id}/assignments?#{query}"
  end

  defp read_session_cookie do
    case File.read(@session_path) do
      {:ok, content} ->
        case String.trim(content) do
          "" -> {:error, {:session_file_empty, @session_path}}
          token -> {:ok, token}
        end

      {:error, reason} ->
        {:error, {:session_file_unreadable, @session_path, reason}}
    end
  end

  # Canvas paginates via the RFC 5988 Link header; follow rel="next" until exhausted.
  # Canvas also issues a fresh canvas_session on every response; carrying it forward
  # (and saving it) keeps the session alive instead of letting the pasted one expire.
  defp fetch_all(nil, cookie, acc), do: {:ok, acc |> Enum.reverse() |> List.flatten(), cookie}

  defp fetch_all(url, cookie, acc) do
    headers = [{"cookie", "canvas_session=#{cookie}"}, {"accept", "application/json"}]

    with {:ok, resp_headers, body} <- HTTP.get(url, headers),
         {:ok, page} when is_list(page) <- Jason.decode(body) do
      fetch_all(next_link(resp_headers), rotated_session(resp_headers) || cookie, [page | acc])
    else
      {:ok, other} -> {:error, {:unexpected_body, other}}
      error -> error
    end
  end

  defp rotated_session(headers) do
    Enum.find_value(headers, fn
      {~c"set-cookie", value} ->
        case Regex.run(~r/^\s*canvas_session=([^;]+)/, to_string(value)) do
          [_, session] -> session
          _ -> nil
        end

      _ ->
        nil
    end)
  end

  # Atomic replace; the file holds a credential, so keep it owner-only.
  defp save_session_cookie(cookie) do
    tmp_path = @session_path <> ".tmp"

    with :ok <- File.write(tmp_path, cookie),
         :ok <- File.chmod(tmp_path, 0o600),
         :ok <- File.rename(tmp_path, @session_path) do
      Logger.debug("Saved refreshed Canvas session cookie.")
    else
      {:error, reason} ->
        Logger.warning("Could not save refreshed session cookie: #{inspect(reason)}")
    end
  end

  defp next_link(headers) do
    with {_, value} <- List.keyfind(headers, ~c"link", 0) do
      value
      |> to_string()
      |> String.split(",")
      |> Enum.find_value(fn part ->
        case Regex.run(~r/<([^>]+)>;\s*rel="next"/, part) do
          [_, url] -> url
          _ -> nil
        end
      end)
    end
  end

  # Atomic file replacement avoids partial read states.
  defp write_snapshot(assignments, submission_status) do
    payload = %{
      "synced_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "submission_status" => inspect(submission_status),
      "assignment_count" => length(assignments),
      "assignments" => Enum.sort_by(assignments, & &1["due_at"])
    }

    tmp_path = @snapshot_path <> ".tmp"

    with :ok <- File.mkdir_p(Path.dirname(@snapshot_path)),
         :ok <- File.write(tmp_path, Jason.encode_to_iodata!(payload, pretty: true)),
         :ok <- File.rename(tmp_path, @snapshot_path) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("Could not write snapshot #{@snapshot_path}: #{inspect(reason)}")
    end
  end
end
