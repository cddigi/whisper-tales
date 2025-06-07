defmodule VoxDialogWeb.ModuleDashboardLive do
  @moduledoc """
  Modular dashboard that allows loading/unloading of system modules.
  Implements Grace Hopper's vision of interchangeable computer modules.
  """
  use VoxDialogWeb, :live_view
  require Logger
  
  @available_modules [
    %{
      id: "stt",
      name: "Speech-to-Text",
      description: "Convert voice to text using Whisper AI",
      icon: "🎙️",
      color: "blue",
      interface: %{
        input: "audio/webm",
        output: "text/plain"
      },
      status: :available
    },
    %{
      id: "tts", 
      name: "Text-to-Speech",
      description: "Generate natural speech from text using Chatterbox",
      icon: "🔊",
      color: "purple",
      interface: %{
        input: "text/plain",
        output: "audio/wav"
      },
      status: :available
    },
    %{
      id: "voice_session",
      name: "Voice Session",
      description: "Real-time voice conversation with AI",
      icon: "💬",
      color: "green",
      interface: %{
        input: "audio/stream",
        output: "audio/stream"
      },
      status: :available
    },
    %{
      id: "audio_library",
      name: "Audio Library",
      description: "Manage and playback audio recordings",
      icon: "📚",
      color: "indigo",
      interface: %{
        input: "audio/*",
        output: "audio/*"
      },
      status: :available
    }
  ]
  
  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to module status updates
      Phoenix.PubSub.subscribe(VoxDialog.PubSub, "module_status")
    end
    
    {:ok, assign(socket,
      available_modules: @available_modules,
      loaded_modules: [],
      active_module: nil,
      loading_module: nil,
      system_status: :ready
    )}
  end
  
  @impl true
  def render(assigns) do
    ~H"""
    <div class="module-dashboard">
      <!-- Header -->
      <header class="dashboard-header">
        <div class="container mx-auto px-6 py-4">
          <div class="flex items-center justify-between">
            <div class="flex items-center space-x-4">
              <svg viewBox="0 0 71 48" class="h-10" aria-hidden="true">
                <path
                  d="m26.371 33.477-.552-.1c-3.92-.729-6.397-3.1-7.57-6.829-.733-2.324.597-4.035 3.035-4.148 1.995-.092 3.362 1.055 4.57 2.39 1.557 1.72 2.984 3.558 4.514 5.305 2.202 2.515 4.797 4.134 8.347 3.634 3.183-.448 5.958-1.725 8.371-3.828.363-.316.761-.592 1.144-.886l-.241-.284c-2.027.63-4.093.841-6.205.735-3.195-.16-6.24-.828-8.964-2.582-2.486-1.601-4.319-3.746-5.19-6.611-.704-2.315.736-3.934 3.135-3.6.948.133 1.746.56 2.463 1.165.583.493 1.143 1.015 1.738 1.493 2.8 2.25 6.712 2.375 10.265-.068-5.842-.026-9.817-3.24-13.308-7.313-1.366-1.594-2.7-3.216-4.095-4.785-2.698-3.036-5.692-5.71-9.79-6.623C12.8-.623 7.745.14 2.893 2.361 1.926 2.804.997 3.319 0 4.149c.494 0 .763.006 1.032 0 2.446-.064 4.28 1.023 5.602 3.024.962 1.457 1.415 3.104 1.761 4.798.513 2.515.247 5.078.544 7.605.761 6.494 4.08 11.026 10.26 13.346 2.267.852 4.591 1.135 7.172.555ZM10.751 3.852c-.976.246-1.756-.148-2.56-.962 1.377-.343 2.592-.476 3.897-.528-.107.848-.607 1.306-1.336 1.49Zm32.002 37.924c-.085-.626-.62-.901-1.04-1.228-1.857-1.446-4.03-1.958-6.333-2-1.375-.026-2.735-.128-4.031-.61-.595-.22-1.26-.505-1.244-1.272.015-.78.693-1 1.31-1.184.505-.15 1.026-.247 1.6-.382-1.46-.936-2.886-1.065-4.787-.3-2.993 1.202-5.943 1.06-8.926-.017-1.684-.608-3.179-1.563-4.735-2.408l-.043.03a2.96 2.96 0 0 0 .04-.029c-.038-.117-.107-.12-.197-.054l.122.107c1.29 2.115 3.034 3.817 5.004 5.271 3.793 2.8 7.936 4.471 12.784 3.73A66.714 66.714 0 0 1 37 40.877c1.98-.16 3.866.398 5.753.899Zm-9.14-30.345c-.105-.076-.206-.266-.42-.069 1.745 2.36 3.985 4.098 6.683 5.193 4.354 1.767 8.773 2.07 13.293.51 3.51-1.21 6.033-.028 7.343 3.38.19-3.955-2.137-6.837-5.843-7.401-2.084-.318-4.01.373-5.962.94-5.434 1.575-10.485.798-15.094-2.553Zm27.085 15.425c.708.059 1.416.123 2.124.185-1.6-1.405-3.55-1.517-5.523-1.404-3.003.17-5.167 1.903-7.14 3.972-1.739 1.824-3.31 3.87-5.903 4.604.043.078.054.117.066.117.35.005.699.021 1.047.005 3.768-.17 7.317-.965 10.14-3.7.89-.86 1.685-1.817 2.544-2.71.716-.746 1.584-1.159 2.645-1.07Zm-8.753-4.67c-2.812.246-5.254 1.409-7.548 2.943-1.766 1.18-3.654 1.738-5.776 1.37-.374-.066-.75-.114-1.124-.17l-.013.156c.135.07.265.151.405.207.354.14.702.308 1.07.395 4.083.971 7.992.474 11.516-1.803 2.221-1.435 4.521-1.707 7.013-1.336.252.038.503.083.756.107.234.022.479.255.795.003-2.179-1.574-4.526-2.096-7.094-1.872Zm-10.049-9.544c1.475.051 2.943-.142 4.486-1.059-.452.04-.643.04-.827.076-2.126.424-4.033-.04-5.733-1.383-.623-.493-1.257-.974-1.889-1.457-2.503-1.914-5.374-2.555-8.514-2.5.05.154.054.26.108.315 3.417 3.455 7.371 5.836 12.369 6.008Zm24.727 17.731c-2.114-2.097-4.952-2.367-7.578-.537 1.738.078 3.043.632 4.101 1.728.374.388.763.768 1.182 1.106 1.6 1.29 4.311 1.352 5.896.155-1.861-.726-1.861-.726-3.601-2.452Zm-21.058 16.06c-1.858-3.46-4.981-4.24-8.59-4.008a9.667 9.667 0 0 1 2.977 1.39c.84.586 1.547 1.311 2.243 2.055 1.38 1.473 3.534 2.376 4.962 2.07-.656-.412-1.238-.848-1.592-1.507Zm17.29-19.32c0-.023.001-.045.003-.068l-.006.006.006-.006-.036-.004.021.018.012.053Zm-20 14.744a7.61 7.61 0 0 0-.072-.041.127.127 0 0 0 .015.043c.005.008.038 0 .058-.002Zm-.072-.041-.008-.034-.008.01.008-.01-.022-.006.005.026.024.014Z"
                  fill="#FD4F00"
                />
              </svg>
              <h1 class="text-2xl font-bold text-gray-900">VoxDialog Module System</h1>
            </div>
            <div class="system-status flex items-center space-x-2">
              <div class={[
                "status-indicator",
                @system_status == :ready && "bg-green-500",
                @system_status == :busy && "bg-yellow-500",
                @system_status == :error && "bg-red-500"
              ]}></div>
              <span class="text-sm text-gray-600">
                System <%= String.capitalize(to_string(@system_status)) %>
              </span>
            </div>
          </div>
        </div>
      </header>
      
      <!-- Main Content -->
      <main class="dashboard-main">
        <div class="container mx-auto px-6 py-8">
          <!-- Module Grid -->
          <div class="module-grid">
            <!-- Available Modules -->
            <section class="available-modules">
              <h2 class="section-title">Available Modules</h2>
              <p class="section-subtitle">Click to load modules into the system</p>
              
              <div class="modules-container">
                <%= for module <- @available_modules do %>
                  <div
                    class={[
                      "module-card",
                      "module-card-#{module.color}",
                      module.id in Enum.map(@loaded_modules, & &1.id) && "module-loaded",
                      @loading_module == module.id && "module-loading"
                    ]}
                    phx-click="load_module"
                    phx-value-module_id={module.id}
                  >
                    <div class="module-icon">
                      <%= module.icon %>
                    </div>
                    <h3 class="module-name"><%= module.name %></h3>
                    <p class="module-description"><%= module.description %></p>
                    
                    <div class="module-interface">
                      <div class="interface-item">
                        <span class="interface-label">Input:</span>
                        <span class="interface-type"><%= module.interface.input %></span>
                      </div>
                      <div class="interface-item">
                        <span class="interface-label">Output:</span>
                        <span class="interface-type"><%= module.interface.output %></span>
                      </div>
                    </div>
                    
                    <%= if @loading_module == module.id do %>
                      <div class="module-loading-overlay">
                        <div class="loading-spinner"></div>
                        <span>Loading Module...</span>
                      </div>
                    <% end %>
                    
                    <%= if module.id in Enum.map(@loaded_modules, & &1.id) do %>
                      <div class="module-loaded-badge">
                        ✓ Loaded
                      </div>
                    <% end %>
                  </div>
                <% end %>
              </div>
            </section>
            
            <!-- Loaded Modules -->
            <section class="loaded-modules">
              <h2 class="section-title">Loaded Modules</h2>
              <p class="section-subtitle">Active modules in the system</p>
              
              <%= if length(@loaded_modules) > 0 do %>
                <div class="loaded-modules-list">
                  <%= for module <- @loaded_modules do %>
                    <div class={[
                      "loaded-module-item",
                      @active_module && @active_module.id == module.id && "module-active"
                    ]}>
                      <div class="module-info">
                        <span class="module-icon-small"><%= module.icon %></span>
                        <span class="module-name-small"><%= module.name %></span>
                      </div>
                      <div class="module-actions">
                        <button
                          phx-click="activate_module"
                          phx-value-module_id={module.id}
                          class="btn-activate"
                          disabled={@active_module && @active_module.id == module.id}
                        >
                          <%= if @active_module && @active_module.id == module.id, do: "Active", else: "Activate" %>
                        </button>
                        <button
                          phx-click="unload_module"
                          phx-value-module_id={module.id}
                          class="btn-unload"
                        >
                          Unload
                        </button>
                      </div>
                    </div>
                  <% end %>
                </div>
              <% else %>
                <div class="empty-state">
                  <p>No modules loaded yet. Click on available modules to load them.</p>
                </div>
              <% end %>
            </section>
          </div>
          
          <!-- Active Module View -->
          <%= if @active_module do %>
            <section class="active-module-view">
              <div class="active-module-header">
                <h2 class="flex items-center space-x-3">
                  <span class="text-3xl"><%= @active_module.icon %></span>
                  <span><%= @active_module.name %></span>
                </h2>
                <button
                  phx-click="close_module"
                  class="btn-close"
                >
                  Close Module
                </button>
              </div>
              
              <div class="active-module-content">
                <%= case @active_module.id do %>
                  <% "stt" -> %>
                    <div class="module-iframe-container">
                      <iframe src="/voice" class="module-iframe"></iframe>
                    </div>
                  <% "tts" -> %>
                    <div class="module-iframe-container">
                      <iframe src="/tts" class="module-iframe"></iframe>
                    </div>
                  <% "voice_session" -> %>
                    <div class="module-iframe-container">
                      <iframe src="/voice" class="module-iframe"></iframe>
                    </div>
                  <% "audio_library" -> %>
                    <div class="module-iframe-container">
                      <iframe src="/clips" class="module-iframe"></iframe>
                    </div>
                  <% _ -> %>
                    <div class="module-placeholder">
                      <p>Module interface not implemented yet.</p>
                    </div>
                <% end %>
              </div>
            </section>
          <% end %>
        </div>
      </main>
    </div>
    
    <style>
      .module-dashboard {
        min-height: 100vh;
        background-color: #f9fafb;
      }
      
      .dashboard-header {
        background: white;
        border-bottom: 1px solid #e5e7eb;
        box-shadow: 0 1px 3px 0 rgba(0, 0, 0, 0.1);
      }
      
      .status-indicator {
        width: 8px;
        height: 8px;
        border-radius: 50%;
        animation: pulse 2s infinite;
      }
      
      @keyframes pulse {
        0% { opacity: 1; }
        50% { opacity: 0.5; }
        100% { opacity: 1; }
      }
      
      .module-grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 2rem;
        margin-bottom: 2rem;
      }
      
      @media (max-width: 1024px) {
        .module-grid {
          grid-template-columns: 1fr;
        }
      }
      
      .section-title {
        font-size: 1.5rem;
        font-weight: 700;
        color: #111827;
        margin-bottom: 0.5rem;
      }
      
      .section-subtitle {
        color: #6b7280;
        margin-bottom: 1.5rem;
      }
      
      .modules-container {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
        gap: 1rem;
      }
      
      .module-card {
        background: white;
        border: 2px solid #e5e7eb;
        border-radius: 0.75rem;
        padding: 1.5rem;
        cursor: pointer;
        transition: all 0.3s ease;
        position: relative;
        overflow: hidden;
      }
      
      .module-card:hover {
        transform: translateY(-2px);
        box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
      }
      
      .module-card-blue:hover { border-color: #3b82f6; }
      .module-card-purple:hover { border-color: #8b5cf6; }
      .module-card-green:hover { border-color: #10b981; }
      .module-card-indigo:hover { border-color: #6366f1; }
      
      .module-card.module-loaded {
        background: #f0fdf4;
        border-color: #10b981;
      }
      
      .module-card.module-loading {
        pointer-events: none;
      }
      
      .module-icon {
        font-size: 3rem;
        margin-bottom: 1rem;
      }
      
      .module-name {
        font-size: 1.25rem;
        font-weight: 600;
        color: #111827;
        margin-bottom: 0.5rem;
      }
      
      .module-description {
        color: #6b7280;
        font-size: 0.875rem;
        margin-bottom: 1rem;
      }
      
      .module-interface {
        border-top: 1px solid #e5e7eb;
        padding-top: 0.75rem;
        font-size: 0.75rem;
      }
      
      .interface-item {
        display: flex;
        justify-content: space-between;
        margin-bottom: 0.25rem;
      }
      
      .interface-label {
        color: #6b7280;
      }
      
      .interface-type {
        color: #111827;
        font-family: monospace;
      }
      
      .module-loading-overlay {
        position: absolute;
        inset: 0;
        background: rgba(255, 255, 255, 0.9);
        display: flex;
        flex-direction: column;
        align-items: center;
        justify-content: center;
        gap: 1rem;
      }
      
      .loading-spinner {
        width: 40px;
        height: 40px;
        border: 3px solid #e5e7eb;
        border-top-color: #3b82f6;
        border-radius: 50%;
        animation: spin 1s linear infinite;
      }
      
      @keyframes spin {
        to { transform: rotate(360deg); }
      }
      
      .module-loaded-badge {
        position: absolute;
        top: 0.75rem;
        right: 0.75rem;
        background: #10b981;
        color: white;
        padding: 0.25rem 0.75rem;
        border-radius: 9999px;
        font-size: 0.75rem;
        font-weight: 600;
      }
      
      .loaded-modules-list {
        background: white;
        border-radius: 0.75rem;
        overflow: hidden;
      }
      
      .loaded-module-item {
        padding: 1rem 1.5rem;
        border-bottom: 1px solid #e5e7eb;
        display: flex;
        justify-content: space-between;
        align-items: center;
        transition: background-color 0.2s;
      }
      
      .loaded-module-item:last-child {
        border-bottom: none;
      }
      
      .loaded-module-item.module-active {
        background: #eff6ff;
      }
      
      .module-info {
        display: flex;
        align-items: center;
        gap: 0.75rem;
      }
      
      .module-icon-small {
        font-size: 1.5rem;
      }
      
      .module-name-small {
        font-weight: 500;
        color: #111827;
      }
      
      .module-actions {
        display: flex;
        gap: 0.5rem;
      }
      
      .btn-activate, .btn-unload, .btn-close {
        padding: 0.5rem 1rem;
        border-radius: 0.375rem;
        font-size: 0.875rem;
        font-weight: 500;
        transition: all 0.2s;
        border: none;
        cursor: pointer;
      }
      
      .btn-activate {
        background: #3b82f6;
        color: white;
      }
      
      .btn-activate:hover:not(:disabled) {
        background: #2563eb;
      }
      
      .btn-activate:disabled {
        background: #9ca3af;
        cursor: not-allowed;
      }
      
      .btn-unload {
        background: #ef4444;
        color: white;
      }
      
      .btn-unload:hover {
        background: #dc2626;
      }
      
      .btn-close {
        background: #6b7280;
        color: white;
      }
      
      .btn-close:hover {
        background: #4b5563;
      }
      
      .empty-state {
        text-align: center;
        padding: 3rem;
        color: #6b7280;
      }
      
      .active-module-view {
        background: white;
        border-radius: 0.75rem;
        overflow: hidden;
        box-shadow: 0 10px 15px -3px rgba(0, 0, 0, 0.1);
      }
      
      .active-module-header {
        padding: 1.5rem;
        border-bottom: 1px solid #e5e7eb;
        display: flex;
        justify-content: space-between;
        align-items: center;
      }
      
      .active-module-content {
        padding: 1.5rem;
        min-height: 600px;
      }
      
      .module-iframe-container {
        width: 100%;
        height: 600px;
        border: 1px solid #e5e7eb;
        border-radius: 0.5rem;
        overflow: hidden;
      }
      
      .module-iframe {
        width: 100%;
        height: 100%;
        border: none;
      }
      
      .module-placeholder {
        display: flex;
        align-items: center;
        justify-content: center;
        height: 400px;
        background: #f9fafb;
        border-radius: 0.5rem;
        color: #6b7280;
      }
    </style>
    """
  end
  
  @impl true
  def handle_event("load_module", %{"module_id" => module_id}, socket) do
    module = Enum.find(socket.assigns.available_modules, & &1.id == module_id)
    
    if module && module.id not in Enum.map(socket.assigns.loaded_modules, & &1.id) do
      # Load module through ModuleManager
      case VoxDialog.ModuleManager.load_module(module_id) do
        :ok ->
          send(self(), {:finish_loading, module})
          {:noreply, assign(socket, loading_module: module_id)}
        {:error, reason} ->
          Logger.error("Failed to load module #{module_id}: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Failed to load module: #{inspect(reason)}")}
      end
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_event("unload_module", %{"module_id" => module_id}, socket) do
    # Unload module through ModuleManager
    case VoxDialog.ModuleManager.unload_module(module_id) do
      :ok ->
        loaded_modules = Enum.reject(socket.assigns.loaded_modules, & &1.id == module_id)
        
        active_module = if socket.assigns.active_module && socket.assigns.active_module.id == module_id do
          nil
        else
          socket.assigns.active_module
        end
        
        {:noreply, assign(socket,
          loaded_modules: loaded_modules,
          active_module: active_module
        )}
      {:error, reason} ->
        Logger.error("Failed to unload module #{module_id}: #{inspect(reason)}")
        {:noreply, put_flash(socket, :error, "Failed to unload module: #{inspect(reason)}")}
    end
  end
  
  @impl true
  def handle_event("activate_module", %{"module_id" => module_id}, socket) do
    module = Enum.find(socket.assigns.loaded_modules, & &1.id == module_id)
    
    if module do
      {:noreply, assign(socket, active_module: module)}
    else
      {:noreply, socket}
    end
  end
  
  @impl true
  def handle_event("close_module", _params, socket) do
    {:noreply, assign(socket, active_module: nil)}
  end
  
  @impl true
  def handle_info({:finish_loading, module}, socket) do
    # Add module to loaded list after simulated delay
    Process.sleep(1000) # Simulate loading time
    
    {:noreply, assign(socket,
      loaded_modules: socket.assigns.loaded_modules ++ [module],
      loading_module: nil
    )}
  end
  
  @impl true
  def handle_info({:module_loaded, %{module_id: module_id} = event_data}, socket) do
    Logger.info("Module loaded event received: #{module_id}")
    Logger.debug("Module event data: #{inspect(event_data)}")
    # Module is already loaded by ModuleManager, just update UI if needed
    {:noreply, socket}
  end
  
  @impl true
  def handle_info({:module_unloaded, module_id}, socket) do
    Logger.info("Module unloaded event received: #{module_id}")
    # Module is already unloaded by ModuleManager, just update UI if needed
    {:noreply, socket}
  end
end