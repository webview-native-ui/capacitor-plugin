---
title: App-local Native UI extensions (experimental)
---

# App-local Native UI extensions (experimental)

> **Experimental:** The extension API, native registration interfaces and behavior may change in future releases. This applies to both SwiftUI and Kotlin/Compose extensions, including `element` and `tab-accessory` placement.

An extension projects your existing Web UI into a SwiftUI View on iOS or Jetpack Compose content on Android. Keep both definitions in your application: no npm package, separate library, or Capacitor plugin is required. The Web element remains the source of truth and the fallback UI.

Extensions use the same [projection model](https://docs.rdlabo.dev/projects/capacitor-native-ui/docs/readme#how-projection-works) as built-in controls. Define the DOM data and actions to expose, then provide their native presentation.

## Before you start

Start with an existing Capacitor 8 app and install the plugin if you have not already:

```sh
npm install @rdlabo/capacitor-native-ui @erkamyaman/capacitor-foldable
```

Choose the native platform you want to support:

- **Android:** use your Capacitor Android project and an API 24+ device or emulator. Follow step 1, then the [Kotlin/Compose registration](#2b-register-compose-content-on-android), and steps 3–4. No iOS project, Xcode, Ionic, or theme package is required.
- **iOS:** use your Capacitor iOS project, Xcode 26+, and an iOS 26+ device or simulator. Follow step 1, the [SwiftUI registration](#2a-register-a-swiftui-view-on-ios), and steps 3–4. To also project standard controls, follow [Ionic setup](https://docs.rdlabo.dev/projects/capacitor-native-ui/docs/setup) or [HTML setup](https://docs.rdlabo.dev/projects/capacitor-native-ui/docs/framework-independent).
- **Both:** share the DOM reader from step 1 and register native content for the same name on each platform.

The TypeScript examples below use the Ionic entry. Without Ionic, import both `defineNativeUI` and `enableNativeUI` from `@rdlabo/capacitor-native-ui/core`.

## 1. Define a DOM reader

```ts
// src/native-ui/counter.ts
import { defineNativeUI } from '@rdlabo/capacitor-native-ui';

export const counter = defineNativeUI({
  name: 'app.counter',
  selector: '[data-counter]',
  read(element) {
    return {
      props: { count: Number(element.getAttribute('data-count') ?? 0) },
      actions: { increment: element.querySelector<HTMLButtonElement>('button') },
    };
  },
});
```

For example, use this Web source. Its reserved space also accommodates native content and an action error:

```html
<div data-counter data-count="0" style="width: 280px; min-height: 128px">
  <p data-count-label>Count: 0</p>
  <button type="button">Increment</button>
</div>
```

Keep your framework's click handler updating the count and `data-count`. In plain HTML, this is enough:

```ts
const source = document.querySelector<HTMLElement>('[data-counter]')!;
source.querySelector('button')!.addEventListener('click', () => {
  const count = Number(source.dataset.count ?? 0) + 1;
  source.dataset.count = String(count);
  source.querySelector('[data-count-label]')!.textContent = `Count: ${count}`;
});
```

The shell observes DOM changes and sends the new props to the native content. State rendered into DOM attributes or text is observed automatically. For properties or external state read by the reader that do not mutate the DOM, call `shell.markForCheck()` after changing them.

## 2a. Register a SwiftUI View on iOS

For CocoaPods projects, first complete the [Engine Podfile setup](https://docs.rdlabo.dev/projects/capacitor-native-ui/docs/setup#4-build-sync-and-run). SwiftPM resolves Engine automatically.

Run `npx cap sync ios` after installing the plugin, then add a Swift file to the application's Xcode target. Import `NativeUIPlugin`, the module supplied by `@rdlabo/capacitor-native-ui`. Keep your existing SPM or CocoaPods integration.

```swift
import SwiftUI
import NativeUIPlugin

struct CounterProps: Decodable {
    let count: Int
}

struct CounterView: View {
    let props: CounterProps
    let actions: NativeUIActions
    @State private var error: String?

    var body: some View {
        HStack {
            Text("Count: \(props.count)")
            Button("Increment") {
                Task { @MainActor in
                    do {
                        try await actions.activate("increment")
                        error = nil
                    } catch {
                        self.error = "Action unavailable"
                    }
                }
            }
            .disabled(!actions.isAvailable("increment"))
            if let error { Text(error) }
        }
    }
}

@MainActor func registerAppNativeUI() throws {
    try NativeUI.register("app.counter") {
        (props: CounterProps, actions: NativeUIActions) in
        CounterView(props: props, actions: actions)
    }
}
```

Call `registerAppNativeUI()` once from `application(_:didFinishLaunchingWithOptions:)`, before JavaScript enables the shell. Handle a registration error there; duplicate or empty names are rejected. Swift source is compiled into the app, so adding or changing a View requires an iOS rebuild. Registration is synchronous setup, not a native bridge command.

## 2b. Register Compose content on Android

Android supports **element extensions only**. Standard Ionic and HTML controls stay on the Web, including explicitly marked buttons. Native Vertical Bars and `tab-accessory` are iOS features; Android can combine a Web side rail with element extensions. The same DOM reader, props, action targets, and `markForCheck()` work on both platforms.

Run `npx cap sync android` after installing the plugin. Use Kotlin in your Android app. In the root `build.gradle`, add the Kotlin and Compose compiler plugins to `buildscript.dependencies`, using the same Kotlin version as the app (the plugin defaults to `2.2.20`). Define `ext.kotlin_version = '2.2.20'` in the root `buildscript` if it is not already defined:

```groovy
classpath "org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlin_version"
classpath "org.jetbrains.kotlin:compose-compiler-gradle-plugin:$kotlin_version"
```

In `app/build.gradle`, apply `kotlin-android` and `org.jetbrains.kotlin.plugin.compose`, and enable `android { buildFeatures { compose true } }`. The Native UI dependency exposes Compose UI and Foundation; add Material dependencies yourself if your extension uses them.

Register once from your `Application.onCreate()`, on the main thread, before JavaScript enables the shell. Use an `Application` subclass configured with `android:name=".App"` on `<application>` in `AndroidManifest.xml`; avoid registering on each Activity recreation.

```kotlin
import android.app.Application
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.*
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import dev.rdlabo.capacitor.nativeui.NativeUI
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

class App : Application() {
    override fun onCreate() {
        super.onCreate()
        NativeUI.register(
            name = "app.counter",
            decode = { json -> json.getInt("count") },
        ) { count, actions, context ->
            val scope = rememberCoroutineScope()
            var error by remember { mutableStateOf<String?>(null) }
            val enabled = actions.isAvailable("increment")
            val foreground = if (context.dark) Color.White else Color.Black
            val background = if (context.dark) Color(0xFF202020) else Color.White
            val textStyle = TextStyle(color = foreground)
            Column(Modifier.fillMaxSize().background(background).padding(8.dp)) {
                BasicText("Count: $count", style = textStyle)
                Box(
                    Modifier.fillMaxWidth().heightIn(min = 48.dp)
                        .alpha(if (enabled) 1f else 0.5f)
                        .clickable(enabled = enabled, role = Role.Button, onClickLabel = "Increment count") {
                            scope.launch {
                                try {
                                    actions.activate("increment")
                                    error = null
                                } catch (cancelled: CancellationException) {
                                    throw cancelled
                                } catch (unavailable: IllegalStateException) {
                                    error = "Action unavailable. Try again."
                                }
                            }
                        },
                    contentAlignment = Alignment.Center,
                ) { BasicText("Increment", style = textStyle) }
                BasicText(
                    error ?: "",
                    modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite },
                    style = textStyle,
                )
            }
        }
    }
}
```

The shell sizes and positions the Compose host from the source DOM rectangle. `context.sourceFrame` contains CSS pixels; `sourceFrameInDp` contains Compose dp, with `dpPerCSSPixel` as the conversion factor. `sourceID` and `viewportWidth` describe the current source and viewport. `rtl` is also applied through `LocalLayoutDirection`; use `dark` to select your app's Compose theme. Do not apply the source's `x` and `y` again inside your content.

The `decode` callback runs before accepting the projection. If it throws, that source stays on the Web. Empty or duplicate registration names are rejected. Compose content owns its styling and accessibility. Rebuild the Android app after changing Kotlin code.

## 3. Enable with local definitions

```ts
import { enableNativeUI } from '@rdlabo/capacitor-native-ui';
import { counter } from './native-ui/counter';

const shell = await enableNativeUI({ ionic: { auto: false }, extensions: [counter] });
```

This example enables your extensions without automatically projecting Ionic controls. Explicit `data-native-ui` sources remain opted in. To also project standard Ionic controls on supported iOS, omit `ionic: { auto: false }`. Android standard controls remain Web-rendered either way.

Replace your existing startup call with the one above; do not start a second shell. Connect it to your framework using the [app-root lifecycle examples](https://docs.rdlabo.dev/projects/capacitor-native-ui/docs/setup#place-startup-in-your-frameworks-app-root), putting these options in the shared startup call.

Keep extension objects stable across repeated enable calls. Changing extensions while running requires `await shell.destroy()` first. Extension names must be unique within an activation. Do not register overlapping selectors for the same source. An extension owns its source subtree, so built-in controls inside it are not projected separately.

## 4. Build and try the extension

Build your Web assets, then sync and rebuild the platform you configured:

- **Android:** run `npx cap sync android`, then build and launch the app from Android Studio. The counter should render with Compose.
- **iOS:** run `npx cap sync ios`, then build and launch the app from Xcode. On iOS 26+, the counter should render with SwiftUI.

Tap Increment: the original Web handler should update `data-count`, and the native count should follow. In a browser, the original Web counter should still work.

For source-specific fallback reasons, temporarily enable [`debug: true`](https://docs.rdlabo.dev/projects/capacitor-native-ui/docs/configuration#understand-why-a-source-stays-on-the-web). If the source stays on the Web, confirm that registration runs before JavaScript enables the shell and that the names and props agree on both sides. On Android, check that your `Application` subclass is declared in the manifest; on iOS, check that the Swift file belongs to the app target.

## Extension reference

- <a id="reader-contract"></a>[Reader contract](native-ui-extension-reference.md#reader-contract)
- <a id="native-scroll-tracking-on-ios-experimental"></a>[Native scroll tracking on iOS (experimental)](native-ui-extension-reference.md#native-scroll-tracking-on-ios-experimental)
- <a id="content-and-placement-are-independent"></a>[Content and placement are independent](native-ui-extension-reference.md#content-and-placement-are-independent)
- <a id="tab-accessory-requirements"></a>[Tab accessory requirements](native-ui-extension-reference.md#tab-accessory-requirements)
- <a id="read-source-geometry-and-presentation-state"></a>[Read source geometry and presentation state](native-ui-extension-reference.md#read-source-geometry-and-presentation-state)
- <a id="use-the-shared-projection-capabilities"></a>[Use the shared projection capabilities](native-ui-extension-reference.md#use-the-shared-projection-capabilities)
- <a id="schedule-a-source-check"></a>[Schedule a source check](native-ui-extension-reference.md#schedule-a-source-check)
- <a id="reuse-native-artwork-and-color-conversion"></a>[Reuse native artwork and color conversion](native-ui-extension-reference.md#reuse-native-artwork-and-color-conversion)
- <a id="lifecycle-and-action-completion"></a>[Lifecycle and action completion](native-ui-extension-reference.md#lifecycle-and-action-completion)
- <a id="action-completion"></a>[Action completion](native-ui-extension-reference.md#action-completion)
- <a id="example-mini-player"></a>[Example: mini-player](native-ui-extension-reference.md#example-mini-player)
