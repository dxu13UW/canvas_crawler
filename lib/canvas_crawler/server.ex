# lib/canvas_crawler/server.ex
defmodule CanvasCrawler.Server do
  @moduledoc """
  Autonomous monitor and deduplication engine for Canvas assignment deadlines.
  Each tick pulls fresh data from Canvas, then emails any newly urgent items.
  """

  use GenServer
  require Logger

  alias CanvasCrawler.{CanvasClient, Notifier, Processor}

  @poll_interval :timer.minutes(15)

  # Persisted on disk so a restart doesn't re-send the auth alert for the same expiration.
  @auth_alert_flag "/home/KO300/ELIXIR/canvas_crawler/canvas_data/.auth_alert_sent"

  defmodule State do
    @moduledoc false
    defstruct notified_ids: MapSet.new()
  end

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def force_check do
    GenServer.call(__MODULE__, :check_now, :timer.minutes(1))
  end

  # --- Callbacks ---

  @impl true
  def init(_opts) do
    Logger.info("Starting CanvasCrawler.Server monitor...")
    # Initial trigger after 1 second, then periodic
    Process.send_after(self(), :check_assignments, 1_000)
    {:ok, %State{}}
  end

  @impl true
  def handle_call(:check_now, _from, state) do
    new_state = run_check(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:check_assignments, state) do
    new_state = run_check(state)
    Process.send_after(self(), :check_assignments, @poll_interval)
    {:noreply, new_state}
  end

  defp run_check(state) do
    case CanvasClient.sync() do
      {:ok, assignments, submission_status} ->
        case submission_status do
          :ok ->
            File.rm(@auth_alert_flag)

          {:auth_expired, status} ->
            Logger.warning("Canvas session expired (HTTP #{status}); completion status unknown.")
            maybe_send_auth_alert(status)

          {:error, reason} ->
            Logger.warning("Could not fetch submission status: #{inspect(reason)}")
        end

        # Due-date reminders go out either way; without a valid cookie they're
        # sent for every upcoming item and marked "status unknown".
        process_pending_items(assignments, state)

      {:error, reason} ->
        Logger.warning("Unable to read the Canvas calendar feed: #{inspect(reason)}")
        state
    end
  end

  defp maybe_send_auth_alert(status) do
    unless File.exists?(@auth_alert_flag) do
      with :ok <- Notifier.send_auth_alert(status) do
        File.touch(@auth_alert_flag)
      end
    end
  end

  defp process_pending_items(assignments, %State{notified_ids: notified_ids} = state) do
    urgent_items = Processor.filter_pending_due_soon(assignments)

    to_notify =
      Enum.reject(urgent_items, fn item -> MapSet.member?(notified_ids, item["id"]) end)

    success_ids =
      if to_notify != [] do
        case Notifier.send_due_alerts(to_notify) do
          :ok -> Enum.map(to_notify, & &1["id"])
          _ -> []
        end
      else
        []
      end

    urgent_id_set = MapSet.new(urgent_items, & &1["id"])

    updated_notified =
      notified_ids
      |> MapSet.intersection(urgent_id_set)
      |> MapSet.union(MapSet.new(success_ids))

    %State{state | notified_ids: updated_notified}
  end
end
