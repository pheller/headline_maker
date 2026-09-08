defmodule Mix.Tasks.Highlights.Build do
  @shortdoc "Build TLOTA000B offline, without running the news batch"

  @moduledoc """
  Write the HIGHLIGHTS body as a standalone object.

  The daily run emits this alongside the headline objects, so the normal way to
  change the landing page is to change `HighlightsBody` and let the batch ship
  it. This task exists for the case where the batch has already run for the day
  and you want a corrected object to upload by hand - a wording fix or a
  retarget - without regenerating the headline tree underneath it.

  ## Slot 1 must match what is already live

  Option 1 announces the lead story. If you rebuild without saying what that
  story is, you will publish a landing page that disagrees with the headline
  chain until the next batch. So slot 1 is REQUIRED - there is no default.

  Read the three lines off the live page and pass them:

      mix highlights.build \\
        --line "Senate Confirms" --line "New Fed Chair" --line "After Delay"

  Or pass the headline and let it wrap to the 17x3 box the way the generator
  would:

      mix highlights.build --headline "Senate Confirms New Fed Chair"

  ## Options

    * `--line`     one line of slot 1; repeat up to three times
    * `--headline` a headline to wrap into slot 1, instead of `--line`
    * `--out`      output path (default: the object's own filename here)
  """
  use Mix.Task

  @impl Mix.Task
  def run(argv) do
    {opts, _, _} =
      OptionParser.parse(argv,
        strict: [line: :keep, headline: :string, out: :string]
      )

    lines = for {:line, l} <- opts, do: l
    headline = opts[:headline]

    slot1 =
      cond do
        lines != [] and headline != nil ->
          Mix.raise("Pass --line or --headline, not both")

        lines != [] ->
          lines

        headline != nil ->
          HighlightsBody.wrap(headline)

        true ->
          Mix.raise("""
          Slot 1 is required: it announces the lead story, and rebuilding
          without it would publish a landing page that disagrees with the
          headline chain already on the server.

              mix highlights.build --line "..." --line "..." --line "..."
              mix highlights.build --headline "..."
          """)
      end

    {name, bytes} = HighlightsBody.build(%{highlight_title: Enum.join(slot1, "\n")})
    path = opts[:out] || name
    File.write!(path, bytes)

    Mix.shell().info("""
    Wrote #{path} (#{byte_size(bytes)} bytes)

    Slot 1:
    #{Enum.map_join(slot1, "\n", &"      #{&1}")}

    Upload it with podb_upload.py; the server assigns the object version.
    """)
  end
end
