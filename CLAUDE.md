# SimplePlayer

App nativa de macOS para ver vídeos de YouTube de forma limpia: solo el vídeo, sin título,
comentarios, likes ni nada del chrome de YouTube. Logueado con tu cuenta para ver tu home,
recomendaciones, suscripciones e historial.

## Cómo funciona (híbrido de 2 modos)

- **Navegar**: un `WKWebView` carga `youtube.com` logueado (sesión persistente, user-agent de
  Safari para esquivar el bloqueo de Google a webviews). Navegas tu feed/recomendaciones normal.
- **Ver**: al hacer clic en cualquier vídeo, se intercepta el enlace (no navega YouTube) y se
  reproduce con `AVPlayer` nativo — cero interfaz de YouTube. `Esc` o "‹ Volver" regresa al feed.

El stream lo resuelve **yt-dlp** (`/opt/homebrew/bin/yt-dlp`): pide H.264 ≤1080p + audio m4a
(los únicos códecs que AVFoundation decodifica de forma fiable — VP9/AV1 de 4K no se reproducen
nativamente, por eso el techo real es 1080p H.264). Vídeo y audio van en streams separados que se
fusionan con `AVMutableComposition`. Las cookies del webview se vuelcan a un `cookies.txt` para que
yt-dlp pueda resolver vídeos personalizados/privados/restringidos.

## Tech stack

- SwiftUI + AppKit (NSViewRepresentable para WKWebView y AVPlayerView)
- AVKit / AVFoundation para reproducción
- WebKit para navegar
- yt-dlp como subproceso para resolver streams
- **Sin App Sandbox** (necesario para ejecutar yt-dlp vía `Process`). App personal, no App Store.

## Arquitectura (`SimplePlayer/`)

| Fichero | Rol |
|---|---|
| `SimplePlayerApp.swift` | `@main`, `ContentView` (browse + overlay player + URLBar), menús/atajos |
| `AppModel.swift` | Estado (`mode`, `currentVideoID`), parser `YouTubeURL` (watch/youtu.be/shorts/embed/live) |
| `BrowseView.swift` | `WKWebView` + JS que intercepta clics en vídeos y reporta cambios de URL del SPA |
| `PlayerView.swift` | Resuelve stream, construye `AVPlayerItem` (merge vídeo+audio), `AVPlayerView` flotante |
| `StreamResolver.swift` | Ejecuta yt-dlp, parsea las URLs (`-g`) |
| `CookieExporter.swift` | Vuelca cookies del webview a Netscape `cookies.txt` para yt-dlp |
| `URLBar.swift` | Barra overlay (⌘L) para pegar un enlace; autocompleta del portapapeles |
| `Updater.swift` | Auto-update vía GitHub Releases: chequea al arrancar (y ⌘U), banner + swap del bundle y relanzado |

Config en `Config/Info.plist` (ATS abierto). Proyecto: `SimplePlayer.xcodeproj` (objectVersion 77,
grupo sincronizado con el sistema de ficheros → no hay que registrar cada `.swift` a mano).

## Comandos

```bash
# Compilar (Release) y generar SimplePlayer.app en la raíz del proyecto
./build.sh

# O manualmente:
xcodebuild -project SimplePlayer.xcodeproj -scheme SimplePlayer -configuration Release -derivedDataPath build
cp -R build/Build/Products/Release/SimplePlayer.app ./SimplePlayer.app

# Abrir en Xcode y darle ⌘R
open SimplePlayer.xcodeproj

# Ejecutar la app construida
open ./SimplePlayer.app

# Publicar una versión nueva (bump de versión + build + tag + GitHub Release con el binario)
# Las apps instaladas la ofrecerán al arrancar (o con ⌘U).
./release.sh 1.2 "Qué cambió"
```

El auto-update consulta `api.github.com/repos/zordor/simple-player/releases/latest`, compara con
`CFBundleShortVersionString` (= `MARKETING_VERSION`) y, si hay una mayor, descarga el asset `.zip`,
descomprime con `ditto`, reemplaza el bundle en marcha vía un script `/bin/sh` (espera a que el
proceso muera → quita quarantine → `mv` → `open`) y se relanza. Repo **público** (descarga sin auth).

## Atajos

- **⌘L** — abrir/cerrar la barra para pegar una URL de YouTube
- **Esc** o **‹ Volver** — del reproductor al feed de YouTube
- **⌘[** — volver al feed (alternativa de menú)

## Dependencias

- `yt-dlp` instalado (`brew install yt-dlp`). Mantenlo actualizado (`yt-dlp -U`): YouTube cambia
  formatos y un yt-dlp viejo deja de resolver streams.

## Limitaciones conocidas

- Techo de calidad **1080p H.264** (no 4K: AVFoundation no decodifica VP9/AV1 de YouTube).
- Las URLs de googlevideo caducan en horas → se re-resuelven cada vez que abres un vídeo (no hay caché).
- Algunos directos/HLS pueden no fusionar en `AVMutableComposition`; cae a stream combinado (~720p).
- La sesión de login de YouTube caduca cada cierto tiempo → re-loguear en el webview.
