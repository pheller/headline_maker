defmodule Summarizer.Ollama do
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
  A local ollama server, the original (and default) summarizer.

  Host comes from `OLLAMA_HOST`, model from `OLLAMA_MODEL`; both keep the
  values that were hardcoded before this became pluggable.

  `configured?/0` is always true: ollama needs no credential, and probing the
  host here would just duplicate the request `complete/1` is about to make. An
  unreachable server surfaces as a connection error, which moves the chain on
  to the next provider.
  """

  @behaviour Summarizer

  @default_host "http://localhost:11434"
  @default_model "llama3.1:8b"
  @generate_path "/api/generate"

  # An 8B model on CPU is slow; the original allowed two minutes per call.
  @receive_timeout 120_000

  @impl Summarizer
  def name, do: "ollama (#{model()})"

  @impl Summarizer
  def configured?, do: true

  @impl Summarizer
  def complete(prompt) do
    body = %{model: model(), prompt: prompt, stream: false}
    url = host() <> @generate_path

    case Req.post(url, json: body, receive_timeout: @receive_timeout) do
      {:ok, %{status: 200, body: %{"response" => response}}} ->
        {:ok, response}

      {:ok, %{status: status, body: body}} ->
        {:error, "HTTP #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp host, do: System.get_env("OLLAMA_HOST") || @default_host
  defp model, do: System.get_env("OLLAMA_MODEL") || @default_model
end
