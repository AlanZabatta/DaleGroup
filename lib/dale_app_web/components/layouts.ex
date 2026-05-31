defmodule DaleAppWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use DaleAppWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :current_scope, :map, default: nil
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="relative min-h-screen bg-white overflow-x-hidden font-sans">
      
      <div class="absolute -top-64 -right-64 w-96 h-[500px] border-2 border-green-500 rounded-full opacity-60 pointer-events-none z-0 lg:w-[800px] lg:h-[1000px] lg:-top-[500px] lg:-right-[500px]"></div>
      <div class="absolute -top-60 -right-72 w-[600px] h-[700px] border-2 border-green-500 rounded-full opacity-60 pointer-events-none z-0 lg:w-[1200px] lg:h-[1400px] lg:-top-[480px] lg:-right-[600px]"></div>

      <main class="relative z-10 max-w-4xl mx-auto px-4 pt-24 pb-12">
        {@inner_content}
      </main>

      <div id="fab-container" class="fixed bottom-6 right-6 z-50 flex flex-col-reverse items-center gap-4">
        
        <button 
          id="fab-trigger" 
          class="size-16 rounded-full bg-white border-4 border-[#2F5B2E] shadow-2xl hover:scale-110 active:scale-95 transition-all duration-300 cursor-pointer overflow-hidden p-1"
        >
          <img 
            src="https://res.cloudinary.com/djziwuaky/image/upload/v1779311629/WhatsApp_Image_2026-05-20_at_6.07.52_PM_2_dz41fk.jpg" 
            alt="DaleGroup Logo" 
            class="size-full object-contain rounded-full"
          />
        </button>

        <div 
          id="fab-menu" 
          class="flex flex-col-reverse items-center gap-4 transition-all duration-300 ease-out 
                 -translate-y-20 opacity-0 pointer-events-none"
        >
          <a 
            href="/#perfil" 
            target="_blank" 
            class="size-14 rounded-full bg-white shadow-xl hover:scale-110 hover:-translate-y-1 transition-all duration-200 overflow-hidden p-1 border-2 border-gray-100"
          >
            <img 
              src="https://res.cloudinary.com/djziwuaky/image/upload/v1779315462/WhatsApp_Image_2026-05-20_at_7.17.13_PM-removebg-preview_v8gofi.png" 
              alt="Perfil" 
              class="size-full object-contain"
            />
          </a>

          <a 
            href="/marcas" 
            class="size-14 rounded-full bg-white shadow-xl hover:scale-110 hover:-translate-y-1 transition-all duration-200 overflow-hidden p-1 border-2 border-gray-100"
          >
            <img 
              src="https://res.cloudinary.com/djziwuaky/image/upload/v1780237821/1000029077_preview_rev_1_1_suv2zb.png" 
              alt="Mapa" 
              class="size-full object-contain"
            />
          </a>

          <a 
            href="/#cupones" 
            target="_blank" 
            class="size-14 rounded-full bg-white shadow-xl hover:scale-110 hover:-translate-y-1 transition-all duration-200 overflow-hidden p-1 border-2 border-gray-100"
          >
            <img 
              src="https://res.cloudinary.com/djziwuaky/image/upload/v1779314471/WhatsApp_Image_2026-05-20_at_7.00.25_PM-removebg-preview_mqvxeb.png" 
              alt="Cupones" 
              class="size-full object-contain"
            />
          </a>
        </div>
      </div>

    </div>

    <.flash_group flash={@flash} />
    """
  end

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite"></div>
    """
  end
end
