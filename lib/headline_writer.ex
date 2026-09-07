defmodule HeadlineWriter do
  # Copyright 2025, Ralph Richard Cook
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

  require Logger
  use NaplpsConstants
  import NaplpsWriter

  @number_of_pages 4

  @debug_delimiter "////////"

  # TODO Add these constants to NaplpsConstants
  @text_width 6
  @text_height 10

  @headline_length 90
  @body_length 450

  # Body text area, in GCU units. The field starts at x=4 and is 251 wide; the
  # story begins at y=147 and must stop clear of the "Go to next page" row at
  # y=55, which leaves eight rows at the current line pitch.
  @body_left 4
  @body_width 251
  @body_top 147
  @body_rows 8

  # C0 text spacing steps one character height per row.
  @line_pitch @text_height

  # Makes the debug delimiter available to other modules
  def debug_delimiter(), do: @debug_delimiter

  @spec dequote(binary()) :: binary()
  def dequote(text) do
    cond do
      String.at(text, 0) == "\"" and String.at(text, -1) == "\"" ->
        String.slice(text, 1, String.length(text) - 2)

      true ->
        text
    end
  end

  def news_trim(text, max_length) do
    if String.length(text) > max_length do
      String.slice(text, 0, max_length - 3) <> "..."
    else
      text
    end
  end

  def choose_summary(original_text, {:error, reason}, summary_length) do
    Logger.error("Error summarizing text: #{inspect(reason)}. Using original text.")
    news_trim(original_text, summary_length)
  end

  # How far over the cap a summary can be and still be worth trimming. Beyond
  # this the model clearly ignored the length instruction, so the original text
  # is the safer thing to cut down.
  @overshoot_tolerance 1.5

  def choose_summary(original_text, {:ok, summary_text}, summary_length) do
    # sometimes the llm puts quotes around the summary, so we want to dequote it if that's the case
    dq_summary = dequote(summary_text)
    summary_len = String.length(dq_summary)

    return_text =
      cond do
        summary_len <= summary_length ->
          dq_summary

        # A summary a few characters over is still a summary. Trimming it beats
        # falling back to the raw story, which is all boilerplate and captions
        # at the front - that fallback threw away every summary of a real feed.
        summary_len <= summary_length * @overshoot_tolerance ->
          Logger.info(
            "Summary of #{summary_len} is over the #{summary_length} limit; trimming it rather than the original (#{String.length(original_text)})."
          )

          dq_summary

        true ->
          Logger.warning(
            "Summary of #{summary_len} far exceeds the #{summary_length} limit; using the original text (#{String.length(original_text)}) instead."
          )

          original_text
      end

    news_trim(return_text, summary_length)
  end

  def write_headlines(options) do
    list_of_long_stories =
      options[:feedstyle].get_stories(options, @number_of_pages)

    list_of_stories =
      if options[:debuginput] != nil do
        Logger.info("Using debug input from #{options[:debuginput]}")
        list_of_long_stories
      else
        Enum.map(list_of_long_stories, fn [hl, body] ->
          # result_hl = (case summarize_text(hl, @headline_length) do
          #   {:ok, short_hl} -> short_hl |> dequote()
          #   {:error, _} -> hl
          # end) |> news_trim(@headline_length)
          result_hl =
            choose_summary(hl, summarize_text(hl, @headline_length, :headline), @headline_length)

          # result_body = (case summarize_text(body, @body_length) do
          #   {:ok, short_body} -> short_body |> dequote()
          #   {:error, _} -> body
          # end) |> news_trim(@body_length)
          result_body =
            choose_summary(body, summarize_text(body, @body_length, :body), @body_length)

          [String.trim(result_hl) <> to_string(options[:attribution]), result_body]
        end)
      end

    list_of_pages = Enum.zip(1..length(list_of_stories), list_of_stories)

    if options[:debugoutput] do
      Enum.each(list_of_pages, fn {page_number, [headline, story]} ->
        debug_file = Path.join(options[:debugoutput], "hmdebug_#{page_number}")
        IO.inspect(debug_file, label: "Debug file")
        File.write!(debug_file, "#{headline}#{@debug_delimiter}#{story}")
        Logger.info("Written debug text to #{debug_file}")
      end)
    end

    [file, ext] = String.split(options[:output], ".", parts: 2)
    # First letter for the proper extension
    ext = String.slice(ext, 0, 1)

    # Write each page to a separate file
    Enum.each(list_of_pages, fn page ->
      # Make a page element object
      {page_number, _} = page
      peo = make_peo(options[:output], page, @number_of_pages)

      peo_buffer =
        ObjectEncoder.encode(peo)
        |> page_setup(page_number, @number_of_pages)

      file_path = Path.join(options[:directory], "#{file}.#{ext}_#{page_number}_8_1")
      File.write!(file_path, peo_buffer)
      Logger.info("Written story to #{file_path}")
    end)
  end

  def make_peo(output, {page_number, [headline, story]}, number_of_pages) do
    # Create a page element object with the headline and story

    [file, ext] = String.split(output, ".", parts: 2)
    file = ObjectUtils.edit_length(file, 8)
    ext = ObjectUtils.edit_length(ext, 3)

    pds = make_pds(page_number, headline, story, number_of_pages)

    Header.new(file, ext, :page_element_object, [pds])
  end

  # Make a presentation data segment (PDS) for the page
  def make_pds(page_number, headline, story, number_of_pages) do
    headline_naplps = make_headline_naplps(page_number, headline, story, number_of_pages)

    PresentationData.new(:presentation_data_naplps, headline_naplps)
  end

  def make_headline_naplps(page_number, headline, story, number_of_pages) do
    headline = String.replace(headline, "\r\n", " ")
    story = String.replace(story, "\r\n", " ")

    buffer =
      gcu_init()
      |> text_attributes({@text_width / 256, @text_height / 256})
      |> select_color(@color_gray)
      |> draw(@cmd_set_rect_outlined, [{0 / 256, 179 / 256}, {255 / 256, -1 * (179 - 51) / 256}])
      |> draw(@cmd_set_rect_outlined, [{1 / 256, 178 / 256}, {253 / 256, -1 * (178 - 52) / 256}])
      |> select_color(@color_black)
      |> draw(@cmd_set_rect_filled, [{2 / 256, 177 / 256}, {251 / 256, -1 * (178 - 53) / 256}])
      |> then(fn b -> setup_next(b, page_number, number_of_pages) end)
      |> draw(@cmd_field, [{4 / 256, 177 / 256}, {251 / 256, -1 * (178 - 53) / 256}])
      #    |> draw(@cmd_set_rect_outlined, [{2 / 256, 177 / 256}, {253 / 256, (-1 * (177 - 53)) / 256}])
      # The wrap bytes stay on even though the text below arrives pre-broken.
      # They cost two bytes, never fire when our measurements are right, and
      # cost nothing on a renderer that wraps properly.
      |> append_byte(@gr_word_wrap_on)
      # Headline, centered by measured width rather than padded with spaces -
      # the font is proportional, so a character count would not center it.
      |> select_color(@color_gray)
      |> then(fn b ->
        line = headline_line(headline)
        draw_text_abs(b, line, {headline_x(line) / 256, 167 / 256})
      end)
      # Story, broken into lines here rather than left to the renderer: the
      # reference renderer breaks mid-word, and pre-breaking is also what lets
      # the generator check that its own output fits before uploading.
      |> select_color(@color_white)
      |> draw_story(story)
      |> append_byte(@gr_word_wrap_off)

    buffer
  end

  @doc """
  The story text broken to the body field, capped at the rows that fit.

  Returns at most `@body_rows` lines, each measured to sit within
  `@body_width`.
  """
  @spec story_lines(String.t()) :: [String.t()]
  def story_lines(story) do
    lines = NaplpsText.wrap(story, @text_width, @body_width)

    if length(lines) <= @body_rows do
      lines
    else
      # The summarizer works to a character budget, which in a proportional
      # font only approximates what fits. When it overshoots, trim to the last
      # row and mark it rather than dropping the tail silently mid-sentence -
      # a slightly short story still reads, and the warning says it happened.
      Logger.warning(
        "Story needs #{length(lines)} rows but only #{@body_rows} fit; trimming the tail."
      )

      lines
      |> Enum.take(@body_rows)
      |> List.update_at(-1, &ellipsize/1)
    end
  end

  @doc "Whether a story fits the body area without trimming."
  @spec fits?(String.t()) :: boolean()
  def fits?(story),
    do: length(NaplpsText.wrap(story, @text_width, @body_width)) <= @body_rows

  # Drop whole words off the end until the line plus an ellipsis fits.
  defp ellipsize(line) do
    words = String.split(line, " ")

    Enum.reduce_while(length(words)..1//-1, "...", fn n, _acc ->
      candidate = (words |> Enum.take(n) |> Enum.join(" ")) <> "..."

      if NaplpsText.text_width(@text_width, candidate) <= @body_width,
        do: {:halt, candidate},
        else: {:cont, "..."}
    end)
  end

  @doc "The headline trimmed to a single row of the body field."
  @spec headline_line(String.t()) :: String.t()
  def headline_line(headline) do
    case NaplpsText.wrap(headline, @text_width, @body_width) do
      [single] -> single
      [first | _] -> ellipsize(first)
      [] -> ""
    end
  end

  # Left edge that centers `text` in the body field.
  defp headline_x(text) do
    @body_left + round((@body_width - NaplpsText.text_width(@text_width, text)) / 2)
  end

  defp draw_story(buffer, story) do
    story
    |> story_lines()
    |> Enum.with_index()
    |> Enum.reduce(buffer, fn {line, i}, acc ->
      draw_text_abs(acc, line, {@body_left / 256, (@body_top - i * @line_pitch) / 256})
    end)
  end

  # If this is not the last page, put up the [Next] button
  defp setup_next(buffer, page_number, number_of_pages) do
    if page_number < number_of_pages do
      select_color(buffer, @color_gray)
      |> draw_text_abs("Go to next page", {23 / 256, 55 / 256})
      |> draw_text_abs("[NEXT]", {222 / 256, 55 / 256})
    else
      buffer
    end
  end

  defp page_setup(buffer, page_number, total_pages) do
    <<
      buf1::binary-size(9),
      _extension1,
      _extension2,
      _orig_page_number,
      buf2::binary-size(3),
      orig_stage_flags,
      _orig_total_pages,
      rest::binary
    >> = buffer

    # the headline names in the object have the extension truncated to one letter
    # 8.3 -> 8.1 and two spaces
    <<
      buf1::binary-size(9),
      0x20,
      0x20,
      page_number,
      buf2::binary-size(3),
      orig_stage_flags,
      total_pages,
      rest::binary
    >>
  end

  def summarize_text(text, max_length, kind \\ :body)

  def summarize_text(text, max_length, _kind)
      when is_binary(text) and byte_size(text) <= max_length do
    Logger.info(
      "Text is already within the maximum length of #{max_length} characters, skipping summarization."
    )

    {:ok, text}
  end

  def summarize_text(text, max_length, kind) when is_binary(text) do
    Summarizer.summarize(text, max_length, kind)
  end
end
