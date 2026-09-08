defmodule NewsEditor do
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
  One editorial pass over the day's feed.

  Where `Summarizer` shortens a single piece of text, this makes the decisions
  a newsroom makes about the whole budget at once: which stories run, in what
  order, and which of them carry a tree of subordinate coverage. Those choices
  interact - a story given four subordinate links has less than half the room
  for its own summary than one given none - so they cannot be made a story at
  a time.

  Returns a plan; it does not draw anything.
  """

  require Logger

  # Rows available for the story body at each subordinate-link count, from the
  # HEADLINE NEWS layout model (see the applications-trial plans). The link
  # block is bottom-anchored and grows upward into the body's space, so a story
  # pays for every link it carries. At six links there is no body at all - the
  # page is a headline over a list, which is exactly what the 1990 captures
  # show.
  @body_rows %{0 => 10, 1 => 9, 2 => 7, 3 => 5, 4 => 4, 5 => 2, 6 => 0}

  # Characters per row actually achieved by wrapped prose in the 250-unit body
  # field at char width 5 - measured, not the theoretical 61.
  # Measured on real wrapped summaries in the 250-unit field at char width 5.
  @chars_per_row 58

  @headline_rows 2

  # The foot of each page announces the next story. It shares a line with the
  # [NEXT] marker, so it has to be far shorter than a headline - the originals
  # run to about thirty characters ("Exxon Pulls Valdez Cleanup Crew").
  @short_title_chars 35

  # The body field of the target layout: 250 units wide at char width 5.
  @char_width 5
  @field_width 250
  @label_chars 50

  @min_stories 5
  @max_stories 7

  @doc "Characters of body text available to a story carrying `n` links."
  @spec body_budget(non_neg_integer()) :: non_neg_integer()
  def body_budget(n), do: Map.get(@body_rows, n, 0) * @chars_per_row

  @doc "Characters available to a headline."
  @spec headline_budget() :: pos_integer()
  def headline_budget, do: @headline_rows * @chars_per_row

  @doc """
  Ask for the day's plan.

  `articles` is a list of `[headline, body]` pairs as the feeds produce them.
  Returns `{:ok, stories}` where each story is a map with `:headline`, `:body`
  and `:substories`.
  """
  @spec plan([[String.t()]], keyword()) :: {:ok, [map()]} | {:error, term()}
  def plan(articles, opts \\ []) when is_list(articles) do
    attempts = Keyword.get(opts, :attempts, 2)

    with {:ok, text} <- Summarizer.complete_raw(prompt(articles)),
         {:ok, stories} <- parse(text) do
      {:ok, Enum.map(stories, &tighten(&1, attempts))}
    end
  end

  # --- Fitting --------------------------------------------------------------

  # The page is the authority on length, not the character count the prompt
  # quotes. Measure what came back and, when a summary runs long, ask for it
  # again with the overage stated. Re-asking beats trimming: the model can drop
  # a whole clause where a trim would cut mid-sentence.
  defp tighten(story, attempts) do
    budget = Map.get(@body_rows, length(story.substories), 0)
    story = %{story | body: fit_text(story.body, budget, attempts, "story summary")}

    subs =
      Enum.map(story.substories, fn sub ->
        %{sub | body: fit_text(sub.body, @body_rows[0], attempts, "subordinate summary")}
      end)

    %{story | substories: subs}
  end

  defp fit_text(text, budget, attempts, what) do
    actual = rows(text)

    cond do
      actual <= budget ->
        text

      attempts <= 0 ->
        Logger.warning(
          "#{what} still #{actual} lines against #{budget}; leaving it to the renderer"
        )

        text

      true ->
        Logger.info("#{what} is #{actual} lines against #{budget}; asking for it shorter")

        case Summarizer.complete_raw(shorten_prompt(text, actual, budget)) do
          {:ok, shorter} ->
            fit_text(Summarizer.to_ascii(String.trim(shorter)), budget, attempts - 1, what)

          {:error, reason} ->
            Logger.warning("could not shorten #{what}: #{inspect(reason)}")
            text
        end
    end
  end

  @doc "Lines this text occupies in the body field."
  @spec rows(String.t()) :: non_neg_integer()
  def rows(text), do: length(NaplpsText.wrap(text, @char_width, @field_width))

  defp shorten_prompt(text, actual, budget) do
    """
    This news summary runs #{actual} lines on the page. It must fit #{budget}.

    Rewrite it #{actual - budget} lines shorter - roughly
    #{(actual - budget) * @chars_per_row} characters - keeping the most
    important facts and the same plain wire-service voice. Drop whole clauses
    or a whole sentence rather than trimming words everywhere. Do not end with
    an ellipsis.

    Reply with the rewritten summary only.

    #{text}
    """
  end

  @doc "The editorial prompt. Exposed so it can be read and reviewed on its own."
  @spec prompt([[String.t()]]) :: String.t()
  def prompt(articles) do
    wire =
      articles
      |> Enum.with_index(1)
      |> Enum.map_join("\n\n", fn {[hl, body], i} ->
        "ARTICLE #{i}\nTitle: #{hl}\nText: #{body}"
      end)

    """
    #{voice()}

    #{task()}

    #{budgets()}

    #{output_format()}

    Here is today's wire copy.

    #{wire}
    """
  end

  # --- The prompt, in pieces so each can be revised on its own ---------------

  defp voice do
    """
    You are a copy editor in the PRODIGY news department, writing HEADLINE NEWS.

    You write in the house style of PRODIGY's 1990 newsroom. The stories
    themselves are today's: report them as current news, and make no reference
    to any era, anniversary or passage of time. The style is what comes from
    1990, not the subject matter.

    Who you are writing for: adults who read a daily paper and follow the news.
    Most are college-educated professionals in two-income households, in and
    around cities; a growing share have young children at home. Write for
    someone intelligent and busy. Do not talk down, do not show off, and do not
    assume specialist knowledge - if a term is technical, place it in a few
    words and move on.

    Who you are: a working newsroom that rewrites AP and UPI wire copy to fit a
    screen. Your colleagues span the political spectrum and the copy does not
    take sides. Report what happened and who said it. Attribute contested
    claims to whoever made them. No adjectives that argue, no scare quotes, no
    knowing asides, no hype, no predictions of your own.

    You write to fit. The screen is small and fixed, and a newsroom that knows
    its medium writes to the space rather than writing long and being cut. A
    story told completely in fewer words is better work, not lesser.

    Headlines and subordinate labels take Title Case, capitalizing the
    principal words, as the service's own headlines do: "Bush Talks Tough in
    Congressional Address". Summaries are ordinary sentences.

    Style: plain declarative sentences, active voice, concrete names, numbers
    and places. Wire-service neutral. Past tense for what happened, present for
    what stands. No preamble and no sign-off - you are writing the screen the
    reader sees, not a note about it.
    """
  end

  defp task do
    """
    YOUR TASK

    From the wire copy below, put together today's HEADLINE NEWS.

    1. Choose the #{@min_stories} to #{@max_stories} stories that matter most.
       Leave the rest out. Weigh consequence and how many readers it touches;
       national and international news over local, unless the local story is
       genuinely extraordinary.

    2. Order them. Numbers 1 and 2 are the day's lead - the two a reader would
       be poorly informed for having missed. The rest follow in descending
       importance.

    3. For each story, decide whether it carries subordinate coverage.

       A subordinate story is its own screen with its own summary, reached from
       a numbered link. Add them ONLY when the wire copy genuinely holds
       separate angles that each stand on their own - a running international
       situation with distinct fronts, or a major event with real strands
       (what happened, the response, what it costs).

       A story with one thing to say gets no links, and that is the common
       case. But a genuinely big story - the kind that would lead a broadcast -
       may well carry three or four, and up to six are available. Give a story
       as many as it truly has and no more.

       Never invent an angle to fill a slot, never split one idea into two, and
       never add a link you cannot write a real summary for from the copy you
       were given.

       Every subordinate story must be supported by the article text. Do not
       reach for outside knowledge.

       The cost is real: every link you add takes room away from the story's
       own summary. Look at the table below before deciding.
    """
  end

  defp budgets do
    rows =
      0..6
      |> Enum.map_join("\n", fn n ->
        rows = @body_rows[n]

        "      #{n} link#{if n == 1, do: " ", else: "s"}   #{String.pad_leading(to_string(rows), 2)} lines  (about #{body_budget(n)} characters)" <>
          if(n == 6, do: "   - headline and links only, no summary", else: "")
      end)

    """
    LENGTHS

    The page is measured in LINES of about #{@chars_per_row} characters. What
    matters is the number of lines the text fills, so leave yourself room -
    text that overruns is cut, and a summary that lands two lines short reads
    better than one that gets truncated.

      Headline:            2 lines  (about #{headline_budget()} characters)
      Short title:         at most #{@short_title_chars} characters
      Subordinate label:   1 line   (at most #{@label_chars} characters)

      Story summary, by how many subordinate links the story carries:

    #{rows}

    A subordinate story's own summary gets the full #{@body_rows[0]} lines
    (about #{body_budget(0)} characters).
    """
  end

  defp output_format do
    """
    OUTPUT

    Reply with JSON only - no fences, no commentary. Shape:

    {"stories":[
      {"headline":"...","short_title":"...","body":"...",
       "substories":[{"label":"...","body":"..."}]}
    ]}

    "short_title" is how the story is announced at the foot of the PREVIOUS
    page, beside a [NEXT] marker. It is not a shortened headline: write a
    complete, self-contained phrase naming the story, the way a newspaper
    teases the next item. "Exxon Pulls Valdez Cleanup Crew", not "Exxon Pulls
    Valdez Cleanup Crew After Federal".

    List the stories in rank order. Use an empty array for a story with no
    subordinate coverage.

    Do NOT number the subordinate labels. The page draws its own numbered box
    beside each one, so a label that begins "1." reads as "1. 1.".

    Plain ASCII only: straight quotes, a hyphen for any dash, no ellipsis
    character.
    """
  end

  # --- Parsing --------------------------------------------------------------

  @doc """
  Parse a model reply into stories.

  Tolerant on purpose: models wrap JSON in prose or code fences often enough
  that failing the run over it would be silly. Anything that cannot be read as
  the documented shape is an error, and the caller falls back.
  """
  @spec parse(String.t()) :: {:ok, [map()]} | {:error, term()}
  def parse(text) when is_binary(text) do
    with {:ok, json} <- extract_json(text),
         {:ok, %{"stories" => stories}} when is_list(stories) <- Jason.decode(json) do
      {:ok, Enum.map(stories, &normalize/1)}
    else
      {:ok, other} -> {:error, {:unexpected_shape, other}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp extract_json(text) do
    trimmed = String.trim(text)

    case {String.starts_with?(trimmed, "{"), :binary.match(trimmed, "{")} do
      {true, _} -> {:ok, trimmed}
      {false, {start, _}} -> {:ok, String.slice(trimmed, start, String.length(trimmed) - start)}
      {false, :nomatch} -> {:error, :no_json_found}
    end
  end

  defp normalize(story) do
    %{
      headline: Summarizer.to_ascii(Map.get(story, "headline", "")),
      short_title:
        story
        |> Map.get("short_title", "")
        |> Summarizer.to_ascii(),
      body: Summarizer.to_ascii(Map.get(story, "body", "")),
      substories:
        story
        |> Map.get("substories", [])
        |> List.wrap()
        |> Enum.map(fn sub ->
          %{
            label:
              sub
              |> Map.get("label", "")
              |> Summarizer.to_ascii()
              |> String.replace(~r/^\s*\d+\s*[.):]\s*/, ""),
            body: Summarizer.to_ascii(Map.get(sub, "body", ""))
          }
        end)
    }
  end
end
