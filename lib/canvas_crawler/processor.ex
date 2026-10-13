# lib/canvas_crawler/processor.ex
defmodule CanvasCrawler.Processor do
  @moduledoc """
  Parses Canvas assignment snapshots and filters items due within 24 hours
  that are not yet graded or completed.
  """

  @json_path "/home/KO300/ELIXIR/canvas_crawler/canvas_data/assignments_latest.json"

  def load_assignments(path \\ @json_path) do
    with {:ok, content} <- File.read(path),
         {:ok, %{"assignments" => assignments}} <- Jason.decode(content) do
      {:ok, assignments}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  def filter_pending_due_soon(assignments, now \\ DateTime.utc_now()) do
    Enum.filter(assignments, fn item ->
      due_soon?(item["due_at"], now) and not_completed?(item)
    end)
  end

  defp due_soon?(nil, _now), do: false

  defp due_soon?(due_at_str, now) do
    case DateTime.from_iso8601(due_at_str) do
      {:ok, due_dt, _offset} ->
        diff_seconds = DateTime.diff(due_dt, now, :second)
        diff_seconds > 0 and diff_seconds <= 86_400

      _ ->
        false
    end
  end

  # "unknown" (no valid session cookie) counts as not completed, so reminders still go out.
  defp not_completed?(%{"workflow_state" => state, "score" => score}) do
    state not in ["submitted", "pending_review", "graded"] and is_nil(score)
  end
end
