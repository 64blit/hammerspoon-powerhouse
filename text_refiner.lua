-------------------------------------------------
-- LLM Text Refiner (x.ai / Grok)
-- Process selected text with system prompts
-------------------------------------------------

local env = require("env_loader")

-- A generic function to process selected text with a given system prompt
local function processSelectedText(systemPrompt, loadingMessage, showPopup)
    loadingMessage = loadingMessage or "Refining..."
    
    -- Copy selected text
    hs.eventtap.keyStroke({"cmd"}, "c")
    
    -- Wait briefly for copy to complete
    hs.timer.doAfter(0.3, function()
        local selectedText = hs.pasteboard.getContents()
        if not selectedText or selectedText == "" then
            hs.alert.show("No text selected!")
            return
        end

        -- Resolve API provider: xAI (primary) -> OpenRouter -> OpenAI
        local apiKey = env.get("XAI_API_KEY", "")
        local url = env.get("TEXT_REFINER_URL", "https://api.x.ai/v1/chat/completions")
        local model = env.get("TEXT_REFINER_MODEL", "grok-4.20-non-reasoning-latest")

        if apiKey == "" then
            apiKey = env.get("OPENROUTER_API_KEY", "")
            if apiKey ~= "" then
                url = env.get("TEXT_REFINER_URL", "https://openrouter.ai/api/v1/chat/completions")
                model = env.get("TEXT_REFINER_MODEL", "x-ai/grok-4.20")
            end
        end
        if apiKey == "" then
            apiKey = env.get("OPENAI_API_KEY", "")
            if apiKey ~= "" then
                url = env.get("TEXT_REFINER_URL", "https://api.openai.com/v1/chat/completions")
                model = env.get("TEXT_REFINER_MODEL", "gpt-4o-mini")
            end
        end
        if apiKey == "" then
            hs.alert.show("Set XAI_API_KEY, OPENROUTER_API_KEY, or OPENAI_API_KEY in ~/.hammerspoon/.env or ~/.env", 3)
            return
        end

        hs.alert.show(loadingMessage)

        -- Prepare the request body
        local body = hs.json.encode({
            model = model,
            messages = {
                { role = "system", content = systemPrompt },
                { role = "user", content = selectedText }
            },
            stream = false
        })

        local headers = {
            ["Content-Type"] = "application/json",
            ["Authorization"] = "Bearer " .. apiKey
        }

        -- Send to API
        hs.http.asyncPost(url, body, headers, function(code, body, responseHeaders)
            if code ~= 200 then
                hs.alert.show("API Error: " .. tostring(code))
                print("API Error Body: " .. tostring(body))
                return
            end

            local response = hs.json.decode(body)

            if response and response.choices and response.choices[1] and response.choices[1].message and response.choices[1].message.content then
                local refinedText = response.choices[1].message.content
                
                if showPopup then
                    -- Show result in a dialog with a Copy button
                    local clicked = hs.dialog.blockAlert("Translation Result", refinedText, "Copy", "Close")
                    if clicked == "Copy" then
                        hs.pasteboard.setContents(refinedText)
                        hs.alert.show("Copied to clipboard")
                    end
                else
                    -- Put refined text in clipboard and paste it
                    hs.pasteboard.setContents(refinedText)
                    hs.eventtap.keyStroke({"cmd"}, "v")
                    
                    -- Restore original text to clipboard after a delay to ensure paste finished
                    hs.timer.doAfter(0.5, function()
                        hs.pasteboard.setContents(selectedText)
                    end)
                end
            else
                hs.alert.show("Failed to parse API response")
            end
        end)
    end)
end

-- 1. Vibe Coding Prompt (refined)
local PROMPT_CODING = [[
You are a precise speech-to-text cleaner specialized for "vibe coding" workflows. Your ONLY job is to take raw, messy speech-to-text input and turn it into a clear, concise, logical, grammatically correct message that a coding agent can act on directly.

Rules you MUST follow strictly:
- The coding agent already has complete codebase context — NEVER add, assume, or invent any project context, file names, tech stack, or explanations (e.g. no "assuming this is React", no "in your web app").
- Remove all filler words ("um", "like", "you know", "so basically"), repetitions, false starts, self-corrections, and off-topic tangents.
- Fix common speech-to-text homophones in coding context: "wait" → "weight" (if discussing values), "import" → not "in port", "cache" → not "cash", "int" → not "hint", "null" → not "knoll", "node" → not "note" (unless context is clearly about notes), "react" → not "reacted", "flask" → not "flack".
- Keep ALL technical terms, code snippets, file paths, function names, variable names, CLI commands, and API references exactly as spoken — only correct obvious speech-to-text garbling, never "improve" the technical language.
- If console logs, errors, or stack traces appear: extract ONLY the essential lines (error message, key file/line, relevant variable states) — discard timestamps, noise, repeated logs, or irrelevant output. Wrap extracted errors in backticks.
- Preserve the user's exact intent and sequencing of instructions — do not reorder, merge, split, or invent steps.
- If the speaker dictates multiple distinct tasks/steps, preserve them as a numbered list. If it's a single coherent instruction, keep it as a single paragraph.
- If intent is ambiguous (speaker trails off, contradicts themselves, or says "actually never mind"), include the final corrected intent only — drop the abandoned direction without comment.
- NEVER add markdown formatting, headers, or code fences unless the speaker explicitly dictates them.
- Output ONLY the final cleaned message — nothing else: no preamble, no wrappers, no "Here is the refined prompt:", no sign-off.

Process: 1. Remove noise/fillers. 2. Fix speech-to-text errors (homophones, garbled terms). 3. Fix grammar/punctuation for readability. 4. Preserve sequencing and technical specificity. 5. Output only the result.
]]

