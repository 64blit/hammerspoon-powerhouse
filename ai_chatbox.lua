local M = {}
local webview = require("hs.webview")
local env = require("env_loader")

local aiChatboxWindow = nil

local HTML_CONTENT = [=[
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<script src="https://cdn.jsdelivr.net/npm/marked/marked.min.js"></script>
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/styles/github-dark.min.css">
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/11.9.0/highlight.min.js"></script>
<style>
  :root {
      --bg: #1e1e1e;
      --bg-input: #2d2d2d;
      --border: #444;
      --accent: #3b82f6;
      --accent-hover: #2563eb;
      --text: #f3f4f6;
      --text-dim: #9ca3af;
      --code-bg: #0d1117;
      --inline-code-bg: #343942;
      --blockquote-border: #3b82f6;
      --table-border: #3a3a3a;
      --table-header-bg: #2a2a2a;
      --table-row-alt: #232323;
      --link: #60a5fa;
      --user-bg: #1d4ed8;
      --assistant-bg: #262626;
  }
  body {
    background-color: var(--bg);
    color: var(--text);
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    height: 100vh;
    box-sizing: border-box;
    overflow: hidden;
  }

  /* ── Header ── */
  .header {
    display: flex;
    gap: 8px;
    padding: 10px 16px;
    border-bottom: 1px solid var(--border);
    align-items: center;
    justify-content: flex-end;
    flex-shrink: 0;
  }
  input, select, textarea, button {
    background-color: var(--bg-input);
    color: var(--text);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 8px 10px;
    font-size: 13px;
    outline: none;
    transition: border-color 0.2s;
  }
  input:focus, select:focus, textarea:focus {
    border-color: var(--accent);
  }
  select { flex: 1; min-width: 0; }
  input#customModel { flex: 1; display: none; min-width: 0; }
  .new-chat-btn {
    background-color: #374151;
    color: var(--text);
    cursor: pointer;
    font-weight: 600;
    border: 1px solid var(--border);
    padding: 8px 12px;
    font-size: 13px;
    white-space: nowrap;
    transition: background-color 0.2s;
  }
  .new-chat-btn:hover { background-color: #4b5563; }
  
  /* ── Chat Area ── */
  #chatArea {
    flex: 1;
    overflow-y: auto;
    padding: 16px;
    display: flex;
    flex-direction: column;
    gap: 4px;
  }
  .empty-state {
    display: flex;
    align-items: center;
    justify-content: center;
    flex: 1;
    color: var(--text-dim);
    font-size: 15px;
    text-align: center;
    line-height: 1.6;
  }

  /* ── Message Bubbles ── */
  .msg { display: flex; flex-direction: column; max-width: 88%; animation: fadeIn 0.15s ease; }
  .msg.user { align-self: flex-end; }
  .msg.assistant { align-self: flex-start; }
  .msg-label {
    font-size: 11px;
    font-weight: 600;
    color: var(--text-dim);
    margin-bottom: 3px;
    padding: 0 4px;
  }
  .msg.user .msg-label { text-align: right; }
  .msg-body {
    padding: 10px 14px;
    border-radius: 12px;
    line-height: 1.6;
    font-size: 14px;
    word-wrap: break-word;
    overflow-wrap: break-word;
  }
  .msg.user .msg-body {
    background-color: var(--user-bg);
    color: #fff;
    border-bottom-right-radius: 4px;
  }
  .msg.assistant .msg-body {
    background-color: var(--assistant-bg);
    border: 1px solid #333;
    border-bottom-left-radius: 4px;
  }
  @keyframes fadeIn { from { opacity: 0; transform: translateY(6px); } to { opacity: 1; transform: translateY(0); } }

  /* ── Input Area ── */
  .input-area {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: 10px 16px;
    border-top: 1px solid var(--border);
    flex-shrink: 0;
  }
  .model-row {
    display: flex;
    gap: 6px;
  }
  .prompt-row {
    display: flex;
    gap: 8px;
  }
  textarea {
    flex: 1;
    resize: none;
    height: 48px;
    font-size: 14px;
  }
  .send-btn {
    background-color: var(--accent);
    color: white;
    cursor: pointer;
    font-weight: bold;
    border: none;
    padding: 0 20px;
    transition: background-color 0.2s;
    font-size: 14px;
  }
  .send-btn:hover { background-color: var(--accent-hover); }
  .send-btn:disabled { opacity: 0.6; cursor: not-allowed; }

  /* ── Markdown in assistant bubbles ── */
  .msg.assistant .msg-body h1, .msg.assistant .msg-body h2, .msg.assistant .msg-body h3,
  .msg.assistant .msg-body h4, .msg.assistant .msg-body h5, .msg.assistant .msg-body h6 {
    margin: 0.8em 0 0.4em;
    font-weight: 600;
    line-height: 1.3;
  }
  .msg.assistant .msg-body h1 { font-size: 1.4em; border-bottom: 1px solid var(--border); padding-bottom: 0.25em; }
  .msg.assistant .msg-body h2 { font-size: 1.2em; border-bottom: 1px solid var(--border); padding-bottom: 0.2em; }
  .msg.assistant .msg-body h3 { font-size: 1.1em; }
  .msg.assistant .msg-body h1:first-child,
  .msg.assistant .msg-body h2:first-child,
  .msg.assistant .msg-body h3:first-child { margin-top: 0; }
  .msg.assistant .msg-body p { margin: 0.5em 0; }
  .msg.assistant .msg-body p:first-child { margin-top: 0; }
  .msg.assistant .msg-body p:last-child { margin-bottom: 0; }
  .msg.assistant .msg-body a { color: var(--link); text-decoration: none; }
  .msg.assistant .msg-body a:hover { text-decoration: underline; }

  .msg.assistant .msg-body code {
    font-family: "SF Mono", "Fira Code", "Cascadia Code", Menlo, Consolas, monospace;
    font-size: 0.88em;
  }
  .msg.assistant .msg-body :not(pre) > code {
    background-color: var(--inline-code-bg);
    padding: 0.15em 0.4em;
    border-radius: 4px;
  }
  .msg.assistant .msg-body pre {
    background-color: var(--code-bg);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 12px 58px 12px 12px;
    overflow-x: auto;
    margin: 0.6em 0;
    position: relative;
  }
  .msg.assistant .msg-body pre code {
    background: none;
    padding: 0;
    font-size: 0.85em;
    line-height: 1.5;
  }
  .msg.assistant .msg-body pre .copy-btn {
    position: absolute;
    top: 6px;
    right: 6px;
    background: #3a3f47;
    border: 1px solid #555;
    color: #ccc;
    padding: 3px 8px;
    border-radius: 4px;
    cursor: pointer;
    font-size: 11px;
    opacity: 0;
    transition: opacity 0.15s;
  }
  .msg.assistant .msg-body pre:hover .copy-btn { opacity: 1; }
  .msg.assistant .msg-body pre .copy-btn:hover { background: #4a4f57; color: #fff; }

  .msg.assistant .msg-body blockquote {
    border-left: 3px solid var(--blockquote-border);
    margin: 0.6em 0;
    padding: 0.3em 0.8em;
    background-color: rgba(59, 130, 246, 0.06);
    border-radius: 0 6px 6px 0;
  }
  .msg.assistant .msg-body blockquote p { margin: 0.2em 0; }
  .msg.assistant .msg-body ul, .msg.assistant .msg-body ol {
    margin: 0.4em 0;
    padding-left: 1.6em;
  }
  .msg.assistant .msg-body li { margin: 0.2em 0; }
  .msg.assistant .msg-body table {
    border-collapse: collapse;
    width: 100%;
    margin: 0.6em 0;
    font-size: 0.92em;
  }
  .msg.assistant .msg-body th, .msg.assistant .msg-body td {
    border: 1px solid var(--table-border);
    padding: 6px 10px;
    text-align: left;
  }
  .msg.assistant .msg-body th { background-color: var(--table-header-bg); font-weight: 600; }
  .msg.assistant .msg-body tr:nth-child(even) { background-color: var(--table-row-alt); }
  .msg.assistant .msg-body hr {
    border: none;
    border-top: 1px solid var(--border);
    margin: 1em 0;
  }
  .msg.assistant .msg-body img { max-width: 100%; border-radius: 6px; }

  /* Scrollbar */
  #chatArea::-webkit-scrollbar { width: 6px; }
  #chatArea::-webkit-scrollbar-track { background: transparent; }
  #chatArea::-webkit-scrollbar-thumb { background: #444; border-radius: 3px; }
  #chatArea::-webkit-scrollbar-thumb:hover { background: #555; }

  /* Streaming cursor */
  .streaming-cursor::after {
    content: "▌";
    animation: blink 0.8s step-end infinite;
    color: var(--accent);
    font-weight: bold;
  }
  @keyframes blink { 50% { opacity: 0; } }
</style>
</head>
<body>

<div class="header">
  <button class="new-chat-btn" onclick="newChat()">✦ New Chat</button>
</div>

<div id="chatArea">
  <div class="empty-state">Ask anything — your conversation<br>history stays in context ✨</div>
</div>

<div class="input-area">
  <div class="model-row">
    <select id="modelSelect" onchange="toggleCustomModel()">
      <option value="openrouter/auto" selected>Auto (Best Available)</option>
      <option value="" disabled>── Anthropic ──</option>
      <option value="anthropic/claude-opus-4.6">Claude Opus 4.6 ⭐ (coding/agents)</option>
      <option value="anthropic/claude-sonnet-4.6">Claude Sonnet 4.6</option>
      <option value="" disabled>── OpenAI ──</option>
      <option value="openai/gpt-5.4-pro">GPT-5.4 Pro ⭐ (best reasoning)</option>
      <option value="openai/gpt-5.2">GPT-5.2</option>
      <option value="openai/gpt-5-mini">GPT-5 Mini (fast)</option>
      <option value="openai/gpt-4.1-mini">GPT-4.1 Mini (fast)</option>
      <option value="openai/o3">o3 (deep thinking)</option>
      <option value="" disabled>── Google ──</option>
      <option value="google/gemini-3-flash-preview">Gemini 3 Flash Preview ⭐ (fast)</option>
      <option value="google/gemini-2.5-pro">Gemini 2.5 Pro</option>
      <option value="google/gemini-2.5-flash-lite">Gemini 2.5 Flash Lite (budget)</option>
      <option value="" disabled>── xAI ──</option>
      <option value="x-ai/grok-4.20">Grok 4.20 ⭐ (fast)</option>
      <option value="x-ai/grok-4.5">Grok 4.5</option>
      <option value="" disabled>── Others ──</option>
      <option value="deepseek/deepseek-v4-flash">DeepSeek V4 Flash</option>
      <option value="deepseek/deepseek-v3.2">DeepSeek V3.2</option>
      <option value="minimax/minimax-m2.5">MiniMax M2.5</option>
      <option value="" disabled>── 🌐 With Internet Search ──</option>
      <option value="openai/gpt-5.2:online">GPT-5.2 :online</option>
      <option value="openai/gpt-4.1-mini:online">GPT-4.1 Mini :online</option>
      <option value="google/gemini-3-flash-preview:online">Gemini 3 Flash :online</option>
      <option value="x-ai/grok-4.20:online">Grok 4.20 :online</option>
      <option value="anthropic/claude-sonnet-4.6:online">Claude Sonnet 4.6 :online</option>
      <option value="perplexity/sonar-pro">Perplexity Sonar Pro (search-native)</option>
      <option value="custom">Custom...</option>
    </select>
    <input type="text" id="customModel" placeholder="e.g. meta-llama/llama-3-70b-instruct">
  </div>
  <div class="prompt-row">
    <textarea id="prompt" placeholder="Ask anything... (Cmd+Enter to send)" autofocus></textarea>
    <button class="send-btn" id="sendBtn" onclick="sendRequest()">Send</button>
  </div>
</div>

<script>
  let apiKey = "API_KEY_PLACEHOLDER";
  let messages = []; // { role: "user"|"assistant", content: "..." }
  let isStreaming = false;

  // Configure marked
  marked.setOptions({
    highlight: function(code, lang) {
      if (lang && hljs.getLanguage(lang)) {
        try { return hljs.highlight(code, { language: lang }).value; } catch(e) {}
      }
      try { return hljs.highlightAuto(code).value; } catch(e) {}
      return code;
    },
    breaks: true,
    gfm: true
  });

  function escapeHtml(text) {
    const div = document.createElement("div");
    div.textContent = text;
    return div.innerHTML;
  }

  // Add copy buttons to code blocks inside an element
  function addCopyButtons(el) {
    el.querySelectorAll("pre code").forEach(function(block) {
      if (block.parentElement.querySelector(".copy-btn")) return;
      const btn = document.createElement("button");
      btn.className = "copy-btn";
      btn.textContent = "Copy";
      btn.onclick = function(e) {
        e.stopPropagation();
        navigator.clipboard.writeText(block.textContent).then(function() {
          btn.textContent = "Copied!";
          setTimeout(function() { btn.textContent = "Copy"; }, 1500);
        });
      };
      block.parentElement.appendChild(btn);
    });
  }

  // Render the full chat from the messages array
  function renderChat() {
    const chatArea = document.getElementById("chatArea");
    chatArea.innerHTML = "";
    if (messages.length === 0) {
      chatArea.innerHTML = '<div class="empty-state">Ask anything — your conversation<br>history stays in context ✨</div>';
      return;
    }
    messages.forEach(function(msg, i) {
      const wrapper = document.createElement("div");
      wrapper.className = "msg " + msg.role;
      const label = document.createElement("div");
      label.className = "msg-label";
      label.textContent = msg.role === "user" ? "You" : "AI";
      const body = document.createElement("div");
      body.className = "msg-body";
      if (msg.role === "assistant") {
        body.innerHTML = marked.parse(msg.content);
        addCopyButtons(body);
      } else {
        body.innerHTML = escapeHtml(msg.content);
      }
      wrapper.appendChild(label);
      wrapper.appendChild(body);
      chatArea.appendChild(wrapper);
    });
    chatArea.scrollTop = chatArea.scrollHeight;
  }

  // Append a user message bubble
  function appendUserBubble(text) {
    const chatArea = document.getElementById("chatArea");
    // Remove empty state if present
    const empty = chatArea.querySelector(".empty-state");
    if (empty) empty.remove();

    const wrapper = document.createElement("div");
    wrapper.className = "msg user";
    const label = document.createElement("div");
    label.className = "msg-label";
    label.textContent = "You";
    const body = document.createElement("div");
    body.className = "msg-body";
    body.innerHTML = escapeHtml(text);
    wrapper.appendChild(label);
    wrapper.appendChild(body);
    chatArea.appendChild(wrapper);
    chatArea.scrollTop = chatArea.scrollHeight;
  }

  // Create or update the streaming assistant bubble
  function createAssistantBubble() {
    const chatArea = document.getElementById("chatArea");
    const wrapper = document.createElement("div");
    wrapper.className = "msg assistant";
    wrapper.id = "streaming-msg";
    const label = document.createElement("div");
    label.className = "msg-label";
    label.textContent = "AI";
    const body = document.createElement("div");
    body.className = "msg-body streaming-cursor";
    body.id = "streaming-body";
    wrapper.appendChild(label);
    wrapper.appendChild(body);
    chatArea.appendChild(wrapper);
    chatArea.scrollTop = chatArea.scrollHeight;
    return body;
  }

  // Debounced render for streaming
  let renderTimer = null;
  function debouncedStreamRender(bodyEl, text) {
    if (renderTimer) clearTimeout(renderTimer);
    renderTimer = setTimeout(function() {
      bodyEl.innerHTML = marked.parse(text);
      addCopyButtons(bodyEl);
      // keep cursor class during stream
      bodyEl.classList.add("streaming-cursor");
      document.getElementById("chatArea").scrollTop = document.getElementById("chatArea").scrollHeight;
    }, 40);
  }

  function newChat() {
    if (isStreaming) return;
    messages = [];
    renderChat();
    document.getElementById("prompt").focus();
  }
  
  function toggleCustomModel() {
    const select = document.getElementById("modelSelect");
    const custom = document.getElementById("customModel");
    if (select.value === "custom") {
      select.style.flex = "0 0 160px";
      custom.style.display = "block";
      custom.focus();
    } else {
      select.style.flex = "1";
      custom.style.display = "none";
    }
  }

  document.getElementById("prompt").addEventListener("keydown", function(e) {
    if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) {
      e.preventDefault();
      sendRequest();
    }
  });

  async function sendRequest() {
    if (isStreaming) return;
    const sendBtn = document.getElementById("sendBtn");
    const promptEl = document.getElementById("prompt");
    const select = document.getElementById("modelSelect");
    const custom = document.getElementById("customModel");
    
    const promptText = promptEl.value.trim();
    if (!promptText) return;
    
    let model = select.value;
    if (model === "custom") {
      model = custom.value.trim();
      if (!model) {
        alert("Please enter a custom model name");
        return;
      }
    }

    // Add user message
    messages.push({ role: "user", content: promptText });
    appendUserBubble(promptText);
    promptEl.value = "";
    
    isStreaming = true;
    sendBtn.disabled = true;
    sendBtn.innerText = "...";

    // Create streaming assistant bubble
    const bodyEl = createAssistantBubble();
    
    try {
      // Build the messages payload with full history
      const apiMessages = messages.map(function(m) {
        return { role: m.role, content: m.content };
      });

      const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": "Bearer " + apiKey,
          "HTTP-Referer": "http://localhost:1234",
          "X-Title": "HS AI Box",
          "Content-Type": "application/json"
        },
        body: JSON.stringify({
          model: model,
          messages: apiMessages,
          stream: true
        })
      });

      if (!response.ok) {
        throw new Error("HTTP Error " + response.status + ": " + response.statusText);
      }

      const reader = response.body.getReader();
      const decoder = new TextDecoder("utf-8");
      let done = false;
      let streamedText = "";
      let buffer = "";

      while (!done) {
        const { value, done: doneReading } = await reader.read();
        done = doneReading;
        if (value) {
          buffer += decoder.decode(value, { stream: true });
          let boundary = buffer.indexOf('\n');
          
          while (boundary !== -1) {
            const line = buffer.slice(0, boundary).trim();
            buffer = buffer.slice(boundary + 1);
            
            if (line.startsWith("data: ") && line !== "data: [DONE]") {
              try {
                const data = JSON.parse(line.slice(6));
                const delta = data.choices && data.choices[0] && data.choices[0].delta;
                if (delta && delta.content) {
                  streamedText += delta.content;
                  debouncedStreamRender(bodyEl, streamedText);
                }
              } catch(e) {}
            }
            boundary = buffer.indexOf('\n');
          }
        }
      }
      // Final render
      bodyEl.classList.remove("streaming-cursor");
      bodyEl.innerHTML = marked.parse(streamedText);
      addCopyButtons(bodyEl);
      document.getElementById("chatArea").scrollTop = document.getElementById("chatArea").scrollHeight;

      // Save assistant message to history
      messages.push({ role: "assistant", content: streamedText });
    } catch (e) {
      bodyEl.classList.remove("streaming-cursor");
      bodyEl.innerHTML = "<p style='color:#f87171;'>Error: " + e.message + "</p>";
      // Remove the failed exchange from messages history
      messages.pop(); // remove user message since it failed
    } finally {
      isStreaming = false;
      sendBtn.disabled = false;
      sendBtn.innerText = "Send";
      promptEl.focus();
    }
  }
