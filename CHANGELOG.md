# Changelog

Todos los cambios notables a este proyecto se documentarán en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
y este proyecto adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-10-11

### 🎉 Versión Inicial

Primera versión estable de Argos como sistema de ejecución de comandos y orquestación de tareas.

### 🏗️ Arquitectura Base

- **Nivel 1B en Proyecto Ypsilon**
- **LIBRERÍA BASE SIN DEPENDENCIAS**
- **Sin dependencias circulares**
- **Devuelve structs en lugar de IO para fácil procesamiento**

### 🚀 Funcionalidad Principal

#### Ejecución de Comandos

- `Argos.exec_command/3` - Ejecución de comandos del sistema básicos
- `Argos.exec_raw/2` - Ejecución sin logging adicional
- `Argos.exec_sudo/2` - Ejecución con privilegios sudo
- `Argos.exec_interactive/2` - Ejecución de comandos interactivos

#### Tareas Asíncronas

- `Argos.run_parallel/2` - Ejecución de múltiples tareas en paralelo
- `Argos.start_async_task/3` - Inicio de tareas asíncronas nombradas
- `Argos.stop_async_task/1` - Detención de tareas asíncronas
- `Argos.get_async_task/1` - Obtención del estado de tareas

#### Logging Estructurado

- `Argos.log/3` - Registro de mensajes con metadata estructurada
- `Argos.log_command/4` - Registro de ejecución de comandos
- `Argos.log_task/4` - Registro de ejecución de tareas

#### Gestión de Procesos

- `Argos.kill_process/1` - Eliminación de procesos por nombre
- `Argos.kill_processes/1` - Eliminación de múltiples procesos
- `Argos.halt/0` - Detención del sistema (uso interno)

### 📦 Estructuras de Datos

#### CommandResult

```elixir
%Argos.Structs.CommandResult{
  command: String.t(),        # Comando ejecutado
  args: [String.t()],         # Argumentos
  output: String.t(),         # Salida del comando
  exit_code: integer(),       # Código de salida
  duration: integer(),        # Duración en milisegundos
  success?: boolean(),        # Éxito de la ejecución
  error: term() | nil         # Error si ocurrió
}
```

#### TaskResult

```elixir
%Argos.Structs.TaskResult{
  task_name: String.t(),      # Nombre de la tarea
  result: CommandResult.t(), # Resultado de la ejecución
  duration: integer(),        # Duración en milisegundos
  success?: boolean(),        # Éxito de la tarea
  error: term() | nil         # Error si ocurrió
}
```

### 🧪 Pruebas

- Suite completa de pruebas unitarias
- Cobertura de código > 85%
- Tests de integración para ejecución de comandos
- Tests para casos de error y tiempo de espera

### 📚 Documentación

- README.md completo con ejemplos prácticos
- Documentación en línea para todas las funciones públicas
- Guía de uso para diferentes escenarios
- Integración con `mix docs`

## [0.1.0] - 2025-10-10

### 🚀 Versión Alpha Inicial

Primera versión alpha de Argos como parte del refactor de Proyecto Ypsilon.

### 🏗️ Estructura Inicial

- Extracción de funcionalidad de ejecución desde Pandr
- Creación de librería base independiente
- Definición de structs para resultados estructurados

### 🛠️ Funcionalidad Básica

- Ejecución básica de comandos del sistema
- Estructuras de datos para resultados
- Funciones de logging básicas

[Unreleased]: https://github.com/usuario/argos/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/usuario/argos/releases/tag/v1.0.0
