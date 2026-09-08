defmodule HeadlineObjects do
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
  Turns a day's plan into the Page Element Objects the service serves.

  The top stories are one element set - sequence 1..N of set size N - so
  NEXT and BACK walk them. A story that carries subordinate coverage gets a
  set of its own, and a standard menu binding each numbered field to one of
  those bodies.

  ## How a subordinate link reaches its page

  Recovered objects (`NH00CF4JB` / `NH00CF4KB`) show the shape: the action
  navigates to the SHARED page template and passes the body to display as a
  destination parameter. One template serves every screen, told each time
  which element to show, so no page template is generated here.

  ## Object ids

  Digit-leading ids are structural - `NH000000` the page template, `NH000251`
  the header - and letter-leading ids are content on a base-36 counter.
  `A000` is the conventional first content id, and it is what the recovered
  page template already points at, so the top stories keep it. Subordinate
  sets take the ids after it: `A001`, `A002`, and so on.
  """

  @legend "NH00"
  @top_id "A000"
  @page_template "NH000000PG"

  # The three bytes that precede the body OBJID in a destination parameter,
  # exactly as the recovered objects carry them.
  @destination_prefix <<0x58, 0x00, 0x01>>

  @doc """
  Build every object for `stories`.

  Returns a list of `{filename, bytes}`, using the `NAME.EXT_seq_type_ver`
  convention the uploader already understands.
  """
  @spec build([map()]) :: [{String.t(), binary()}]
  def build(stories) do
    total = length(stories)
    ids = subordinate_ids(stories)

    tops =
      stories
      |> Enum.with_index(1)
      |> Enum.map(fn {story, i} ->
        # The foot of each page trails the story the reader reaches with NEXT,
        # so every page but the last needs its successor's title.
        next = stories |> Enum.at(i) |> next_title()
        top_object(story, i, total, Map.get(ids, i), next)
      end)

    subs =
      stories
      |> Enum.with_index(1)
      |> Enum.flat_map(fn {story, i} ->
        case Map.get(ids, i) do
          nil -> []
          id -> subordinate_objects(story, id)
        end
      end)

    tops ++ subs
  end

  @doc """
  Content ids for the stories that carry subordinate coverage, keyed by the
  story's position. Allocated in order from the id after `A000`, so they can
  collide neither with the top set nor with each other.
  """
  @spec subordinate_ids([map()]) :: %{pos_integer() => String.t()}
  def subordinate_ids(stories) do
    stories
    |> Enum.with_index(1)
    |> Enum.filter(fn {story, _i} -> story.substories != [] end)
    |> Enum.map_reduce(next_id(@top_id), fn {_story, i}, id ->
      {{i, id}, next_id(id)}
    end)
    |> elem(0)
    |> Map.new()
  end

  @doc """
  The next content id after `id`, counting in base 36 across all four
  characters.

      iex> HeadlineObjects.next_id("A000")
      "A001"
      iex> HeadlineObjects.next_id("A00Z")
      "A010"
  """
  @spec next_id(String.t()) :: String.t()
  def next_id(id) do
    (String.to_integer(id, 36) + 1)
    |> Integer.to_string(36)
    |> String.pad_leading(4, "0")
    |> String.upcase()
  end

  # --- Objects --------------------------------------------------------------

  # The short form a story is announced by on the previous page. The editor
  # supplies one; falling back to the headline keeps older plans working, at
  # the cost of a trim.
  defp next_title(nil), do: nil

  defp next_title(story) do
    case Map.get(story, :short_title) do
      t when is_binary(t) and t != "" -> t
      _ -> story.headline
    end
  end

  defp top_object(story, sequence, total, sub_id, next) do
    labels = Enum.map(story.substories, & &1.label)

    naplps = HeadlinePage.render(story.headline, story.body, labels, next)

    menu =
      case sub_id do
        nil -> []
        id -> [menu_for(id, length(labels))]
      end

    segments =
      [
        PresentationData.new(:presentation_data_naplps, naplps),
        CustomText.new(1, 7, 0)
      ] ++ field_defs(length(labels)) ++ menu

    {"#{@legend}#{@top_id}.B_#{sequence}_8_1",
     encode(@legend <> @top_id, sequence, total, segments)}
  end

  defp subordinate_objects(story, id) do
    total = length(story.substories)

    story.substories
    |> Enum.with_index(1)
    |> Enum.map(fn {sub, j} ->
      naplps = HeadlinePage.render(sub.label, sub.body, [], nil)

      segments = [
        PresentationData.new(:presentation_data_naplps, naplps),
        CustomText.new(1, 7, 0)
      ]

      {"#{@legend}#{id}.B_#{j}_8_1", encode(@legend <> id, j, total, segments)}
    end)
  end

  # One numbered, selectable box per link, from the page's own geometry.
  defp field_defs(count) do
    HeadlinePage.field_defs(count)
    |> Enum.map(fn f ->
      [x, y] = f.origin
      [w, h] = f.size
      # 0x80/0x00 - an action field, which is what both the traced originals
      # and the recovered objects use for a numbered selection box. (objutil
      # labels these "state=input, format=alphabetic", which does not match
      # the library's own value map.)
      # new/6 is the cursor-less form, which is what both the traced originals
      # and the recovered objects use - naming a cursor would add four bytes
      # the service never shipped here.
      FieldDefinition.new(
        :field_state_action_field,
        :field_format_alphanumeric,
        {x, y},
        {w, h},
        f.name,
        1
      )
    end)
  end

  # Every link navigates to the shared page template, carrying the body it
  # wants displayed.
  defp menu_for(sub_id, count) do
    actions =
      for j <- 1..count do
        body = StandardMenu.objid("#{@legend}#{sub_id}B", j, 0x08)

        StandardMenu.objid(@page_template, 1, 0x04) <>
          StandardMenu.destination(@destination_prefix <> body)
      end

    StandardMenu.new(:pc_event_post_processor, mode: 3, actions: actions)
  end

  # Header.new/4 puts the SEGMENT count in the set-size byte, which is only
  # ever right by accident, so the header is built directly.
  defp encode(name, sequence, set_size, segments) do
    %Header{
      object_name: String.slice(name, 0, 8),
      object_ext: "B  ",
      sequence: sequence,
      object_type: :page_element_object,
      object_module: nil,
      candicacy_version_high: 0,
      num_objects: set_size,
      candidacy_version_low: 1,
      object_list: segments
    }
    |> ObjectEncoder.encode()
  end
end
