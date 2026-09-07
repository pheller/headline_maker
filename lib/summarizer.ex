defmodule Summarizer do
  # Copyright 2026, Ralph Richard Cook
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

  @moduledoc """
  Pluggable text summarization, in the same shape as `NewsFeeds`: a behaviour
  with swappable implementations chosen at the command line.

  A local ollama is ideal when the host can run one, but an 8B model needs
  around 6 GB resident and some deployment targets cannot spare it. So the
  provider is a chain, tried in order:

      --summarizer ollama,anthropic    local first, hosted API if it is not there
      --summarizer anthropic           hosted API only
      --summarizer none                no LLM at all

  The default is `ollama` alone, which is exactly the behavior before this
  module existed.

  The chain is explicit on purpose - probing for a local ollama and silently
  falling back would mean an unattended daily run produces different prose
  depending on what happened to be reachable, with nothing in the output saying
  which path ran. Every summary logs the provider that produced it.

  When no provider in the chain succeeds, `summarize/2` returns
  `{:error, :no_provider}`. `HeadlineWriter.choose_summary/3` already handles an
  error by trimming the original text, so an exhausted chain degrades to
  truncation rather than failing the run.

  This module owns the prompt so that every provider sends an identical
  instruction and their outputs stay comparable; implementations only carry it
  to a model and hand back text.
  """

  require Logger

  @typedoc "A provider module implementing this behaviour."
  @type provider :: module()

  @doc "Human-readable provider name, used in logs."
  @callback name() :: String.t()

  @doc """
  Whether this provider has what it needs to run - an API key in the
  environment, say. A provider that is not configured is skipped without an
  attempt, so an unset key costs no network round trip.
  """
  @callback configured?() :: boolean()

  @doc "Send one prompt, return the completion text."
  @callback complete(prompt :: String.t()) :: {:ok, String.t()} | {:error, term()}

  @providers %{
    "ollama" => Summarizer.Ollama,
    "anthropic" => Summarizer.Anthropic,
    "claude" => Summarizer.Anthropic,
    "gemini" => Summarizer.Gemini,
    "none" => Summarizer.None
  }

  @default_chain "ollama"

  @typedoc "Which kind of text is being shortened - they want different prose."
  @type kind :: :body | :headline

  @doc """
  Shorten `text` to fit `max_length` characters.

  Walks the configured chain and returns the first success. Returns
  `{:error, :no_provider}` when every provider is unconfigured or fails.

  Output is run through `to_ascii/1`: feed text is normalized on the way in,
  but a model's output never was, and this ends up in a NAPLPS renderer that
  wants plain ASCII.
  """
  @spec summarize(String.t(), pos_integer(), kind()) :: {:ok, String.t()} | {:error, term()}
  def summarize(text, max_length, kind \\ :body) when is_binary(text) do
    prompt = prompt_for(text, max_length, kind)

    chain()
    |> Enum.reduce_while({:error, :no_provider}, fn provider, _acc ->
      cond do
        not function_exported?(provider, :complete, 1) ->
          Logger.warning("Summarizer #{inspect(provider)} is not loaded; skipping")
          {:cont, {:error, :no_provider}}

        not provider.configured?() ->
          Logger.info("Summarizer #{provider.name()} is not configured; skipping")
          {:cont, {:error, :no_provider}}

        true ->
          case provider.complete(prompt) do
            {:ok, response} ->
              clean = to_ascii(response)

              Logger.info(
                "Summarized with #{provider.name()}: requested #{max_length}, " <>
                  "original #{String.length(text)}, result #{String.length(clean)}"
              )

              {:halt, {:ok, clean}}

            {:error, reason} ->
              Logger.warning("Summarizer #{provider.name()} failed: #{inspect(reason)}")
              {:cont, {:error, reason}}
          end
      end
    end)
  end

  @doc """
  The prompt for one piece of text, shared by every provider so that swapping
  providers changes the model and not the instruction.

  Two things the wording has to get right, both learned the hard way:

  * The limit is stated as hard, and the target set below `max_length`. Asking
    for something "close to" a maximum reliably lands just over it, and
    `HeadlineWriter.choose_summary/3` then has to trim what came back.
  * The real work on a wire feed is not compression. Story text arrives with
    photo captions, agency credits, datelines, network boilerplate, duplicated
    sentences, and the lede several paragraphs down. Asking only for a summary
    does not ask for any of that to be fixed.
  """
  @spec prompt_for(String.t(), pos_integer(), kind()) :: String.t()
  def prompt_for(text, max_length, kind \\ :body) do
    instructions(kind, target_length(max_length)) <> "\n\n" <> text
  end

  # Aim under the cap so ordinary overshoot still lands inside it.
  @headroom 0.93

  @doc "The length actually asked for, kept below the caller's hard cap."
  @spec target_length(pos_integer()) :: pos_integer()
  def target_length(max_length), do: max(1, trunc(max_length * @headroom))

  defp instructions(:body, target) do
    """
    Rewrite the news story below as a single self-contained news brief of AT \
    MOST #{target} characters. That is a hard limit - do not exceed it.

    Lead with what happened. Drop photo captions, agency credits, datelines, \
    timestamps, network boilerplate, and anything said twice. Keep the facts, \
    names and numbers that matter. Write complete sentences in plain newspaper \
    style.

    Use ASCII characters only: straight quotes and apostrophes, a hyphen for \
    any dash, and no ellipsis character. Reply with the brief itself only - no \
    preamble, no quotation marks around it, no note about what you did.
    """
  end

  defp instructions(:headline, target) do
    """
    Rewrite the news headline below in AT MOST #{target} characters. That is a \
    hard limit - do not exceed it.

    Keep the specific subject - who or what it is about - and cut everything \
    that is not needed to understand the story at a glance. Plain newspaper \
    style, no trailing punctuation.

    Use ASCII characters only: straight quotes and apostrophes, a hyphen for \
    any dash, and no ellipsis character. Reply with the headline itself only - \
    no preamble, no quotation marks around it, no note about what you did.
    """
  end

  @doc """
  The provider chain, as a list of modules.

  Read from `:headline_maker, :summarizer` (set from the command line), then
  the `SUMMARIZER` environment variable, then the default. Unknown names are
  logged and dropped rather than raising - a typo in a cron line should not take
  down the run, it should fall through to the trim path.
  """
  @spec chain() :: [provider()]
  def chain do
    setting =
      Application.get_env(:headline_maker, :summarizer) ||
        System.get_env("SUMMARIZER") ||
        @default_chain

    setting
    |> String.split(",", trim: true)
    |> Enum.map(&(&1 |> String.trim() |> String.downcase()))
    |> Enum.flat_map(fn name ->
      case Map.fetch(@providers, name) do
        {:ok, provider} ->
          [provider]

        :error ->
          Logger.error("Unknown summarizer #{inspect(name)}; known: #{known_providers()}")
          []
      end
    end)
  end

  @doc "Comma-separated list of the names accepted by `--summarizer`."
  @spec known_providers() :: String.t()
  def known_providers, do: @providers |> Map.keys() |> Enum.sort() |> Enum.join(", ")

  # Model output normalized for a renderer that wants plain ASCII. This is
  # deliberately separate from `NewsFeeds.replace_utf_chars/1` and adds the two
  # dashes that map leaves alone: `MemeorandumFeed` splits incoming stories on
  # the em-dash, so rewriting it at ingestion would break that parse. Here we
  # are past all parsing, so the dashes are safe to fold.
  #
  # Written as byte literals to keep this source ASCII.
  @ascii_replacements %{
    # left/right single quote
    <<0xE2, 0x80, 0x98>> => "'",
    <<0xE2, 0x80, 0x99>> => "'",
    # left/right double quote
    <<0xE2, 0x80, 0x9C>> => "\"",
    <<0xE2, 0x80, 0x9D>> => "\"",
    # ellipsis
    <<0xE2, 0x80, 0xA6>> => "...",
    # non-breaking space
    <<0xC2, 0xA0>> => " ",
    # em dash, en dash
    <<0xE2, 0x80, 0x94>> => "-",
    <<0xE2, 0x80, 0x93>> => "-"
  }

  @ascii_keys Map.keys(@ascii_replacements)

  @doc """
  Fold the punctuation a model is likely to emit down to ASCII.

  Anything still non-ASCII after the substitutions is dropped, so nothing
  multi-byte reaches the NAPLPS encoder.
  """
  @spec to_ascii(String.t()) :: String.t()
  def to_ascii(text) do
    text
    |> String.replace(@ascii_keys, fn pat -> @ascii_replacements[pat] end)
    |> String.replace(~r/[^\x00-\x7F]/u, "")
  end
end
