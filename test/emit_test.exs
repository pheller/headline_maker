defmodule EmitTest do
  @moduledoc """
  The whole emit step, driven from a synthetic plan.

  No feed and no model: `write_objects/2` is the seam where a day's stories
  become the set of files the uploader ships, and this asserts that set is
  what `bin/run-generator` expects to find.
  """
  use ExUnit.Case, async: true

  defp story(headline, opts \\ []) do
    %{
      headline: headline,
      short_title: Keyword.get(opts, :short_title, headline),
      highlight_title: Keyword.get(opts, :highlight_title, ""),
      body: "Body copy for #{headline}.",
      substories: Keyword.get(opts, :substories, [])
    }
  end

  defp emit(stories) do
    dir = Path.join(System.tmp_dir!(), "emit_test_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf(dir) end)
    HeadlineMaker.write_objects(stories, %{directory: dir, debugoutput: nil})
    {dir, File.ls!(dir)}
  end

  test "the landing page ships in the same set as the headline chain" do
    stories = [
      story("Senate Confirms New Fed Chair", highlight_title: "Senate Confirms\nNew Fed Chair"),
      story("Storm Closes Gulf Ports"),
      story("Talks Resume In Vienna")
    ]

    {dir, files} = emit(stories)

    assert "TLOTA000.B_1_8_1" in files
    assert Enum.any?(files, &String.starts_with?(&1, "NH00A000.B"))

    # Every file the generator writes must be collected by run-generator's
    # `find ... -name '*_8_1'` sweep, or it silently never uploads.
    assert Enum.all?(files, &String.ends_with?(&1, "_8_1")),
           "not collectable: #{inspect(Enum.reject(files, &String.ends_with?(&1, "_8_1")))}"

    # And the landing page must carry the lead story, not some other one.
    body = File.read!(Path.join(dir, "TLOTA000.B_1_8_1"))
    assert String.contains?(body, "Senate Confirms")
    assert String.contains?(body, "New Fed Chair")
  end

  test "a lead story with no highlight_title still produces a landing page" do
    {dir, files} = emit([story("Fed Holds Rates Steady Through Year End")])

    assert "TLOTA000.B_1_8_1" in files
    body = File.read!(Path.join(dir, "TLOTA000.B_1_8_1"))
    # Wrapped from the headline at 17 columns.
    assert String.contains?(body, "Fed Holds Rates")
  end

  test "the landing page always links to HEADLINE NEWS" do
    {dir, _} = emit([story("Anything At All")])
    body = File.read!(Path.join(dir, "TLOTA000.B_1_8_1"))
    assert String.contains?(body, "NH000000PG ")
  end
end
