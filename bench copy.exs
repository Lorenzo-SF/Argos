# Benchmarks para Aurora
#
# Ejecutar con: mix run bench.exs

alias Aurora.{Color, Convert, Effects, Format}
alias Aurora.Structs.{ChunkText, ColorInfo, FormatInfo}

# Datos de prueba
sample_texts = [
  "Texto corto",
  "Este es un texto de longitud media que incluye varios caracteres",
  String.duplicate("Texto muy largos repetido múltiples veces. ", 50)
]

sample_colors = [:primary, :secondary, :error, :success, :warning, :info]

sample_hex_colors = ["#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF", "#00FFFF"]

sample_chunks = [
  %ChunkText{text: "Simple chunk"},
  %ChunkText{text: "Chunk con color", color: Color.get_color_info(:primary)},
  %ChunkText{text: "Chunk posicionado", pos_x: 10, pos_y: 5},
  %ChunkText{text: "Chunk completo", color: Color.get_color_info(:success), pos_x: 20, pos_y: 10}
]

IO.puts("🚀 Iniciando benchmarks para Aurora...\n")

Benchee.run(
  %{
    # === BENCHMARKS DE COLOR ===
    "Color.resolve_color/1 (atom)" => fn ->
      Enum.each(sample_colors, &Color.resolve_color/1)
    end,

    "Color.resolve_color/1 (hex)" => fn ->
      Enum.each(sample_hex_colors, &Color.resolve_color/1)
    end,

    "Color.apply_color/2" => fn ->
      color_info = Color.resolve_color(:primary)
      Enum.each(sample_texts, &Color.apply_color(&1, color_info))
    end,

    "Color.generate_gradient_between/2" => fn ->
      Color.generate_gradient_between("#FF0000", "#00FF00")
    end,

    # === BENCHMARKS DE CONVERT ===
    "Convert.to_chunk/1 (string)" => fn ->
      Enum.each(sample_texts, &Convert.to_chunk/1)
    end,

    "Convert.to_chunk/1 (tuple)" => fn ->
      Enum.each(sample_colors, fn color ->
        Convert.to_chunk({"Texto", color})
      end)
    end,

    # === BENCHMARKS DE EFFECTS ===
    "Effects.apply_effect/2 (single)" => fn ->
      Enum.each(sample_texts, &Effects.apply_effect(&1, :bold))
    end,

    "Effects.apply_multiple_effects/2" => fn ->
      effects = [:bold, :underline, :italic]
      Enum.each(sample_texts, &Effects.apply_multiple_effects(&1, effects))
    end,

    # === BENCHMARKS DE FORMAT ===
    "Format.format/1 (modo normal)" => fn ->
      format_info = %FormatInfo{chunks: sample_chunks, mode: :normal}
      Format.format(format_info)
    end,

    "Format.format/1 (modo table)" => fn ->
      format_info = %FormatInfo{chunks: sample_chunks, mode: :table}
      Format.format(format_info)
    end,

    "Format.format/1 (modo raw)" => fn ->
      positioned_chunks = [
        %ChunkText{text: "Raw text", pos_x: 10, pos_y: 5}
      ]
      format_info = %FormatInfo{chunks: positioned_chunks, mode: :raw}
      Format.format(format_info)
    end,

    # === BENCHMARKS DE AURORA PRINCIPAL ===
    "Aurora.format/2 (simple)" => fn ->
      Enum.each(sample_texts, &Aurora.format(&1, color: :primary))
    end,

    "Aurora.format/2 (con opciones)" => fn ->
      Enum.each(sample_texts, &Aurora.format(&1, color: :primary, bold: true, align: :center))
    end,

    "Aurora.colorize/2" => fn ->
      Enum.each(sample_texts, &Aurora.colorize(&1, :primary))
    end,

    "Aurora.stylize/2" => fn ->
      Enum.each(sample_texts, &Aurora.stylize(&1, [:bold, :underline]))
    end,

    "Aurora.json/2" => fn ->
      data = %{name: "test", value: 42, nested: %{a: 1, b: 2}}
      Aurora.json(data)
    end,

    "Aurora.json/2 (compact)" => fn ->
      data = %{name: "test", value: 42, nested: %{a: 1, b: 2}}
      Aurora.json(data, compact: true)
    end,

    # === BENCHMARKS DE OPTIMIZACIÓN ===
    "Color.expand_gradient_colors/1 (optimizado)" => fn ->
      test_cases = [
        ["#FF0000"],
        ["#FF0000", "#00FF00"],
        ["#FF0000", "#00FF00", "#0000FF"],
        ["#FF0000", "#00FF00", "#0000FF", "#FFFF00"],
        ["#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF"],
        ["#FF0000", "#00FF00", "#0000FF", "#FFFF00", "#FF00FF", "#00FFFF"]
      ]

      Enum.each(test_cases, &Color.expand_gradient_colors/1)
    end,

    "Aurora.json/2 (pipeline optimizado)" => fn ->
      data = %{
        user: "test_user",
        settings: %{theme: "dark", lang: "es"},
        data: Enum.map(1..10, &%{id: &1, name: "item_#{&1}"})
      }
      Aurora.json(data, color: :info, indent: true)
    end
  },

  # Configuración de benchmark
  time: 10,
  memory_time: 2,
  reduction_time: 2,
  print: [
    fast_warning: false
  ],
  formatters: [
    Benchee.Formatters.HTML,
    Benchee.Formatters.Console
  ],
  html: [file: "bench/results.html"]
)

IO.puts("\n✅ Benchmarks completados!")
IO.puts("📊 Resultados guardados en: bench/results.html")
IO.puts("🎯 Los benchmarks cubren:")
IO.puts("   - Operaciones de color y gradientes")
IO.puts("   - Conversión de tipos y chunks")
IO.puts("   - Aplicación de efectos ANSI")
IO.puts("   - Formateo en diferentes modos (normal, table, raw)")
IO.puts("   - Funciones principales de Aurora")
IO.puts("   - Optimizaciones implementadas")
