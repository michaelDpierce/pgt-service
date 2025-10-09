require "json"

class HumeSessionsController < ApplicationController
  SYSTEM_PROMPT = <<~PROMPT
    You are a careful, structured summarizer. Read the conversation messages (assistant and user turns). 
    Classify user content into the following buckets (use EXACT keys):

    1. best_personal
    2. worst_personal
    3. impact_personal
    4. best_work
    5. worst_work
    6. impact_work
    7. best_family
    8. worst_family
    9. impact_family

    Rules:
    - Place each relevant user statement in the correct bucket's `items` (as short bullet strings).
    - If a bucket has nothing relevant, leave its `items` empty.
    - Keep items short (1–2 lines) and faithful to the user’s words (light paraphrase okay).
    - For each of the three "impact" buckets, write a one-sentence `impact_summary` (or empty string if insufficient info).
    - Create `overall_session_summary`: 3–6 sentences capturing key themes and changes over time (if any).
    - Create `emotions_summary.user_top3`: pick the top three emotions that characterize the USER across the session; if scores are provided, prefer higher-scoring and more frequent emotions. For each, include `name`, `mean_score` (0–1, float), and `occurrences` (int). If you can’t estimate scores, set them to null.
    - Create `emotions_summary.notes`: 1–3 sentences explaining the emotional pattern (e.g., spikes, contrast with assistant tone, etc.).

    Output valid JSON only, matching the schema exactly. No extra text or markdown.
  PROMPT

  def create
    payload = params.permit!.to_h
    session = HumeSession.create!(data: payload)

    chat_messages = Array(payload["transcript"]).map do |e|
      role = %w[user assistant].include?(e["role"].to_s.downcase) ? e["role"].to_s.downcase : "user"
      emo_line =
        if e["emotions_top3"].present?
          tops = e["emotions_top3"].map { |x| "#{x["name"]}(#{x["score"]})" }.join(", ")
          " | top_emotions: #{tops}"
        else
          ""
        end
      { role: role, content: "#{e["text"]}#{emo_line}" }
    end

    precomputed = compute_user_emotion_stats(payload["transcript"])

    user_instruction = <<~INSTR.strip
      Produce STRICT JSON with these keys:

      {
        "buckets": {
          "best_personal":   { "items": [], "impact_summary": "" },
          "worst_personal":  { "items": [], "impact_summary": "" },
          "impact_personal": { "items": [], "impact_summary": "" },
          "best_work":       { "items": [], "impact_summary": "" },
          "worst_work":      { "items": [], "impact_summary": "" },
          "impact_work":     { "items": [], "impact_summary": "" },
          "best_family":     { "items": [], "impact_summary": "" },
          "worst_family":    { "items": [], "impact_summary": "" },
          "impact_family":   { "items": [], "impact_summary": "" }
        },
        "overall_session_summary": "",
        "emotions_summary": {
          "user_top3": [ { "name": "", "mean_score": null, "occurrences": 0 } ],
          "notes": ""
        }
      }

      Focus ONLY on USER turns for emotions. If no numeric scores are present, set mean_score to null.

      (Context – precomputed user emotion stats for reference):
      #{JSON.pretty_generate(precomputed)}
    INSTR

    messages = [
      { role: "system", content: SYSTEM_PROMPT },
      { role: "user", content: user_instruction },
      *chat_messages
    ]

    client = OpenAI::Client.new

    # --- Try #1: JSON Schema enforcement (if supported) ---
    schema = {
      type: "object",
      required: ["buckets", "overall_session_summary", "emotions_summary"],
      additionalProperties: false,
      properties: {
        buckets: {
          type: "object",
          required: %w[
            best_personal worst_personal impact_personal
            best_work worst_work impact_work
            best_family worst_family impact_family
          ],
          additionalProperties: false,
          properties: Hash[
            %w[
              best_personal worst_personal impact_personal
              best_work worst_work impact_work
              best_family worst_family impact_family
            ].map { |k|
              [k, {
                type: "object",
                required: ["items", "impact_summary"],
                additionalProperties: false,
                properties: {
                  items: { type: "array", items: { type: "string" } },
                  impact_summary: { type: "string" }
                }
              }]
            }
          ]
        },
        overall_session_summary: { type: "string" },
        emotions_summary: {
          type: "object",
          required: ["user_top3", "notes"],
          additionalProperties: false,
          properties: {
            user_top3: {
              type: "array",
              items: {
                type: "object",
                required: ["name", "mean_score", "occurrences"],
                additionalProperties: false,
                properties: {
                  name: { type: "string" },
                  mean_score: { type: ["number", "null"] },
                  occurrences: { type: "integer" }
                }
              }
            },
            notes: { type: "string" }
          }
        }
      }
    }

    raw = nil
    parsed = nil

    begin
      response = client.chat(
        parameters: {
          model: "gpt-4.1-mini",
          temperature: 0.0,
          max_tokens: 1200, # give headroom so it doesn't truncate
          response_format: {
            type: "json_schema",
            json_schema: { name: "BucketedSessionSummary", schema: schema, strict: true }
          },
          messages: messages
        }
      )
      raw = response.dig("choices", 0, "message", "content").to_s
      parsed = JSON.parse(raw)
    rescue => _ignored
      # Fall through to next attempts
    end

    # --- Try #2: json_object fallback (older models/accounts) ---
    if parsed.nil?
      begin
        response = client.chat(
          parameters: {
            model: "gpt-4.1-mini",
            temperature: 0.0,
            max_tokens: 1200,
            response_format: { type: "json_object" },
            messages: messages
          }
        )
        raw = response.dig("choices", 0, "message", "content").to_s
        parsed = JSON.parse(raw)
      rescue => _ignored
      end
    end

    # --- Try #3: plain text + coercion helper ---
    if parsed.nil?
      response = client.chat(
        parameters: {
          model: "gpt-4.1-mini",
          temperature: 0.0,
          max_tokens: 1200,
          messages: [
            { role: "system", content: "#{SYSTEM_PROMPT}\nReturn ONLY JSON. No markdown, no commentary." },
            { role: "user", content: user_instruction },
            *chat_messages
          ]
        }
      )
      raw = response.dig("choices", 0, "message", "content").to_s
      parsed = safe_json_coerce(raw)
    end

    if parsed.nil?
      Rails.logger.error("OpenAI summary not valid JSON.\nRaw:\n#{raw}")
      return render json: { ok: false, error: "Model did not return valid JSON" }, status: :unprocessable_entity
    end

    session.update!(
      data: session.data.merge(
        "openai_summary" => parsed,
        "openai_model"   => "gpt-4.1-mini"
      )
    )

    render json: { ok: true, summary: parsed }
  end

  private

  # Coerce common patterns: code fences, leading/trailing prose, and extract
  # the first balanced {...} block.
  def safe_json_coerce(str)
    return nil if str.blank?

    s = str.dup.strip
    # Strip code fences if present
    s = s.sub(/\A```(?:json)?\s*/i, "").sub(/```+\z/, "").strip

    # If it's already valid
    begin
      return JSON.parse(s)
    rescue JSON::ParserError
    end

    # Extract the first balanced {...}
    obj = extract_first_json_object(s)
    return obj if obj

    nil
  end

  # Finds the first balanced JSON object in a string and parses it.
  def extract_first_json_object(s)
    depth = 0
    start_idx = nil
    s.each_char.with_index do |ch, i|
      if ch == "{"
        depth += 1
        start_idx ||= i
      elsif ch == "}"
        depth -= 1 if depth > 0
        if depth == 0 && start_idx
          candidate = s[start_idx..i]
          begin
            return JSON.parse(candidate)
          rescue JSON::ParserError
            # keep scanning
          ensure
            start_idx = nil
          end
        end
      end
    end
    nil
  end

  # Optional: pre-compute per-emotion aggregates for USER turns only.
  def compute_user_emotion_stats(transcript)
    stats = Hash.new { |h, k| h[k] = { "count" => 0, "sum" => 0.0 } }

    Array(transcript).each do |e|
      next unless e["role"].to_s.downcase == "user"

      if e["emotions_all"].is_a?(Hash) && e["emotions_all"].any?
        e["emotions_all"].each do |name, score|
          next unless score.is_a?(Numeric)
          stats[name]["count"] += 1
          stats[name]["sum"]   += score
        end
      elsif e["emotions_top3"].is_a?(Array)
        e["emotions_top3"].each do |x|
          name  = x["name"]
          score = x["score"]
          next unless name && score.is_a?(Numeric)
          stats[name]["count"] += 1
          stats[name]["sum"]   += score
        end
      end
    end

    means = stats.transform_values { |v| v.merge("mean" => (v["count"] > 0 ? (v["sum"] / v["count"]).round(4) : 0.0)) }
    { "user_emotions" => means }
  end
end