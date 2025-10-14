# Argos

**Sistema de ejecución de comandos y orquestación de tareas** - Nivel 1B de Proyecto Ypsilon

[![Version](https://img.shields.io/hexpm/v/argos.svg)](https://hex.pm/packages/argos) [![License](https://img.shields.io/hexpm/l/argos.svg)](https://github.com/usuario/argos/blob/main/LICENSE)

Argos es una librería base sin dependencias para ejecución de comandos del sistema y gestión de tareas asíncronas.

## Arquitectura

Argos forma parte de **Proyecto Ypsilon**:

```
                    ┌─────────────────┐
                    │   NIVEL 3: ARK  │
                    │  Microframework │
                    │     Global      │
                    └────────┬────────┘
                             │
                    ┌────────▼─────────┐
                    │  NIVEL 2: AEGIS  │
                    │  CLI/TUI         │
                    │  Framework       │
                    └────┬─────┬───────┘
                         │     │
           ┌─────────────┘     └─────────────┐
           │                                 │
    ┌──────▼────────┐              ┌─────────▼──────┐
    │ NIVEL 1A:     │              │ NIVEL 1B:      │
    │ AURORA        │              │ ARGOS          │
    │ Formatting &  │              │ Execution &    │
    │ Rendering     │              │ Orchestration  │
    └───────────────┘              └────────────────┘
         BASE                              BASE
      (sin deps)                        (sin deps) ← ESTÁS AQUÍ
```

## Características

- 🚀 **Ejecución de comandos** del sistema con resultados estructurados
- ⚡ **Tareas asíncronas** con control de concurrencia
- 📝 **Logging estructurado** sin dependencias de UI
- 🛠️ **Sin dependencias externas** - completamente autónomo
- 🎯 **Devuelve structs en lugar de IO** para fácil procesamiento

## Instalación

Agrega a tu `mix.exs`:

```elixir
def deps do
  [
    {:argos, "~> 1.0.0"}
  ]
end
```

## Uso Rápido

### Ejecución de comandos

```elixir
# Ejecución simple
result = Argos.exec_command("ls", ["-la"])
if result.success? do
  IO.puts("Output: #{result.output}")
end

# Ejecución con sudo
result = Argos.exec_sudo("systemctl restart nginx")

# Ejecución interactiva
result = Argos.exec_interactive("vim", ["config.txt"])

# Ejecución básica sin logging
result = Argos.exec_raw("pwd")
```

### Tareas en paralelo

```elixir
tasks = [
  {"compile", "mix compile"},
  {"test", {:function, &run_tests/0}},
  {"lint", "mix credo --strict"}
]

result = Argos.run_parallel(tasks, max_concurrency: 2)
IO.inspect(result.results)
```

### Logging estructurado

```elixir
# Logging simple
Argos.log(:info, "Operation completed")

# Logging con metadata
Argos.log(:info, "Task completed", task_id: 123, duration: 1500)

# Logging de comandos
Argos.log_command("ls -la", 0, 250, "total 8...")
```

## API Principal

### Ejecución de Comandos

- `Argos.exec_command/3` - Ejecuta un comando del sistema
- `Argos.exec_raw/2` - Ejecución básica sin logging adicional
- `Argos.exec_sudo/2` - Ejecuta un comando con privilegios sudo
- `Argos.exec_interactive/2` - Ejecuta un comando de forma interactiva

### Tareas Asíncronas

- `Argos.run_parallel/2` - Ejecuta múltiples tareas en paralelo
- `Argos.start_async_task/3` - Inicia una tarea asíncrona
- `Argos.stop_async_task/1` - Detiene una tarea asíncrona
- `Argos.get_async_task/1` - Obtiene el estado de una tarea

### Logging

- `Argos.log/3` - Registra un mensaje con metadata estructurada
- `Argos.log_command/4` - Registra la ejecución de un comando
- `Argos.log_task/4` - Registra la ejecución de una tarea

### Gestión de Procesos

- `Argos.kill_process/1` - Mata un proceso por nombre
- `Argos.kill_processes/1` - Mata múltiples procesos
- `Argos.halt/0` - Detiene la ejecución del sistema

## Módulos Principales

- `Argos.Command` - Ejecución de comandos del sistema
- `Argos.AsyncTask` - Gestión de tareas asíncronas
- `Argos.Log` - Logging estructurado
- `Argos.Structs.CommandResult` - Resultado de comandos
- `Argos.Structs.TaskResult` - Resultado de tareas

## Estructuras de Datos

### CommandResult

```elixir
%Argos.Structs.CommandResult{
  command: "ls -la",
  args: [],
  output: "total 8\n-rw-r--r--...",
  exit_code: 0,
  duration: 150,
  success?: true,
  error: nil
}
```

### TaskResult

```elixir
%Argos.Structs.TaskResult{
  task_name: "compile",
  result: %CommandResult{},
  duration: 2500,
  success?: true,
  error: nil
}
```

## Uso como CLI

Argos también puede usarse como una herramienta de línea de comandos independiente:

```bash
# Ejecutar un comando
argos exec ls -la

# Ejecutar con sudo
argos sudo "systemctl restart nginx"

# Ejecutar comando sin logging adicional
argos raw "pwd"

# Ejecutar tareas en paralelo
argos parallel --task "compile:mix compile" --task "test:mix test"

# Matar un proceso
argos kill "process_name"

# Listar procesos
argos ps
```

## Licencia

Apache 2.0 - Consulta el archivo [LICENSE](LICENSE) para más detalles.
