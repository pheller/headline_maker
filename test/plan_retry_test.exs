defmodule PlanRetryTest do
  @moduledoc """
  A day's headlines must not hinge on one reply parsing.

  The run uploads nothing when the editorial pass fails, by design - yesterday's
  tree beats a broken one. That makes a single unusable reply expensive: on
  2026-09-12 the editor answered with something carrying no JSON at all, the
  reply was discarded unlogged, and the service served the previous day's news.
  """
  use ExUnit.Case, async: true

  @articles [["Some headline", "Some body text."]]
  @good ~s({"stories":[{"headline":"H","short_title":"S","body":"B","substories":[]}]})
  @refusal "I'm sorry, I can't help with that."

  # Replies handed out in order, so a test can say "fail once, then succeed".
  defp scripted(replies) do
    {:ok, agent} = Agent.start_link(fn -> replies end)

    fn _prompt ->
      Agent.get_and_update(agent, fn
        [last] -> {{:ok, last}, [last]}
        [next | rest] -> {{:ok, next}, rest}
      end)
    end
  end

  test "a reply with no JSON is asked again rather than losing the day" do
    assert {:ok, [story]} =
             NewsEditor.plan(@articles, tries: 2, complete: scripted([@refusal, @good]))

    assert story.headline == "H"
  end

  test "the retry is bounded - one try means one request" do
    assert {:error, :no_json_found} =
             NewsEditor.plan(@articles, tries: 1, complete: scripted([@refusal, @good]))
  end

  test "gives up and reports the parse error when every try fails" do
    assert {:error, :no_json_found} =
             NewsEditor.plan(@articles, tries: 2, complete: scripted([@refusal]))
  end

  test "a transport failure is retried too" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    complete = fn _ ->
      case Agent.get_and_update(agent, &{&1, &1 + 1}) do
        0 -> {:error, :timeout}
        _ -> {:ok, @good}
      end
    end

    assert {:ok, [_]} = NewsEditor.plan(@articles, tries: 2, complete: complete)
  end
end
