# AI function deployment

The Flutter web app calls the `ai-assistant` Supabase Edge Function. Keep the
Gemini API key on the server; do not add it to `.env`, Flutter assets, source
code, or GitHub Pages build arguments.

1. Revoke any Gemini API key that was previously committed or included in a
   web build, then create a replacement key.
2. Link this project to your Supabase project:

   ```sh
   supabase login
   supabase link --project-ref YOUR_PROJECT_REF
   ```

3. Store the replacement key as a Supabase Function secret and deploy the
   function:

   ```sh
   supabase secrets set GEMINI_API_KEY=YOUR_NEW_GEMINI_API_KEY
   supabase functions deploy ai-assistant
   ```

   `SUPABASE_URL` and `SUPABASE_ANON_KEY` are provided to deployed functions
   by Supabase. The function verifies the caller's Supabase user session.
4. Rebuild and redeploy the Flutter web app to GitHub Pages. No Gemini key is
   needed when building the Flutter client.

The function uses Google's `gemini-3.6-flash` model. Check the Gemini API model
availability for your account if the provider reports that the model is
unavailable.
