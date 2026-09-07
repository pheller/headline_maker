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

  def choose_summary(original_text, {:ok, summary_text}, summary_length) do
    # sometimes the llm puts quotes around the summary, so we want to dequote it if that's the case
    dq_summary = dequote(summary_text)
    return_text = if String.length(dq_summary) <= summary_length do
      dq_summary
    else
      Logger.info(
        "Summary is still too long after dequoting, using original text. Original length: #{String.length(original_text)}, Summary length: #{String.length(dq_summary)}, Max length: #{summary_length}"
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
          result_hl = choose_summary(hl, summarize_text(hl, @headline_length), @headline_length)
          # result_body = (case summarize_text(body, @body_length) do
          #   {:ok, short_body} -> short_body |> dequote()
          #   {:error, _} -> body
          # end) |> news_trim(@body_length)
          result_body = choose_summary(body, summarize_text(body, @body_length), @body_length)
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
      |> append_byte(@gr_word_wrap_on)
      # Headline color and position, can word wrap to next line
      |> select_color(@color_gray)
      |> draw_text_abs(headline, {4 / 256, 167 / 256})
      # Story color and position, can word wrap in the rest of the field
      |> select_color(@color_white)
      |> draw_text_abs(story, {4 / 256, 147 / 256})
      |> append_byte(@gr_word_wrap_off)

    buffer
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

  def summarize_text(text, max_length) when is_binary(text) and byte_size(text) <= max_length do
    Logger.info(
      "Text is already within the maximum length of #{max_length} characters, skipping summarization."
    )
    {:ok, text}
  end

  def summarize_text(text, max_length) when is_binary(text) do
    Summarizer.summarize(text, max_length)
  end
end
