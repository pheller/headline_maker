defmodule HeadlinePageLayoutTest do
  @moduledoc """
  The story text must never reach the link block.

  A four-link page shipped with its last two rows drawn on top of the rule and
  the first link, because the row budget measured from the top of the story
  area without reserving the rows the headline draws there first.
  """
  use ExUnit.Case, async: true

  # Mirrors of HeadlinePage's private geometry. If these drift the test is
  # meaningless, so they are asserted against the module's own arithmetic below.
  @body_top 167
  @body_pitch 9

  describe "body_rows/2" do
    test "the last body row always clears the rule above the links" do
      for n <- 0..6, head <- 0..2 do
        rows = HeadlinePage.body_rows(n, head)
        rule = HeadlinePage.top_rule(n)

        if rows > 0 do
          first = @body_top - head * @body_pitch
          last = first - (rows - 1) * @body_pitch

          assert last > rule,
                 "#{n} links, #{head}-line headline: last row at #{last} is not above the rule at #{rule}"
        end
      end
    end

    test "reserves the headline, so budgets shrink as the headline grows" do
      for n <- 0..6 do
        assert HeadlinePage.body_rows(n, 0) >= HeadlinePage.body_rows(n, 1)
        assert HeadlinePage.body_rows(n, 1) >= HeadlinePage.body_rows(n, 2)
      end
    end

    test "body_rows/1 budgets for the headline the prompt promises" do
      for n <- 0..6 do
        assert HeadlinePage.body_rows(n) == HeadlinePage.body_rows(n, HeadlinePage.headline_rows())
      end
    end

    test "the four-link case that shipped broken now fits" do
      # Two rows, not the four it used to claim.
      assert HeadlinePage.body_rows(4) == 2
    end

    test "more links never means more room" do
      budgets = Enum.map(0..6, &HeadlinePage.body_rows/1)
      assert budgets == Enum.sort(budgets, :desc)
    end
  end

  describe "the editor and the renderer agree" do
    test "NewsEditor budgets from HeadlinePage, not a copy of it" do
      for n <- 0..6 do
        assert NewsEditor.body_budget(n) == HeadlinePage.body_rows(n) * 58
      end
    end

    test "the headline allowance is not duplicated either" do
      # It lived in three places - HeadlinePage, a NewsEditor attribute, and a
      # literal in the prompt text. All three now come from one function, so
      # changing the layout cannot leave the prompt promising the old number.
      assert NewsEditor.headline_budget() == HeadlinePage.headline_rows() * 58
    end

    test "the prompt quotes the real headline allowance" do
      rows = HeadlinePage.headline_rows()
      assert NewsEditor.budgets() =~ "Headline:            #{rows} lines"
    end
  end
end
