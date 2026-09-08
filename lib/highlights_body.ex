defmodule HighlightsBody do
  @moduledoc """
  Builds `TLOTA000B` - the body of the post-login HIGHLIGHTS page.

  HIGHLIGHTS is a page template (`TLOT0011PG`) that calls four elements by
  name. Only one of them carries the option list, so changing the landing page
  means regenerating exactly this object and nothing else.

  ## Why it is generated here

  Option 1 announces the day's lead story and links to HEADLINE NEWS, so it
  changes whenever the headlines do. Emitting it alongside the `NH00*` objects
  puts both in the same all-on-nothing upload set, which is the only way the
  landing page and the headline chain cannot disagree about what the lead
  story is.

  ## How it is built

  Not re-authored - patched. The recovered original is carried in `priv/` in
  two pieces:

    * `tlota000b.obj` - the packed 1124-byte object, byte-identical to the
      copy recovered from the service.
    * `tlota000b.td`  - its NAPLPS, decompiled to Telidraw source, with the
      six option text blocks replaced by a `@@SLOTS@@` marker.

  Generation substitutes the marker, transpiles back to NAPLPS, and splices
  the result into the original object in place of its presentation segment.
  Everything we do not fully understand - the field attributes and their
  cursor bytes, the custom_text segment, the whole 188-byte XXOPSM00
  parameter block and the XXOPSM01 post-processor call - survives untouched.

  `TelidrawTranspiler` round-trips the untouched original to the same 723
  bytes it started from, which is what makes this safe; `highlights_body_test`
  asserts it.

  ## Retargeting

  Only two of the nine destinations move, and both names are 11 characters, so
  they are substituted in place with no reframing:

      5C000000PG -> ZZAB0000PG   option 2, now Welcome / short history
      FN000000PG -> ZZPR0000P    option 3, the Prodigy Reloaded featurette
      SJ000000PG -> 3C00SRCHPG   option 4, the Software Guide
      AT000000PG -> GCC00000PG   option 5, the Computer Club bulletin board

  Options 4 and 5 were placeholder ideas from the first exhibit build and had
  no objects behind them at all. They now reach real content.

  Option 1 keeps the original's `NH000000PG`, which is also where the
  HEADLINES keyword lands.

  ## The slot-1 budget

  The text box is `field 35,131 102x30` and the original fills it with three
  lines whose longest is exactly 17 characters ("Hostage Execution"). 102/17
  is 6 and 30/3 is 10, so the cell is 6x10 MONOSPACE and the budget is a hard
  17 columns by 3 rows. The proportional metrics in `NaplpsText` do not apply
  to this slot - wrapping here is plain character counting.
  """

  @external_resource "priv/tlota000b.obj"
  @external_resource "priv/tlota000b.td"

  @template_obj File.read!("priv/tlota000b.obj")
  @template_td File.read!("priv/tlota000b.td")

  @output_name "TLOTA000.B_1_8_1"

  # Slot 1 is monospaced 6x10 in a 102x30 box.
  @slot1_cols 17
  @slot1_rows 3

  # The five text slots, in the order the NAPLPS draws them. Option 3 is the
  # promo panel on the right and carries no text of its own.
  @slot2 ["Welcome and a", "Short History of", "Prodigy"]
  @slot4 "Home-Office Computing Software Guide"
  @slot5 "Talk Tech in the Computer Club"
  @slot6 "Credit where credit is due"

  # Slots 4, 5 and 6 start at x=35 on a 256-wide screen in the same 6x10 cell,
  # so 221/6 = 36 characters. The original's own longest entry ("North to
  # Alaska and South to Atlanta") is exactly 36, which is what proves the limit
  # rather than merely implying it.
  @wide_slot_cols 36

  @retarget [
    {"5C000000PG ", "ZZAB0000PG "},
    {"FN000000PG ", "ZZPR0000P  "},
    {"SJ000000PG ", "3C00SRCHPG "},
    {"AT000000PG ", "GCC00000PG "}
  ]

  for {slot, text} <- [slot4: @slot4, slot5: @slot5, slot6: @slot6],
      String.length(text) > @wide_slot_cols do
    raise CompileError,
      description:
        "#{slot} is #{String.length(text)} characters; the row holds #{@wide_slot_cols}"
  end

  @doc """
  The destination substitutions, as `{from, to}` pairs.

  Every name is 11 characters on both sides, which is what lets them be
  swapped in place with no segment reframing.
  """
  @spec retarget_map() :: [{binary(), binary()}]
  def retarget_map, do: @retarget

  @doc """
  Build the HIGHLIGHTS body announcing `lead`.

  `lead` is the top story from `NewsEditor.plan/1`. Its `:highlight_title` is
  used when it fits the slot; otherwise the headline is wrapped to fit.

  Returns `{filename, bytes}` in the same convention the uploader already
  understands.
  """
  @spec build(map()) :: {String.t(), binary()}
  def build(lead) when is_map(lead) do
    {@output_name, patch(slot1_lines(lead))}
  end

  @doc """
  Rebuild the object with an explicit slot-1 block.

  Exposed for the round-trip test, which passes the original's own text and
  expects the original bytes back.
  """
  @spec patch([String.t()], keyword()) :: binary()
  def patch(slot1, opts \\ []) do
    nap = render_nap(slot1, opts)
    replace_presentation(@template_obj, nap) |> retarget(opts)
  end

  @doc """
  The three lines for slot 1: the model's `:highlight_title` when it fits,
  otherwise the headline wrapped to the box.

  A title that overruns is not an error worth failing a day's run over - the
  page still has to draw - so it falls back rather than raising.
  """
  @spec slot1_lines(map()) :: [String.t()]
  def slot1_lines(story) do
    case fits?(Map.get(story, :highlight_title)) do
      {:ok, lines} -> lines
      :error -> story |> Map.get(:headline, "") |> wrap()
    end
  end

  defp fits?(nil), do: :error
  defp fits?(""), do: :error

  defp fits?(text) when is_binary(text) do
    lines = text |> String.split(~r/\r?\n/, trim: true) |> Enum.map(&String.trim/1)

    if lines != [] and length(lines) <= @slot1_rows and
         Enum.all?(lines, &(String.length(&1) <= @slot1_cols)) do
      {:ok, lines}
    else
      :error
    end
  end

  # Greedy word wrap at a fixed column count. A word longer than the column
  # budget is hard-split rather than allowed to overrun the box.
  @doc false
  @spec wrap(String.t()) :: [String.t()]
  def wrap(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.flat_map(&split_long/1)
    |> Enum.reduce([], fn word, acc ->
      case acc do
        [] ->
          [word]

        [current | rest] ->
          candidate = current <> " " <> word

          if String.length(candidate) <= @slot1_cols,
            do: [candidate | rest],
            else: [word, current | rest]
      end
    end)
    |> Enum.reverse()
    |> Enum.take(@slot1_rows)
  end

  defp split_long(word) do
    if String.length(word) <= @slot1_cols do
      [word]
    else
      word |> String.graphemes() |> Enum.chunk_every(@slot1_cols) |> Enum.map(&Enum.join/1)
    end
  end

  # --- NAPLPS ---------------------------------------------------------------

  defp render_nap(slot1, opts) do
    slots =
      [
        boxed(slot1, "35/256 131/256 102/256 30/256", "35/256 151/256", true),
        boxed(Keyword.get(opts, :slot2, @slot2), "35/256 94/256 102/256 30/256", "35/256 114/256", false),
        single(Keyword.get(opts, :slot4, @slot4), "35/256 69/256"),
        single(Keyword.get(opts, :slot5, @slot5), "35/256 51/256"),
        single(Keyword.get(opts, :slot6, @slot6), "35/256 25/256")
      ]
      |> Enum.join("\n")

    @template_td
    |> String.replace("@@SLOTS@@", slots)
    |> TelidrawTranspiler.transpile!(init: false)
  end

  # A three-line slot in its own text box. `color 7` is emitted once, on the
  # first slot only, exactly where the original carries it.
  defp boxed(lines, box, origin, first?) do
    head = ["field " <> box, "move " <> origin] ++ if first?, do: ["color 7"], else: []
    (head ++ interleave(lines)) |> Enum.join("\n")
  end

  defp single(text, origin) do
    Enum.join(["field", "move " <> origin, text_cmd(text)], "\n")
  end

  # APR/APD between lines is what the original uses to step down a row.
  defp interleave(lines) do
    lines
    |> Enum.map(&text_cmd/1)
    |> Enum.intersperse(["APR", "APD"])
    |> List.flatten()
  end

  defp text_cmd(text), do: ~s(text "#{escape(text)}")

  defp escape(text), do: String.replace(text, "\"", "'")

  # --- Object surgery -------------------------------------------------------

  # Swap the presentation segment's payload, then fix that segment's length
  # and the object's total length. Every other segment is copied verbatim.
  defp replace_presentation(obj, nap) do
    <<head::binary-13, _total::16-little, tail3::binary-3, body::binary>> = obj
    <<0x51, seg_len::16-little, rest::binary>> = body

    payload_len = seg_len - 3
    <<format::binary-1, _old_nap::binary-size(payload_len - 1), others::binary>> = rest

    new_payload = format <> nap
    new_seg = <<0x51, byte_size(new_payload) + 3::16-little>> <> new_payload
    new_body = new_seg <> others

    head <> <<18 + byte_size(new_body)::16-little>> <> tail3 <> new_body
  end

  defp retarget(obj, opts) do
    Keyword.get(opts, :retarget, @retarget)
    |> Enum.reduce(obj, fn {from, to}, acc ->
      11 = byte_size(from)
      11 = byte_size(to)
      String.replace(acc, from, to)
    end)
  end
end
