# Headline Maker 

Headline Maker is a command-line program to collect news stories and prepare them for publishing in the Prodigy Service client application.
It uses news stories to make a headline and story, then creates Prodigy object files that is put in the Prodigy Reloaded database to be served by the Prodigy Reloaded server.

Different news services are picked with "pluggable" built-in news gathering libraries. 

## Usage

```sh
headline_maker [options]
```

## Options

| Option                | Alias | Type    | Description                                                                                  |
|-----------------------|-------|---------|----------------------------------------------------------------------------------------------|
| `--input`             | `-i`  | string  | Input file or URL for the news feed. Default: `https://memeorandum.com/feed.xml`             |
| `--output`            | `-o`  | string  | Output file name. Default: `NH00A000.BDY`                                                    |
| `--directory`         | `-d`  | string  | Output directory. Default: `.`                                                               |
| `--attribution`       | `-a`  | string  | Adds the attribution string to the end of a story's headline.                                |
| `--help`              | `-h`  | boolean | Show help message and exit.                                                                  |
| `--feedstyle`         | `-f`  | string  | Feed style module name (without `Elixir.` prefix). Default: `MemeorandumFeed`                |
| `--retroguide`        | `-r`  | string  | Telnet guide string for RetroCampusFeed feed style. Default: `511-1234`                      |
| `--debugoutput`       |       | string  | Debug output file (no alias).                                                                |
| `--debuginput`        |       | string  | Debug input file (no alias). If specified, overrides feedstyle with `DebugFeed`.             |
| `--summarizer`        | `-s`  | string  | Summarizer chain, comma separated, tried in order. Default: `ollama`                         |

## Example

```sh
./headline_maker -i https://memeorandum.com/feed.xml -d /tmp/headlines -o NH00A000.BDY
```

## Help

To display the help message, use:

```sh
headline_maker --help
```

## Notes

- All options except `--help` have sensible defaults.
- Debug options do not have short aliases.
- If `--debuginput` is specified, the feed style is overridden to use `DebugFeed`, which just reads in the files from the debuginput directory.

## Summarization

Story text is summarized to fit the page. The summarizer is pluggable, in the
same way feeds are, and is given as a chain tried in order:

| Name | Needs | Notes |
|------|-------|-------|
| `ollama` | a reachable ollama server | Default. `OLLAMA_HOST`, `OLLAMA_MODEL` |
| `anthropic` (alias `claude`) | `ANTHROPIC_API_KEY` | `ANTHROPIC_MODEL` |
| `gemini` | `GEMINI_API_KEY` | `GEMINI_MODEL` |
| `none` | nothing | No LLM; text is trimmed to length instead |

```sh
# local model, falling back to the API on a host that cannot run one
headline_maker -s ollama,anthropic

# no model at all - stories are trimmed to length
headline_maker -s none
```

The chain can also be set with the `SUMMARIZER` environment variable; the
command line wins. Each summary logs which provider produced it, so an
unattended run can be traced after the fact. If every provider in the chain is
unconfigured or fails, the story text is trimmed to length rather than the run
failing.
