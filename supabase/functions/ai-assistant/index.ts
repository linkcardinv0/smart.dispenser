import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(status: number, body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "Method not allowed." });
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization) {
    return jsonResponse(401, { error: "Authentication is required." });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const geminiApiKey = Deno.env.get("GEMINI_API_KEY");
  if (!supabaseUrl || !supabaseAnonKey || !geminiApiKey) {
    console.error("AI function is missing required server configuration.");
    return jsonResponse(500, { error: "AI service is not configured." });
  }

  const supabase = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: authError } = await supabase.auth.getUser();
  if (authError || !userData.user) {
    return jsonResponse(401, { error: "A valid user session is required." });
  }

  let body: unknown;
  try {
    body = await request.json();
  } catch {
    return jsonResponse(400, { error: "Request body must be valid JSON." });
  }

  if (
    typeof body !== "object" ||
    body === null ||
    !("prompt" in body) ||
    typeof body.prompt !== "string"
  ) {
    return jsonResponse(400, { error: "A text prompt is required." });
  }

  const prompt = body.prompt.trim();
  if (!prompt || prompt.length > 8000) {
    return jsonResponse(400, {
      error: "Prompt must contain between 1 and 8000 characters.",
    });
  }

  let geminiResponse: Response;
  try {
    geminiResponse = await fetch(
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.6-flash:generateContent",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-goog-api-key": geminiApiKey,
        },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: { temperature: 0.4, maxOutputTokens: 600 },
        }),
        signal: AbortSignal.timeout(30000),
      },
    );
  } catch (error) {
    console.error("Gemini request could not be completed:", error);
    return jsonResponse(502, { error: "AI provider could not be reached." });
  }

  if (!geminiResponse.ok) {
    console.error("Gemini returned HTTP status", geminiResponse.status);
    return jsonResponse(502, {
      error: "AI provider rejected the request. Check the server API key.",
    });
  }

  const result: unknown = await geminiResponse.json();
  if (
    typeof result !== "object" ||
    result === null ||
    !("candidates" in result) ||
    !Array.isArray(result.candidates)
  ) {
    console.error("Gemini returned an unexpected response.");
    return jsonResponse(502, { error: "AI provider returned an invalid response." });
  }

  const candidate = result.candidates[0];
  if (
    typeof candidate !== "object" ||
    candidate === null ||
    !("content" in candidate) ||
    typeof candidate.content !== "object" ||
    candidate.content === null ||
    !("parts" in candidate.content) ||
    !Array.isArray(candidate.content.parts)
  ) {
    return jsonResponse(502, { error: "AI provider returned no answer." });
  }

  const text = candidate.content.parts
    .map((part: unknown) =>
      typeof part === "object" &&
        part !== null &&
        "text" in part &&
        typeof part.text === "string"
        ? part.text
        : ""
    )
    .join("")
    .trim();

  if (!text) {
    return jsonResponse(502, { error: "AI provider returned no answer." });
  }
  return jsonResponse(200, { text });
});
