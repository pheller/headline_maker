defmodule HeadlinePage do
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
  Draws a HEADLINE NEWS body: a story over a list of subordinate story links.

  The geometry is derived from the traced originals NH00A000.B01 (four links)
  and .B02 (one link); see the applications-trial plan
  `headline-news-body-templates.md` for how each number was arrived at. Every
  measurement keys off the link count, because the link block is anchored to
  the bottom of the panel and grows upward into the story's space.

  This module produces the NAPLPS for the page and the field definitions that
  make the links selectable. It does not decide what the links point at - that
  is navigation wiring on the page template, not presentation.
  """

  import NaplpsWriter
  use NaplpsConstants

  # --- Geometry, all in GCU units -------------------------------------------

  @panel_top 178
  @panel_left 0
  @panel_width 254
  @panel_height 127

  @bottom_rule 65
  @link_pitch 15
  @link_box_left 5
  @link_box_size {12, 11}
  @gutter_width 16

  @rule_left 23
  @rule_length 229
  @label_left 23
  @label_width 233

  @body_left 3
  @body_width 250
  @body_top 167
  @body_pitch 9
  @body_clearance 4

  # Three text sizes, as the originals use: the story is finer than the link
  # labels, and the numerals in the gutter are larger again. The second TEXT
  # operand differs too - 0xC0 steps one character height per row, 0xC2 steps
  # one and a half, which is what makes the link rows 15 apart while the body
  # rows are 9.
  @body_font {5, 9}
  @label_font {5, 10}
  @numeral_font {6, 10}
  @spacing_single 0xC0
  @spacing_wide 0xC2

  @max_links 6

  @doc "Rows of story text available with `n` subordinate links."
  @spec body_rows(non_neg_integer()) :: non_neg_integer()
  def body_rows(n) when n in 0..@max_links do
    div(@body_top - top_rule(n) - @body_clearance, @body_pitch) |> max(0)
  end

  @doc "Y of the rule above the link block; `nil` when there are no links."
  @spec top_rule(non_neg_integer()) :: pos_integer() | nil
  def top_rule(0), do: @bottom_rule
  def top_rule(n) when n in 1..@max_links, do: @bottom_rule + @link_pitch * n + 2

  @doc "Y of the first (topmost) link row."
  @spec first_link_row(pos_integer()) :: pos_integer()
  def first_link_row(n) when n in 1..@max_links,
    do: @bottom_rule + @link_pitch * (n - 1) + 4

  @doc """
  Field definitions for `n` links, as `objutil` manifest maps - one selectable
  box per link, stepping down from the top of the block.
  """
  @spec field_defs(non_neg_integer()) :: [map()]
  def field_defs(0), do: []

  def field_defs(n) when n in 1..@max_links do
    {w, h} = @link_box_size
    first = first_link_row(n)

    for i <- 0..(n - 1) do
      %{origin: [@link_box_left, first - i * @link_pitch], size: [w, h], name: i + 1}
    end
  end

  @doc """
  The page's NAPLPS.

  `headline` and `body` are the story; `labels` are the subordinate link
  captions, at most #{@max_links} of them. `next_headline` is the trailing
  "... [NEXT]" line, or nil.
  """
  @spec render(String.t(), String.t(), [String.t()], String.t() | nil) :: binary()
  def render(headline, body, labels \\ [], next_headline \\ nil) do
    n = length(labels)

    gcu_init()
    |> panel()
    |> story(headline, body, n)
    |> links(labels, n)
    |> next_line(next_headline, n)
  end

  # --- Pieces ---------------------------------------------------------------

  defp panel(buffer) do
    buffer
    |> select_color(@color_black)
    |> draw(@cmd_set_rect_filled, [
      {@panel_left / 256, @panel_top / 256},
      {@panel_width / 256, -@panel_height / 256}
    ])
  end

  defp story(buffer, headline, body, n) do
    rows = body_rows(n)
    head_lines = wrap(headline, @body_font, @body_width) |> Enum.take(2)
    body_lines = wrap(body, @body_font, @body_width) |> Enum.take(rows)

    buffer
    |> text_size(@body_font, @spacing_single)
    # The wrap controls stay on although the text arrives pre-broken: two
    # bytes, and free insurance on a renderer that wraps properly.
    |> append_byte(@gr_word_wrap_on)
    |> select_color(@color_gray)
    |> lines(head_lines, @body_top, @body_pitch, :center)
    |> select_color(@color_white)
    |> lines(body_lines, @body_top - length(head_lines) * @body_pitch, @body_pitch, :left)
    |> append_byte(@gr_word_wrap_off)
  end

  defp links(buffer, [], _n), do: buffer

  defp links(buffer, labels, n) do
    first = first_link_row(n)

    buffer
    # Selection gutter behind the numerals.
    |> select_color(@color_gray)
    |> draw(@cmd_set_rect_filled, [
      {1 / 256, (top_rule(n) - 1) / 256},
      {@gutter_width / 256, -(@link_pitch * (n + 1)) / 256}
    ])
    |> text_size(@numeral_font, @spacing_wide)
    |> select_color(@color_black)
    |> numerals(n, first)
    # Rules bracketing the block, in the dark red the originals use.
    |> select_color(@color_red)
    |> draw(@cmd_set_line_rel, [
      {@rule_left / 256, top_rule(n) / 256},
      {@rule_length / 256, 0},
      {@rule_left / 256, @bottom_rule / 256},
      {@rule_length / 256, 0}
    ])
    # The colour must be put back before the labels or they inherit the red.
    |> select_color(@color_gray)
    |> text_size(@label_font, @spacing_wide)
    |> labels(labels, first)
  end

  defp numerals(buffer, n, first) do
    Enum.reduce(0..(n - 1), buffer, fn i, acc ->
      draw_text_abs(acc, " #{i + 1}", {@link_box_left / 256, (first - i * @link_pitch) / 256})
    end)
  end

  defp labels(buffer, labels, first) do
    labels
    |> Enum.with_index()
    |> Enum.reduce(buffer, fn {label, i}, acc ->
      text = label |> wrap(@label_font, @label_width) |> List.first() || ""
      draw_text_abs(acc, text, {@label_left / 256, (first - i * @link_pitch) / 256})
    end)
  end

  defp next_line(buffer, nil, _n), do: buffer

  defp next_line(buffer, headline, n) do
    {w, _} = @label_font
    text = fit_next(headline, w)
    y = if n == 0, do: @bottom_rule - 11, else: first_link_row(n) - @link_pitch * n
    x = @panel_width - round(NaplpsText.text_width(w, text))

    buffer
    |> text_size(@label_font, @spacing_wide)
    |> select_color(@color_gray)
    |> draw_text_abs(text, {max(x, @label_left) / 256, y / 256})
  end

  # Drop trailing words from the next story's headline until it and the [NEXT]
  # marker fit the width available to the right of the gutter.
  defp fit_next(headline, char_width) do
    avail = @panel_width - @label_left
    words = String.split(headline, " ")

    Enum.reduce_while(length(words)..1//-1, "[NEXT]", fn k, _acc ->
      candidate = (words |> Enum.take(k) |> Enum.join(" ")) <> " [NEXT]"

      if NaplpsText.text_width(char_width, candidate) <= avail,
        do: {:halt, candidate},
        else: {:cont, "[NEXT]"}
    end)
  end

  # --- Helpers --------------------------------------------------------------

  # NaplpsWriter.text_attributes/2 hardcodes the single-height spacing operand,
  # so the wide-spaced link rows need the bytes written directly.
  defp text_size(buffer, {w, h}, spacing) do
    buffer
    |> append_bytes([@cmd_text_attr, 0xF0, spacing])
    |> mb_xy({w / 256, h / 256})
  end

  defp wrap(text, {w, _h}, width), do: NaplpsText.wrap(text, w, width)

  defp lines(buffer, lines, top, pitch, align) do
    lines
    |> Enum.with_index()
    |> Enum.reduce(buffer, fn {line, i}, acc ->
      draw_text_abs(acc, line, {x_for(line, align) / 256, (top - i * pitch) / 256})
    end)
  end

  defp x_for(_line, :left), do: @body_left

  defp x_for(line, :center) do
    {w, _} = @body_font
    @body_left + round((@body_width - NaplpsText.text_width(w, line)) / 2)
  end
end