</script>
</body>
</html>
]=]

function M.toggleChatbox()
    if aiChatboxWindow then
        aiChatboxWindow:delete()
        aiChatboxWindow = nil
        return
    end

    local apiKey = env.get("OPENROUTER_API_KEY", "")
    if apiKey == "" then
        hs.alert.show("OPENROUTER_API_KEY not found in ~/.hammerspoon/.env or ~/.env", 3)
    end

    local rect = {x = 0, y = 0, w = 600, h = 500}
    local screen = hs.screen.mainScreen()
    local frame = screen:fullFrame()
    rect.x = frame.x + (frame.w - rect.w) / 2
    rect.y = frame.y + (frame.h - rect.h) / 2

    local prefs = {}
    prefs.developerExtrasEnabled = true
    aiChatboxWindow = webview.new(rect, prefs)
    
    aiChatboxWindow:windowStyle(1 | 2 | 8 | 16) -- TITLED | CLOSABLE | MINIATURIZABLE | RESIZABLE
    aiChatboxWindow:windowTitle("AI Chatbox (Cmd+Enter to send)")
    aiChatboxWindow:level(hs.drawing.windowLevels.floating)
    aiChatboxWindow:allowGestures(true)
    aiChatboxWindow:allowTextEntry(true)
    aiChatboxWindow:deleteOnClose(true)

    aiChatboxWindow:windowCallback(function(action)
        if action == "closing" then
            aiChatboxWindow = nil
        end
    end)

    local html = HTML_CONTENT:gsub("API_KEY_PLACEHOLDER", function() return apiKey end)
    aiChatboxWindow:html(html)
    aiChatboxWindow:show()
end

function M.window()
    return aiChatboxWindow
end

function M.openWithPrompt(promptText)
    if not aiChatboxWindow then
        M.toggleChatbox()
    else
        aiChatboxWindow:show()
        local win = aiChatboxWindow:hswindow()
        if win then win:focus() end
    end
    if promptText and promptText ~= "" then
        local encoded = hs.json.encode({ promptText })
        hs.timer.doAfter(0.55, function()
            if aiChatboxWindow then
                aiChatboxWindow:evaluateJavaScript(string.format(
                    "(function(){ const p = document.getElementById('prompt'); if (p) { p.value = (%s)[0]; sendRequest(); } })();",
                    encoded
                ))
            end
        end)
    end
end

return M
