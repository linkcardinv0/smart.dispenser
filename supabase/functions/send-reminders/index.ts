// supabase/functions/send-reminders/index.ts
import { createClient } from "npm:@supabase/supabase-js@2";
import { JWT } from "npm:google-auth-library@9";

const sa = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req) => {
  if (req.headers.get("x-cron-secret") !== Deno.env.get("CRON_SECRET")) {
    return new Response("forbidden", { status: 403 });
  }

  // Masa Malaysia sekarang "HH:mm"
  const hhmm = new Date().toLocaleTimeString("en-GB", {
    timeZone: "Asia/Kuala_Lumpur", hour: "2-digit", minute: "2-digit", hour12: false,
  });

  const { data: meds, error } = await supabase
    .from("medications")
    .select("user_id, medication_name, slot_number, scheduled_time")
    .in("scheduled_time", [hhmm, `${hhmm}:00`]);
  if (error) return new Response(error.message, { status: 500 });

  const due = (meds ?? []).filter((m) => {
    const n = (m.medication_name ?? "").trim();
    return n !== "" && n !== "Empty" && n !== "Unassigned";
  });
  if (!due.length) return new Response(`none at ${hhmm}`);

  const jwt = new JWT({
    email: sa.client_email,
    key: sa.private_key,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const { token: accessToken } = await jwt.getAccessToken();

  let sent = 0;
  for (const m of due) {
    const { data: tokens } = await supabase
      .from("fcm_tokens").select("token").eq("user_id", m.user_id);

    for (const t of tokens ?? []) {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: t.token,
              notification: {
                title: "⏰ MASA MAKAN UBAT!",
                body: `Sila ambil ${m.medication_name} dari Slot ${m.slot_number}`,
              },
              webpush: { headers: { Urgency: "high", TTL: "300" } },
            },
          }),
        },
      );
      if (res.ok) sent++;
      else if (res.status === 404) {
        await supabase.from("fcm_tokens").delete().eq("token", t.token);
      } else {
        console.error("FCM error", res.status, await res.text());
      }
    }
  }
  return new Response(`time ${hhmm}: sent ${sent}`);
});