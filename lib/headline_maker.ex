defmodule HeadlineMaker do
  require Logger

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
          summarizer: :string,
          stories: :integer
        ],
        # Deliberatly not using shortcuts for debug options
        aliases: [
          i: :input,
          o: :output,
          d: :directory,
          h: :help,
          f: :feedstyle,
          r: :retroguide,
          a: :attribution,
          s: :summarizer
        ]
      )

    cond do
      opts[:help] ->
        print_help()

      # opts[:input] && opts[:output] ->
      true ->
        input = opts[:input] || "https://memeorandum.com/feed.xml"
        output = opts[:output] || "NH00A000.BDY"
        stories = opts[:stories] || 10
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
          attribution: attribution,
          stories: stories
        }

        IO.puts(
          "Input file: #{input}, Output files: #{output}, Directory: #{directory}, Feed Style: #{feedstyle}"
        )

        IO.puts("Summarizer chain: #{Enum.map_join(Summarizer.chain(), ", ", & &1.name())}")

        run(options)
    end
  end

  # Fetch the wire copy, put a day's HEADLINE NEWS together, and write every
  # object it takes. Returns non-zero on failure so the caller uploads nothing:
  # yesterday's headlines are better than a broken tree.
  defp run(options) do
    articles = options[:feedstyle].get_stories(options, options[:stories])

    cond do
      articles == [] ->
        Logger.error("No articles from #{options[:input]}; nothing written")
        exit({:shutdown, 1})

      true ->
        case NewsEditor.plan(articles) do
          {:ok, stories} ->
            write_objects(stories, options)

          {:error, reason} ->
            Logger.error("Could not plan today's headlines: #{inspect(reason)}")
            exit({:shutdown, 1})
        end
    end
  end

  defp write_objects(stories, options) do
    dir = options[:directory]
    File.mkdir_p!(dir)

    objects = HeadlineObjects.build(stories)

    for {name, bytes} <- objects do
      path = Path.join(dir, name)
      File.write!(path, bytes)
      Logger.info("Wrote #{path}, #{byte_size(bytes)} bytes")
    end

    if options[:debugoutput], do: write_debug(stories, options[:debugoutput])

    subs = Enum.sum(Enum.map(stories, &length(&1.substories)))
    IO.puts("#{length(objects)} objects: #{length(stories)} stories, #{subs} subordinate pages")
  end

  # The copy as text, for reading without a renderer.
  defp write_debug(stories, dir) do
    File.mkdir_p!(dir)

    for {s, i} <- Enum.with_index(stories, 1) do
      subs = Enum.map_join(s.substories, "\n", fn sub -> "- #{sub.label}\n#{sub.body}" end)

      File.write!(
        Path.join(dir, "hmdebug_#{i}"),
        "#{s.headline}#{HeadlineWriter.debug_delimiter()}#{s.body}\n\n#{subs}"
      )
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
