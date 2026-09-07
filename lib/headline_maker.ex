defmodule HeadlineMaker do
  # Copyright 2025, Ralph Richard Cook
  #
  # This file is part of Prodigy Reloaded.
  #
  # Prodigy Reloaded is free software: you can redistribute it and/or modify it under the terms of the GNU Affero General
  # Public License as published by the Free Software Foundation, either version 3 of the License, or (at your
  # option) any later version.
  #
  # Prodigy Reloaded is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
  # the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  # GNU Affero General Public License for more details.
  #
  # You should have received a copy of the GNU Affero General Public License along with Prodigy Reloaded. If not,
  # see <https://www.gnu.org/licenses/>.

  def main(argv) do
    {opts, _args, _invalid} =
      OptionParser.parse(argv,
        switches: [
          input: :string,
          output: :string,
          directory: :string,
          help: :boolean,
          feedstyle: :string,
          retroguide: :string,
          debugoutput: :string,
          debuginput: :string,
          attribution: :string,
          summarizer: :string
        ],
        # Deliberatly not using shortcuts for debug options
        aliases: [i: :input, o: :output, d: :directory, h: :help, f: :feedstyle, r: :retroguide, a: :attribution, s: :summarizer]
      )

    cond do
      opts[:help] ->
        print_help()

      # opts[:input] && opts[:output] ->
      true ->
        input = opts[:input] || "https://memeorandum.com/feed.xml"
        output = opts[:output] || "NH00A000.BDY"
        directory = opts[:directory] || "."
        retroguide = opts[:retroguide] || "511-1234"
        debugoutput = opts[:debugoutput]
        debuginput = opts[:debuginput]
        attribution = opts[:attribution]

        # Command line beats SUMMARIZER beats the default; setting it here
        # keeps Summarizer's own lookup order intact when the flag is absent.
        if opts[:summarizer] do
          Application.put_env(:headline_maker, :summarizer, opts[:summarizer])
        end

        feedstyle =
          case opts[:feedstyle] do
            nil -> :"Elixir.MemeorandumFeed"
            style -> String.to_atom("Elixir." <> style)
          end

        # Override feedstyle if debuginput is specified
        feedstyle = if debuginput != nil, do: DebugFeed, else: feedstyle

        options = %{
          input: input,
          output: output,
          directory: directory,
          feedstyle: feedstyle,
          retroguide: retroguide,
          debugoutput: debugoutput,
          debuginput: debuginput,
          attribution: attribution
        }

        IO.puts(
          "Input file: #{input}, Output files: #{output}, Directory: #{directory}, Feed Style: #{feedstyle}"
        )

        IO.puts("Summarizer chain: #{Enum.map_join(Summarizer.chain(), ", ", & &1.name())}")

        HeadlineWriter.write_headlines(options)

   end
  end

  defp print_help do
    IO.puts("""
    Usage: headline_maker [options]

    Options:
      -i, --input       Input file
      -o, --output      Output file
      -d, --directory   Output directory
      -f, --feedstyle   Feed style module name
      -r, --retroguide  Telnet guide string for RetroCampusFeed
      -a, --attribution Attribution appended to each headline
      -s, --summarizer  Summarizer chain, comma separated, tried in order
      -h, --help        Show this help message
    """)
  end
end
