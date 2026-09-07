defmodule Summarizer.Gemini do
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
  Google's Gemini `generateContent` endpoint.

  Needs `GEMINI_API_KEY`; `GEMINI_MODEL` overrides the model. Included because
  this project summarized with Gemini before moving to a local ollama, so the
  chain can reach back to it without reviving the old code path.
  """

  @behaviour Summarizer

  @endpoint_base "https://generativelanguage.googleapis.com/v1beta/models/"
  @default_model "gemini-2.0-flash"
  @receive_timeout 120_000

  @impl Summarizer
  def name, do: "gemini (#{model()})"

  @impl Summarizer
  def configured?, do: api_key() not in [nil, ""]

  @impl Summarizer
  def complete(prompt) do
    url = "#{@endpoint_base}#{model()}:generateContent?key=#{api_key()}"
    body = %{contents: [%{parts: [%{text: prompt}]}]}

    case Req.post(url, json: body, receive_timeout: @receive_timeout) do
      {:ok, %{status: 200, body: body}} ->
        extract_text(body)

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp extract_text(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]}) do
    text =
      parts
      |> Enum.map_join("", &Map.get(&1, "text", ""))
      |> String.trim()

    case text do
      "" -> {:error, :no_text_in_response}
      text -> {:ok, text}
    end
  end

  defp extract_text(body), do: {:error, "unexpected response: #{inspect(body)}"}

  defp api_key, do: System.get_env("GEMINI_API_KEY")
  defp model, do: System.get_env("GEMINI_MODEL") || @default_model
end
