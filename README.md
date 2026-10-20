# BabyLock

BabyLock bloquea el teclado, los clics, el desplazamiento y algunos gestos mientras mirás algo con un bebé cerca. El cursor sigue moviéndose. Una pastilla flotante permite salir con doble clic.

La versión macOS conserva el código original de BabyLock. Windows es una adaptación del mismo comportamiento.

## Descargar

Descargá la última versión desde [Releases](https://github.com/alandaitch/babylock/releases/latest):

| Sistema | Archivo |
| --- | --- |
| Mac con Apple Silicon o Intel | `BabyLock-macOS-universal.zip` |
| Windows x64 | `BabyLock-win-x64.zip` |
| Windows ARM64 | `BabyLock-win-arm64.zip` |

En macOS, descomprimí y mové `BabyLock.app` a Aplicaciones. Permití Accesibilidad cuando macOS lo pida. Como la app tiene firma ad hoc y no está notarizada, macOS puede pedirte confirmar su apertura en Ajustes del Sistema > Privacidad y seguridad. Si recompilás la app, quizá necesites desactivar y reactivar ese permiso.

En Windows, descomprimí y ejecutá `BabyLock.exe`. El ejecutable incluye .NET. Windows puede mostrar una advertencia porque el archivo no tiene firma comercial.

## Usar

Abrir BabyLock activa el bloqueo. Para salir, hacé doble clic en la pastilla flotante.

| Sistema | Atajo alternativo |
| --- | --- |
| macOS | Control + Opción + Comando + B |
| Windows | Control + Alt + Mayús + B |

También podés lanzar la app desde una terminal con `--minutos N` para desbloquear automáticamente. `--solo-teclado` deja libres los clics y el desplazamiento. Los argumentos se pueden combinar.

En macOS, `--test` hace una prueba sintética del bloqueo y del atajo.

BabyLock no reemplaza el bloqueo de sesión. El botón de encendido y Touch ID siguen funcionando. Algunos gestos del sistema pueden pasar por otro canal. En Windows, las pantallas protegidas pueden ignorar el bloqueo. Probala primero sin un bebé cerca y verificá ambos métodos de salida.

## Compilar

En macOS 13 o posterior, instalá Xcode Command Line Tools y ejecutá `bash mac/build.sh`. La app universal queda en `dist/BabyLock.app`.

En Windows, instalá .NET 10 SDK y ejecutá `dotnet publish windows/BabyLock.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true`.

## Licencia

[MIT](LICENSE).
