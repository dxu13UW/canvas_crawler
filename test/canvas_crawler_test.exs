defmodule CanvasCrawlerTest do
  use ExUnit.Case
  doctest CanvasCrawler

  alias CanvasCrawler.{CalendarFeed, CanvasClient, Processor}

  @now ~U[2026-10-13 12:00:00Z]

  @ics """
  BEGIN:VCALENDAR\r
  BEGIN:VEVENT\r
  UID:event-assignment-11765940\r
  DTSTART;VALUE=DATE;VALUE=DATE:20261013\r
  SUMMARY:Worksheet 2 [TMATH 126 B]\r
  URL;VALUE=URI:https://canvas.uw.edu/calendar?include_contexts=course_192303\r
   9&month=10&year=2026#assignment_11765940\r
  END:VEVENT\r
  BEGIN:VEVENT\r
  UID:event-assignment-42\r
  DTSTART:20261215T185000Z\r
  SUMMARY:Unit 4 - Artifact 4: For Someone Else (Progress\\, Week 1 of 2) [TCS\r
   S 490 A]\r
  URL;VALUE=URI:https://canvas.uw.edu/calendar?include_contexts=course_1935620\r
  END:VEVENT\r
  BEGIN:VEVENT\r
  UID:event-calendar-event-99\r
  DTSTART:20261015T185000Z\r
  SUMMARY:Office hours [TMATH 126 B]\r
  END:VEVENT\r
  END:VCALENDAR\r
  """

  defp item(attrs) do
    Map.merge(
      %{
        "id" => 1,
        "due_at" => "2026-10-14T06:59:59Z",
        "workflow_state" => "unsubmitted",
        "score" => nil
      },
      attrs
    )
  end

  test "feed parsing unfolds lines, unescapes text, and converts all-day dates to 11:59 pm Pacific" do
    assert [worksheet, artifact] = CalendarFeed.parse(@ics)

    assert worksheet == %{
             "id" => 11_765_940,
             "course_id" => "1923039",
             "course" => "TMATH 126 B",
             "name" => "Worksheet 2",
             # PDT (UTC-7) in October
             "due_at" => "2026-10-14T06:59:59Z",
             "html_url" => "https://canvas.uw.edu/courses/1923039/assignments/11765940"
           }

    assert artifact["name"] == "Unit 4 - Artifact 4: For Someone Else (Progress, Week 1 of 2)"
    assert artifact["course"] == "TCSS 490 A"
    assert artifact["due_at"] == "2026-12-15T18:50:00Z"
  end

  test "all-day dates after the DST change use PST" do
    ics = String.replace(@ics, "20261013", "20261201")
    assert [%{"due_at" => "2026-12-02T07:59:59Z"} | _] = CalendarFeed.parse(ics)
  end

  test "normalize flattens the submission and defaults a missing one to unsubmitted" do
    assert %{"workflow_state" => "unsubmitted", "score" => nil} =
             CanvasClient.normalize(%{"id" => 7, "submission" => nil})

    assert %{"workflow_state" => "graded", "score" => 9.0} =
             CanvasClient.normalize(%{
               "id" => 7,
               "submission" => %{"workflow_state" => "graded", "score" => 9.0}
             })
  end

  test "merge marks status unknown when the session cookie is expired" do
    feed_item = %{"id" => 1, "name" => "Quiz 2"}
    sub = %{"workflow_state" => "graded", "score" => 9.0}

    assert %{"workflow_state" => "unknown"} =
             CanvasClient.merge(feed_item, sub, {:auth_expired, 401})

    assert %{"workflow_state" => "graded", "name" => "Quiz 2"} =
             CanvasClient.merge(feed_item, sub, :ok)
  end

  test "filter keeps only incomplete items due within 24 hours" do
    assignments = [
      item(%{"id" => 1}),
      item(%{"id" => 2, "workflow_state" => "graded", "score" => 5.0}),
      item(%{"id" => 3, "due_at" => "2026-10-20T06:59:59Z"}),
      item(%{"id" => 4, "due_at" => "2026-10-12T06:59:59Z"}),
      item(%{"id" => 5, "due_at" => nil}),
      item(%{"id" => 6, "workflow_state" => "submitted"}),
      item(%{"id" => 7, "workflow_state" => "unknown"})
    ]

    assert [%{"id" => 1}, %{"id" => 7}] = Processor.filter_pending_due_soon(assignments, @now)
  end
end
