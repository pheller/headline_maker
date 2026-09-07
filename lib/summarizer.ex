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

  @doc """
  Summarize `text` to close to `max_length` characters.

  Walks the configured chain and returns the first success. Returns
  `{:error, :no_provider}` when every provider is unconfigured or fails.
  """
  @spec summarize(String.t(), pos_integer()) :: {:ok, String.t()} | {:error, term()}
  def summarize(text, max_length) when is_binary(text) do
    prompt = prompt_for(text, max_length)

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
              Logger.info(
                "Summarized with #{provider.name()}: requested #{max_length}, " <>
                  "original #{String.length(text)}, result #{String.length(response)}"
              )

              {:halt, {:ok, response}}

            {:error, reason} ->
              Logger.warning("Summarizer #{provider.name()} failed: #{inspect(reason)}")
              {:cont, {:error, reason}}
          end
      end
    end)
  end

  @doc """
  The summarization prompt, shared by every provider.

  Kept verbatim from the original single-provider implementation so that
  swapping providers changes the model, not the instruction.
  """
  @spec prompt_for(String.t(), pos_integer()) :: String.t()
  def prompt_for(text, max_length) do
    escaped_text = String.replace(text, "\"", "\\\"")

    "Summarize the text #{escaped_text} close to a maximum of #{max_length} characters, " <>
      "keeping as much of the original meaning as possible. " <>
      "Do not add ellipses or other indicators of truncation."
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
end
