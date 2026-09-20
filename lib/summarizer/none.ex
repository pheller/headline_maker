defmodule Summarizer.None do
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
  No summarization at all.

  Declines every prompt, so every caller takes its error branch: feed copy
  reaches the page as written, untouched by a model. Useful for seeing how the
  raw copy reads, or on a host with neither a local model nor an API key.

  Note that `NewsEditor.plan/2` cannot degrade - it has no non-model way to
  rank and cut a page - so a run whose chain is only `none` will not produce a
  page.
  """

  @behaviour Summarizer

  @impl Summarizer
  def name, do: "none"

  @impl Summarizer
  def configured?, do: true

  @impl Summarizer
  def complete(_prompt), do: {:error, :summarization_disabled}
end