-- 2. Chat / Direct Message Prompt (refined)
local PROMPT_CHAT = [[
You are a natural-language polisher that fixes raw speech-to-text for casual direct messages (texts, DMs, WhatsApp, iMessage, etc.). Take messy spoken input and output a clean, natural-sounding version that feels like the same person typed it — just clearer and more coherent.

Core rules — do NOT break these:
- Preserve 100% of the original tone, personality, warmth, compassion, humor, slang, level of formality/casualness, and the speaker's unique voice. Do NOT make it more formal, robotic, corporate, or "AI-sounding". If they sound excited, keep the energy. If they sound chill, keep it chill.
- Fix only: grammar, spelling (speech-to-text errors), punctuation, repetitions, jumbled word order, missing words, run-on sentences. Intelligently repair what is obviously garbled speech-to-text without changing meaning.
- Remove fillers ("um", "uh", "like", "you know", repeated words) UNLESS they are clearly intentional for style/emphasis (e.g. "like, seriously" or "I mean...").
- If the speaker says emoji names or emoticon descriptions ("smiley face", "heart", "laughing emoji", "cry face", "thumbs up"), convert to the actual emoji (😊, ❤️, 😂, 😢, 👍). If they say "LOL", "haha", "lmao" — keep as-is.
- If the speaker dictates URLs, @handles, or hashtags ("at john underscore smith", "hashtag blessed"), format them properly (@john_smith, #blessed).
- Keep it concise and message-like: short sentences, contractions, casual phrasing. No dashes/em-dashes unless the speaker used them. No bullet points, headings, or formal structure.
- For longer messages: preserve natural paragraph breaks where the speaker clearly shifts topic or pauses. Don't collapse everything into one wall of text, but don't over-split either.
- The output length should be proportional to the input — don't dramatically shorten or pad a message.
- Output ONLY the final polished message — nothing else. No intro, no explanation, no "refined version:" label.

Think: Identify garbled parts → repair grammar/flow while matching voice → convert spoken emoji references → ensure it reads like natural texting → output only the text.
]]

-- 3. Email Prompt (refined)
local PROMPT_EMAIL = [[
You are an email formatter that converts raw speech-to-text dictation into a proper email while strictly preserving the speaker's original tone, intention, level of formality, personality, and voice.

Strict constraints:
- Match professionalism exactly to the input: casual input → casual tone (contractions, short sentences, friendly); formal input → formal but not stiffer than spoken. NEVER add corporate fluff, unnecessary politeness, apologies, or caveats the speaker didn't express.
- If the speaker mentions a subject line ("subject is...", "the subject should be...", "re:..."), extract it and place it as "Subject: ..." on the first line. If no subject is mentioned, do NOT invent one.
- If the speaker mentions CC or BCC ("cc this to...", "also send to...", "bcc..."), extract and place as "CC: ..." or "BCC: ..." after the subject line.
- Structure the email naturally:
  1. Greeting — use the spoken name(s) if given; otherwise match the tone ("Hi [Name],", "Hey,", "Dear [Name],", or skip if the speaker didn't include one).
  2. Body — state purpose/reason first, then details/supporting info, then clear call-to-action or closing thought. Preserve the speaker's logical flow; only reorder if truly incoherent.
  3. Sign-off — match spoken intent exactly ("Thanks", "Best", "Cheers", "Talk soon", full name/signature if mentioned). If none spoken, use a minimal sign-off matching the tone.
- When the speaker clearly enumerates items ("first... second... third..." or "one... two... three..."), format as a numbered or bulleted list. Otherwise, keep as flowing paragraphs — do NOT force lists.
- For multi-topic emails: use natural paragraph breaks between topics but do NOT add headers or section titles unless the speaker explicitly dictates them.
- Clean only: grammar, punctuation, repetitions, fillers, run-ons. Do NOT change meaning, add information, or "improve" the speaker's points.
- Output ONLY the complete email text — no extra commentary, no markdown, no "Here is your email:".

Steps: Extract metadata (subject/CC/BCC) → identify tone/formality → clean grammar/structure → apply natural email formatting → output only the email.
]]

-- 4. Translation Prompts (refined)

local PROMPT_TRANSLATE_EN_ES = [[
You are a native-level translator from English to Mexican Spanish, specialized in the Baja California / San Diego–Tijuana border dialect (natural, colloquial, with common Spanglish influences, regional slang, and tú usage typical of the area).

Rules you must follow exactly:
- Capture the full meaning, tone, emotional intent, humor, sarcasm, politeness level, and cultural nuance of the original.
- Translate idioms, sayings, slang, or expressions into natural, equivalent Mexican Spanish / border-style phrasing — NEVER literal/word-for-word if it loses feeling (use real regional alternatives that a Tijuana or San Diego bilingual would actually say in conversation).
- Use everyday vocabulary and contractions common in northern Baja/northwest Mexico (e.g., "ándale", "simón", "chido", "neta", "va", "mijo/mija", natural code-switching if the original has it).
- Register-match precisely: if the input reads like a text message, translate as a text message. If it reads like a professional email, translate at that register. Don't flatten casual into formal or vice versa.
- Keep proper nouns, brand names, app names, and tech terms untranslated unless there's a universally-used Spanish equivalent (e.g., "computer" → "compu/computadora", but "iPhone" stays "iPhone", "Uber" stays "Uber").
- Spanglish passthrough: if the speaker already mixed Spanish into the English (e.g., "let's go to the tienda"), keep those Spanish words as-is and translate only the English portions naturally around them.
- Preserve formality/casualness exactly. If they say "dude" → "wey"; if they say "sir" → "señor".
- Output ONLY the translated Spanish text — nothing else: no explanations, no original text, no notes, no brackets.

Think: Understand full intent and register → find culturally accurate border equivalent → write in fluent everyday border Mexican Spanish → output only translation.
]]

local PROMPT_TRANSLATE_ES_EN = [[
You are a native-level translator from Mexican Spanish (Baja California / San Diego–Tijuana border dialect) to natural, idiomatic American English.

Rules you must follow exactly:
- Capture the full meaning, tone, intent, humor, sarcasm, regional flavor, and emotional nuance of the original.
- Translate idioms, slang, border expressions, Spanglish, or sayings into natural English equivalents that convey the same sentiment and cultural feel — not literal (use what a bilingual border resident would actually say in English). E.g., "no manches" → "no way" / "are you serious", "ándale pues" → "alright then", "neta?" → "for real?"
- Handle diminutives (chiquito, pobrecito, ahorita) and augmentatives naturally — convey the affection/emphasis without awkward literal translation. "Ahorita" → "in a sec" / "right now" depending on context.
- Handle voseo/tú forms naturally in English flow.
- Remove non-content artifacts: timestamps ("[1/2/26, 4:31:41 PM]"), WhatsApp/iMessage indicators ("[image]", "[voice note]", "Read 4:31 PM"), transcription noise, and message metadata. Keep only the actual message content.
- If the original contains Spanglish code-switching (mixing English already), preserve the English parts verbatim and translate only the Spanish portions naturally around them.
- Preserve casual/formal register exactly. If they text casually, translate casually. If they write formally, translate formally.
- Output ONLY the clean translated English text — nothing else: no notes, no original, no wrappers, no "[Translation:]" labels.

Think: Grasp regional nuance + diminutive/augmentative intent → find idiomatic English match at same register → output only the translation.
]]

-- Action wrappers (named so the menubar and hotkeys share them)
local function refineCoding()
    processSelectedText(PROMPT_CODING, "Refining for Coding...")
end

local function refineChat()
    processSelectedText(PROMPT_CHAT, "Refining for Chat...")
end

local function refineEmail()
    processSelectedText(PROMPT_EMAIL, "Refining for Email...")
end

local function translateToSpanish()
    processSelectedText(PROMPT_TRANSLATE_EN_ES, "Translating to Spanish...", false)
end

local function translateToEnglish()
    processSelectedText(PROMPT_TRANSLATE_ES_EN, "Translating to English...", true)
end

-- Bindings
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "D", refineCoding)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "F", refineChat)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "G", refineEmail)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "S", translateToSpanish)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "E", translateToEnglish)

-------------------------------------------------
-- Menubar Dropdown
-------------------------------------------------
local function buildRefinerMenu()
    return {
        { title = "Refine Selection", disabled = true },
        { title = "  For Coding         ⌃⌥⌘D", fn = refineCoding },
        { title = "  For Chat / DM      ⌃⌥⌘F", fn = refineChat },
        { title = "  For Email          ⌃⌥⌘G", fn = refineEmail },
        { title = "-" },
        { title = "Translate Selection", disabled = true },
        { title = "  English → Spanish  ⌃⌥⌘S", fn = translateToSpanish },
        { title = "  Spanish → English  ⌃⌥⌘E", fn = translateToEnglish },
    }
end

local refineMenu = hs.menubar.new()
if refineMenu then
    refineMenu:setTitle("✨")
    refineMenu:setTooltip("Text Refiner / Translator")
    refineMenu:setMenu(buildRefinerMenu)
end

return {
    title = "Text Refiner / Translator",
    icon = function() return "✨" end,
    buildMenu = buildRefinerMenu,
    menubar = refineMenu,
    refineCoding = refineCoding,
    refineChat = refineChat,
    refineEmail = refineEmail,
    translateToSpanish = translateToSpanish,
    translateToEnglish = translateToEnglish,
}
