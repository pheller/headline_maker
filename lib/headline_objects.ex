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

  ## One object per page

  Every recovered HEADLINE NEWS body is `sequence 1` of `set_size 1` with its
  own id - NH00A3XY, NH00CF4J, NH00CF4K - so the service did not page through
  element sets here. Each screen is its own object, and the base-36 id is a
  page counter: CF4J and CF4K are adjacent because they were allocated one
  after the other.

  ## NEXT chains through the menu, not through a set

  A body's standard menu carries the next page in its third parameter. That is
  the whole reason NH00CF4JB has a menu at all - its choice and action lists
  are empty, and P3 names CF4K. So every page gets a menu, whether or not it
  has numbered links, and the last page of a chain simply has nothing in P3.

  ## How a subordinate link reaches its page

  An action navigates to the SHARED page template and passes the body to
  display as a destination parameter. One template serves every screen, told
  each time which element to show, so no page template is generated here.

  ## Object ids

  Digit-leading ids are structural - NH000000 the page template, NH000251 the
  header - and letter-leading ids are content. A000 is the conventional first
  content id and is what the recovered page template already points at, so the
  first story keeps it; every page after that takes the next id in turn.
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
    plan = allocate(stories)

    tops =
      plan
      |> Enum.map(fn %{id: id, story: story, subs: subs, next: next, next_title: next_title} ->
        page(
          id,
          story.headline,
          story.body,
          Enum.map(subs, & &1.sub.label),
          next,
          first_sub_id(subs),
          next_title
        )
      end)

    subs =
      Enum.flat_map(plan, fn %{subs: subs} ->
        Enum.map(subs, fn %{id: id, sub: sub, next: next, next_label: nt} ->
          page(id, sub.label, sub.body, [], next, nil, nt)
        end)
      end)

    tops ++ subs
  end

  @doc """
  Assign a page id to every screen and work out what each one's NEXT is.

  Top stories are allocated first, so they keep the contiguous run beginning at
  `A000`; each story's subordinate pages follow. Within a group, every page
  points at the next and the last points at nothing.
  """
  @spec allocate([map()]) :: [map()]
  def allocate(stories) do
    {tops, next_free} =
      Enum.map_reduce(stories, @top_id, fn story, id -> {{id, story}, next_id(id)} end)

    {plan, _} =
      Enum.map_reduce(Enum.with_index(tops), next_free, fn {{id, story}, i}, free ->
        {sub_ids, free} =
          Enum.map_reduce(story.substories, free, fn sub, f -> {{f, sub}, next_id(f)} end)

        subs =
          sub_ids
          |> Enum.with_index()
          |> Enum.map(fn {{sid, sub}, j} ->
            following = Enum.at(sub_ids, j + 1)

            %{
              id: sid,
              sub: sub,
              next: following && elem(following, 0),
              next_label: following && elem(following, 1).label
            }
          end)

        following_top = Enum.at(tops, i + 1)

        {%{
           id: id,
           story: story,
           subs: subs,
           next: following_top && elem(following_top, 0),
           # The foot of a page announces the page NEXT reaches, so this is the
           # FOLLOWING story's short form, not this story's.
           next_title: following_top && next_title(elem(following_top, 1))
         }, free}
      end)

    plan
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

  # Every page is sequence 1 of set size 1 with its own id; NEXT is carried by
  # the menu rather than by set membership.
  defp page(id, headline, body, labels, next_id, first_sub_id, next_title) do
    naplps = HeadlinePage.render(headline, body, labels, next_title)

    segments =
      [
        PresentationData.new(:presentation_data_naplps, naplps),
        CustomText.new(1, 7, 0)
      ] ++
        field_defs(length(labels)) ++
        [menu(next_id, labels, first_sub_id), dispatcher()]

    {"#{@legend}#{id}.B_1_8_1", encode(@legend <> id, 1, 1, segments)}
  end

  defp next_title(story) do
    case Map.get(story, :short_title) do
      t when is_binary(t) and t != "" -> t
      _ -> story.headline
    end
  end

  # P3 names the page NEXT reaches; P4/P5/P6 carry the numbered links, which a
  # page without subordinate coverage simply leaves empty - exactly the shape
  # NH00CF4JB has, where the menu exists only to declare its successor.
  defp menu(next_id, labels, first_sub_id) do
    next_page =
      if next_id do
        StandardMenu.objid(@page_template, 1, 0x04) <>
          StandardMenu.destination(
            @destination_prefix <> StandardMenu.objid("#{@legend}#{next_id}B", 1, 0x08)
          )
      end

    actions =
      case first_sub_id do
        nil ->
          []

        first ->
          labels
          |> Enum.with_index()
          |> Enum.map(fn {_label, i} ->
            body = sub_id_at(first, i)

            StandardMenu.objid(@page_template, 1, 0x04) <>
              StandardMenu.destination(
                @destination_prefix <> StandardMenu.objid("#{@legend}#{body}B", 1, 0x08)
              )
          end)
      end

    StandardMenu.new(:pc_event_initializer,
      mode: 3,
      next_page: next_page,
      actions: actions
    )
  end

  defp first_sub_id([]), do: nil
  defp first_sub_id([%{id: id} | _]), do: id

  defp sub_id_at(first, 0), do: first
  defp sub_id_at(first, n), do: sub_id_at(next_id(first), n - 1)

  # The post-processor half. It takes no parameters and carries NO parameter
  # area - nil rather than [], since an empty area would make the segment two
  # bytes longer than the recovered call.
  defp dispatcher do
    ProgramCall.new(
      :pc_event_post_processor,
      :pc_prefix_program_call,
      "XXOPSM01",
      "PGM",
      <<>>,
      nil
    )
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
