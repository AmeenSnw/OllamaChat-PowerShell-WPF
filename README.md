# Ollama Chat GUI (PowerShell & WPF)

A lightweight, feature-rich, zero-dependency desktop GUI client for [Ollama](https://ollama.com/), built entirely in **PowerShell** and **Windows Presentation Foundation (WPF)**. Designed for local Large Language Model (LLM) workflows, it delivers a modern chat experience with segmented message blocks, live embedded web previews, dual table rendering modes, and full multilingual (RTL/LTR) support.

## ✨ Key Features

### 💬 Advanced Chat & Rendering Engine

* **Segmented Message Architecture:** Assistant responses are dynamically parsed into distinct, interactive UI widgets rather than a single flat text block:

  * **Formatted Text Blocks:** Supports Markdown bold, italics, and inline code with automatic **RTL** and **LTR** text direction adaptation.

  * **Dedicated Code Cards:** Always rendered Left-to-Right (`Consolas`) with syntax language headers, horizontal scrolling, and one-click `[Copy Code]` buttons.

  * **Dual In-Chat Table Modes:** Switchable from Settings between:

    1. **FlowDocument Table:** Clean, integrated native tables with alternating row shading.

    2. **Interactive DataGrid:** Sortable columns, selectable cells, and grid lines for data analysis.

* **Smart Free Scroll:** Automatically follows streaming responses at the bottom, but immediately yields scroll control if you scroll up to read earlier sections while generation continues in the background.

* **Interactive Message Controls:** Built-in `[Copy]`, `[Regen]` (Regenerate response), and `[Edit]` (Edit prompt and resend) actions on chat bubbles.

### 🌐 Smart Preview Pane (Code & Embedded Web)

* **Live Embedded WebBrowser:** Preview generated `HTML`, `SVG`, or formatted Markdown tables directly inside the application without leaving the window.

* **Instant View Toggle:** Switch seamlessly between **`Code`** (raw source view) and **`Web Preview`** (live rendered output).

* **Export & External Launch:** Open any block in your default external browser/editor, or save individual/all extracted blocks to disk with one click.

### ⚡ Performance, Models & Attachments

* **Non-Blocking Asynchronous Streaming:** Uses background PowerShell runspaces and `ConcurrentQueue` with a UI `DispatcherTimer` to keep the interface responsive during long generations, complete with real-time token/sec (`tok/s`) and context usage (`%`) telemetry.

* **Multimodal & File Attachments:** Drag-and-drop or attach images (`.png`, `.jpg`, `.gif`, `.bmp` for Vision models) and text/code files (`.ps1`, `.py`, `.json`, `.csv`, `.md`, `.html`, etc.).

* **Full Ollama Server & Model Management:**

  * Start the local `ollama serve` daemon directly from the menu.

  * Pull new models with real-time download progress tracking.

  * Built-in network & API diagnostics tool.

* **Granular Tuning & Persistence:** Configure `Host/Port`, `System Prompt`, Speed Presets (`Max Speed`, `Balanced`, `Quality`), `num_ctx`, `num_thread`, `keep_alive`, and sampling parameters (`Temperature`, `Top P`, `Top K`, `Repeat Penalty`, `Seed`). All preferences are persisted automatically to `%APPDATA%\OllamaChat\settings.json`.

## 📋 Prerequisites

* **Operating System:** Windows 10 or Windows 11.

* **PowerShell:** Windows PowerShell 5.1 (built-in) or PowerShell 7+.

* **Ollama:** Installed locally and accessible in your system `PATH` (or running remotely on an accessible host/port).

## 🚀 Getting Started

1. **Clone or Download the Repository:**

   ```
   git clone https://github.com/YourUsername/OllamaChat-PowerShell-WPF.git
   cd OllamaChat-PowerShell-WPF
   
   ```

2. **Run the Application:**
   Right-click `SnwOllamaGUIv18.ps1` and select **Run with PowerShell**, or launch it from a terminal:

   ```
   powershell -ExecutionPolicy Bypass -File .\SnwOllamaGUIv18.ps1
   
   ```

3. **Connect & Start Chatting:**

   * If Ollama is not already running in the background, click **`[Ollama] -> Start Ollama Server`**.

   * Open **`[Settings] -> Configuration...`** to select your installed model (or click **Pull** to download one like `llama3.2:1b` or `qwen2.5-coder`).

## 🛠️ Configuration & Data Paths

All user configurations and saved chat sessions are stored cleanly in your local AppData directory:

* **Configuration File:** `%APPDATA%\OllamaChat\settings.json`

* **Saved Conversations:** `%APPDATA%\OllamaChat\conversations\`

## ⌨️ Keyboard Shortcuts

| Shortcut | Action | 
| ----- | ----- | 
| `Enter` | Send message (default mode) | 
| `Shift + Enter` | Insert new line | 
| `Ctrl + Enter` | Send message (also works when `Send with Ctrl+Enter` is enabled in Settings) | 

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.
