defmodule HighlightsBodyTest do
  use ExUnit.Case, async: true

  @original File.read!("priv/tlota000b.obj")

  # The original's own six option texts. Feeding these back through the
  # generator must reproduce the recovered object byte for byte - that is what
  # makes patching it safe.
  @orig_slot1 ["Hostage Execution", "Delayed", "Indefinitely"]
  @orig_slot2 ["New Columnist:", "Terry Atkinson on", "Compact Discs"]
  @orig_slot4 "Order Disposable Cameras From Fuji"
  @orig_slot5 "Get 1000 Bonus Points from Sheraton"
  @orig_slot6 "North to Alaska and South to Atlanta"

  describe "round trip" do
    test "rebuilding with the original text reproduces the original object" do
      rebuilt =
        HighlightsBody.patch(@orig_slot1,
          slot2: @orig_slot2,
          slot4: @orig_slot4,
          slot5: @orig_slot5,
          slot6: @orig_slot6,
          retarget: []
        )

      assert rebuilt == @original
    end
  end

  describe "retargeting" do
    test "moves only the two destinations that change" do
      obj = HighlightsBody.patch(["a", "b", "c"])

      # Option 1 still reaches HEADLINE NEWS.
      assert String.contains?(obj, "NH000000PG ")
      # Options 2 and 3 are retargeted.
      assert String.contains?(obj, "ZZAB0000PG ")
      assert String.contains?(obj, "ZZPR0000P  ")
      refute String.contains?(obj, "5C000000PG ")
      refute String.contains?(obj, "FN000000PG ")
      # The six untouched destinations survive.
      for name <- ~w(SJ000000PG AT000000PG ID000000PG XS000000PG IHB00000PG IHC00000PG) do
        assert String.contains?(obj, name)
      end
    end

    test "retargeting cannot change the object length" do
      a = HighlightsBody.patch(["a", "b", "c"], retarget: [])
      b = HighlightsBody.patch(["a", "b", "c"])
      assert byte_size(a) == byte_size(b)
    end
  end

  describe "slot 1" do
    test "uses the model's highlight_title when it fits" do
      story = %{highlight_title: "Hostage\nExecution\nDelayed", headline: "ignored"}
      assert HighlightsBody.slot1_lines(story) == ["Hostage", "Execution", "Delayed"]
    end

    test "falls back to the headline when a line is too wide" do
      story = %{
        highlight_title: "This one line is very much too wide",
        headline: "Exxon Pulls Cleanup Crew"
      }

      lines = HighlightsBody.slot1_lines(story)
      assert lines == ["Exxon Pulls", "Cleanup Crew"]
    end

    test "falls back when there are too many lines" do
      story = %{highlight_title: "a\nb\nc\nd", headline: "Short One"}
      assert HighlightsBody.slot1_lines(story) == ["Short One"]
    end

    test "falls back when the title is missing" do
      assert HighlightsBody.slot1_lines(%{headline: "Fed Holds Rates"}) == ["Fed Holds Rates"]
    end
  end

  describe "wrap/1" do
    test "breaks on word boundaries at 17 columns" do
      # Greedy: "Hostage Execution" is exactly 17, which is the break the
      # original itself made.
      assert HighlightsBody.wrap("Hostage Execution Delayed Indefinitely") ==
               ["Hostage Execution", "Delayed", "Indefinitely"]
    end

    test "never exceeds three lines" do
      lines = HighlightsBody.wrap(String.duplicate("word ", 40))
      assert length(lines) == 3
    end

    test "never exceeds seventeen columns" do
      lines = HighlightsBody.wrap("Antidisestablishmentarianism rules today")
      assert Enum.all?(lines, &(String.length(&1) <= 17))
    end
  end

  describe "the object stays well formed" do
    test "segment lengths still walk to the end" do
      obj = HighlightsBody.patch(["Fed Holds Rates", "Steady Through", "Year End"])
      <<_name::binary-11, _seq, _type, total::16-little, _cv::binary-3, body::binary>> = obj

      assert total == byte_size(obj)

      types = walk(body, [])
      # presentation, nine fields, custom text, and the two program calls
      assert types == [0x51] ++ List.duplicate(0x04, 9) ++ [0x0A, 0x01, 0x01]
    end
  end

  defp walk(<<>>, acc), do: Enum.reverse(acc)

  defp walk(<<type, len::16-little, _rest::binary>> = bin, acc) do
    <<_::binary-size(len), tail::binary>> = bin
    walk(tail, [type | acc])
  end
end
