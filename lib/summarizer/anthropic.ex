defmodule Summarizer.Anthropic do
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
  Anthropic's Messages API - the hosted option for hosts that cannot run a
  local model.

  Needs `ANTHROPIC_API_KEY`; without it `configured?/0` is false and the chain
  moves on without a request. `ANTHROPIC_MODEL` overrides the model.

  Two details worth knowing:

  * Effort is set to `low` rather than turning thinking off. Thinking is on by
    default on this model family, and disabling it is the discouraged route -
    lowering effort is the supported way to keep a simple task cheap.
  * News copy can trip the safety classifiers. A refusal is not an HTTP error:
    it arrives as a 200 with `stop_reason` of `refusal`, so that case is checked
    explicitly and turned into an error, which lets the chain (and ultimately
    the trim path) take over. Server-side fallbacks are enabled as well, so a
    refusal is usually re-routed before it ever reaches us.
  """

  @behaviour Summarizer

  @endpoint "https://api.anthropic.com/v1/messages"
  @api_version "2023-06-01"
  @fallback_beta "server-side-fallback-2026-07-01"
  @default_model "claude-opus-5"

  # Thinking tokens count against this, and NewsEditor asks for a whole page
  # plan rather than one summary, so leave real headroom. Unused capacity costs
  # nothing.
  @max_tokens 16_000
  @receive_timeout 120_000

  @system_prompt "You are a copy editor preparing wire stories for a news page. " <>
                   "Reply with the summary text only - no preamble, no quotation marks around it, " <>
                   "no commentary about what you did."

  @impl Summarizer
  def name, do: "anthropic (#{model()})"

  @impl Summarizer
  def configured?, do: api_key() not in [nil, ""]

  @impl Summarizer
  def complete(prompt) do
    body = %{
      model: model(),
      max_tokens: @max_tokens,
      system: @system_prompt,
      output_config: %{effort: "low"},
      fallbacks: "default",
      messages: [%{role: "user", content: prompt}]
    }

    # Over plain HTTP the beta opt-in is a header; only the SDKs take it as a
    # `betas` body field.
    headers = [
      {"x-api-key", api_key()},
      {"anthropic-version", @api_version},
      {"anthropic-beta", @fallback_beta}
    ]

    case Req.post(@endpoint, json: body, headers: headers, receive_timeout: @receive_timeout) do
      {:ok, %{status: 200, body: %{"stop_reason" => "refusal"} = body}} ->
        {:error, "refused: #{inspect(Map.get(body, "stop_details"))}"}

      {:ok, %{status: 200, body: %{"content" => content}}} ->
        extract_text(content)

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Content is a list of blocks; thinking blocks ride along with the text ones,
  # so take only the text.
  defp extract_text(content) when is_list(content) do
    text =
      content
      |> Enum.filter(&(Map.get(&1, "type") == "text"))
      |> Enum.map_join("", &Map.get(&1, "text", ""))
      |> String.trim()

    case text do
      "" -> {:error, :no_text_in_response}
      text -> {:ok, text}
    end
  end

  defp extract_text(other), do: {:error, "unexpected content: #{inspect(other)}"}

  defp api_key, do: System.get_env("ANTHROPIC_API_KEY")
  defp model, do: System.get_env("ANTHROPIC_MODEL") || @default_model
end
