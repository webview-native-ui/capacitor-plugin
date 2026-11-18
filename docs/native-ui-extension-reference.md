# App-local Native UI extension reference (experimental)

For a working counter on iOS or Android, follow the [extension setup guide](native-ui-extensions.md).

## Reader contract

| Part           | Requirement                                                                                                    |
| -------------- | -------------------------------------------------------------------------------------------------------------- |
| Execution      | Synchronous and read-only.                                                                                     |
| Web fallback   | Return `null` when the source should stay on the Web.                                                          |
| `props`        | JSON object containing finite numbers, strings, booleans, null, arrays and objects; limited to 64K characters. |
| Action targets | The source itself or its descendants. Missing, hidden and disabled targets cannot be activated.                |
| Action count   | Up to 30 per source.                                                                                           |

## Native scroll tracking on iOS (experimental)

For an element inside a single overflow scroller, supply `scrollElement`. The Web side measures layout; iOS observes the matching `UIScrollView` and updates only native position and clipping during scrolling. Sources in the same container share one observer. The binding calibrates DOM/native coordinate origins while the scroller is at rest, then retains that mapping across content updates. Partially visible controls remain native, and fully clipped controls cannot receive input.

```ts
const scrollElement = await ionContent.getScrollElement();
const counter = defineNativeUI({
  name: 'app.counter',
  selector: '[data-counter]',
  scrollElement: () => scrollElement,
  read(element) {
    return {
      props: { count: Number(element.getAttribute('data-count') ?? 0) },
      actions: { increment: element.querySelector<HTMLButtonElement>('button') },
    };
  },
});
```

With plain HTML, return the element with `overflow: auto` or `scroll`. Return `null` until it is ready, then call `shell.markForCheck()` if readiness did not change the DOM. Keep source dimensions and content-layout changes observable; use `markForCheck()` for changes the shell cannot observe.

This uses WebKit's internal overflow-view hierarchy without private class names. A binding must match exactly one native scroller; missing or ambiguous matches keep the interactive Web source. Nested scrolling, rounded or shaped clipping, CSS transforms/zoom, sticky/fixed descendants, document scrolling, older native binaries and Android are not supported by this opt-in. Omit `scrollElement` to keep the existing JS-based placement path. Other unbound projection sources inside the same scroller still require ordinary layout synchronization. Each `scrollend` performs one reconciliation through the normal update/acknowledgement path, including retries after a temporary binding refusal.

`NativeUIContext.sourceFrame` is the latest layout sample, not a per-scroll notification. Native tracking does not rebuild SwiftUI content for scroll offsets. Fixed tab accessories do not use this binding. Web Modal transforms remain on their existing handoff path; noninteractive covered content can use prepared images, while interactive scrolling content stays native.

## Content and placement are independent

| `placement`            | Behavior                                                                              |
| ---------------------- | ------------------------------------------------------------------------------------- |
| Omitted or `'element'` | Hosts native content in the source element's Web frame on iOS 26+ or Android API 24+. |
| `'tab-accessory'`      | Attaches the View to a projected tab bar's system SwiftUI tab accessory on iOS 26.1+. |

Extensions are independent of `controls` and `ionic.auto`, including with `enableVerticalControlArea()`. The application controls their presentation: return `null` from the reader when a source should stay on the Web, then call `markForCheck()` when that condition changes. Accessories still require their supported native tab host.

### Tab accessory requirements

| Requirement         | Supported configuration                                                                           |
| ------------------- | ------------------------------------------------------------------------------------------------- |
| Source location     | Inside its owning `ion-tabs`; the shell resolves that element's `ion-tab-bar`.                    |
| Native host         | Vertical Bars SwiftUI tab host on iOS 26.1+.                                                      |
| Accessory count     | A single accessory for the host.                                                                  |
| Web fallback layout | Keep an equivalent Web layout, such as a fixed footer; the source retains its space while hidden. |

Ordinary UIKit tab bars, missing native tabs, iOS 26.0 or competing accessories keep the source on the Web. Applications do not pass native controller references, and the shell does not approximate a system accessory with a floating overlay.

## Read source geometry and presentation state

The shell measures the source DOM element automatically. With the default `element` placement, it positions and sizes the SwiftUI host to match that rectangle. You do not need to send coordinates in `props` or position the native view yourself.

Use the three-argument registration closure to receive that information:

```swift
try NativeUI.register("app.counter") {
    (props: CounterProps, actions: NativeUIActions, context: NativeUIContext) in
    CounterView(props: props, actions: actions)
        .padding(.horizontal, context.sourceFrame.width < 240 ? 4 : 12)
}
```

The existing `(props, actions)` closure remains supported. Both forms use the same registration names and duplicate-name checks.

| Context property       | Meaning                                                                                                              |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------- |
| `sourceID`             | Opaque source identity for its current lifetime; not the HTML `id`.                                                  |
| `sourceFrame`          | DOM `getBoundingClientRect()` in CSS pixels relative to the Web viewport, including `x`, `y`, `width`, and `height`. |
| `sourceFrameInWebView` | The source rectangle converted to UIKit points in the WebView's local coordinate system; not screen coordinates.     |
| `viewportWidth`        | CSS viewport width used for that snapshot's coordinate conversion.                                                   |
| `pointsPerCSSPixel`    | UIKit points per CSS pixel; not device pixel density.                                                                |
| `placement`            | `.element` or `.tabAccessory`.                                                                                       |
| `colorScheme`          | `.light` or `.dark`, also applied to the SwiftUI environment.                                                        |
| `layoutDirection`      | `.leftToRight` or `.rightToLeft`, also applied to the SwiftUI environment.                                           |

The closure receives a fresh context when the shell applies an updated snapshot, including source movement, resizing, and appearance changes. Use the current context rather than caching its geometry in `@State`. Updates cross the Web/native bridge; they are not a synchronous DOM measurement from Swift.

For `tabAccessory`, `sourceFrame` still describes the original DOM element. The system assigns the accessory's actual location and size. Use SwiftUI's `GeometryReader` inside your View for the actual local space in either placement:

```swift
GeometryReader { geometry in
    CounterView(props: props, actions: actions)
        .frame(width: geometry.size.width, height: geometry.size.height)
}
```

Do not apply `sourceFrame.x` or `y` as another SwiftUI offset: the shell already positions the host for `element`. Your View lays out its contents within that host.

## Use the shared projection capabilities

| Capability                          | How an extension uses it                                                                                                                                  |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Position and size                   | Automatic host placement plus `NativeUIContext`; actual local bounds through `GeometryReader`.                                                            |
| Dark mode and RTL                   | `context` or SwiftUI `@Environment(\.colorScheme)` and `@Environment(\.layoutDirection)`.                                                                 |
| Reduce Motion and accessibility     | SwiftUI environment values such as `@Environment(\.accessibilityReduceMotion)` and native accessibility modifiers. Give custom controls accessible names. |
| DOM-backed application state        | Return JSON `props` from `read(element)`; DOM changes trigger synchronization. For changes without a DOM mutation, call `shell.markForCheck()`.           |
| Enabled/visible action targets      | `actions.availableNames` or `actions.isAvailable("increment")`; unavailable DOM targets are omitted.                                                      |
| Invoke the original Web action      | `try await actions.activate("increment")`; completion and failure follow the contract below.                                                              |
| Temporary Web fallback and teardown | Managed automatically for unsupported content, overlays, navigation suspension, and source removal.                                                       |
| Application-controlled suspension   | Use the shell handle's `suspend()`, the returned token's `resume()`, and `destroy()` from JavaScript.                                                     |

For example, disable a native button when its original action is unavailable:

```swift
Button("Increment") {
    Task { @MainActor in
        do { try await actions.activate("increment") }
        catch { /* Present an application-appropriate error. */ }
    }
}
.disabled(!actions.isAvailable("increment"))
```

Availability is a snapshot, not a reservation: a target can disappear before activation, so handle errors too. Custom text, selected state, fonts, colors, and badges belong in your extension's `props` and SwiftUI View; the shell does not infer a custom component's visual structure from CSS. Read the desired element's computed styles and attributes in your reader. Use the shared image and color conversion APIs below instead of reimplementing those transformations.

## Schedule a source check

DOM attributes, text, children, observed element sizes, scrolling, and supported lifecycle events trigger automatic checks. The shell does not poll JavaScript variables or arbitrary DOM properties. After changing state that your reader uses without a DOM mutation, request a check:

```ts
source.playbackPosition = newPosition; // An application-defined property read by your extension.
shell.markForCheck();
```

`markForCheck(): void` schedules a re-read and geometry measurement; it does not update the application's DOM or force a native redraw. Repeated calls are batched, and unchanged snapshots are not sent. A call during a bridge update schedules another check afterwards. Suspended projection stays suspended until resumed. Calls after `destroy()` or in an environment without a projection runtime do nothing.

Call after your framework has committed any relevant DOM changes. This API does not trigger Angular change detection, React rendering, or Vue rendering, and it is not a promise that waits for native completion. It also works for standard controls when their properties change without an observable mutation.

## Reuse native artwork and color conversion

A reader's second argument exposes the standard SVG capture and rasterization path. It accepts a local `svg` or a resolved `ion-icon` belonging to the source and returns an **opaque image reference**, or `null` for unsupported artwork. Return the reference in `props`; do not try to read image bytes synchronously:

```ts
const badge = defineNativeUI({
  name: 'app.badge',
  selector: '[data-badge]',
  read(element, context) {
    return {
      props: {
        icon: context.image(element.querySelector<HTMLElement>('ion-icon')),
        color: getComputedStyle(element).color,
      },
    };
  },
});
```

Before sending the snapshot, the shell resolves references into `{ data, width, height, template }`: base64 PNG data, CSS dimensions, and rendering mode. Nested references and copies are supported; the `$nativeUIImage` key is reserved for references returned by the current read context. Use `{ template: true }` as the second argument to `image()` when SwiftUI should tint the icon; the default preserves source colors. The same local SVG restrictions, RTL capture, display-scale rasterization, and image cache used by standard controls apply. External resources and unsupported SVG content return `null`; unresolved `ion-icon` content should retain your Web fallback until loaded. Rasterization failure or props exceeding the size limit keeps that extension on the Web.

On iOS, decode the resulting value with `NativeUIImage` and use the shared converters:

```swift
struct BadgeProps: Decodable {
    let icon: NativeUIImage?
    let color: String
}

struct BadgeView: View {
    let props: BadgeProps
    var body: some View {
        if let icon = props.icon, let image = NativeUIRendering.image(icon) {
            Image(uiImage: image)
                .foregroundStyle(Color(uiColor: NativeUIRendering.color(props.color)))
        }
    }
}
```

`NativeUIRendering.image` returns `nil` for invalid image data. `NativeUIRendering.color` accepts computed `rgb()`/`rgba()` values; unsupported formats use `.label`, or the `fallback:` color you pass. Both are shared with the standard native renderers. They do not evaluate CSS selectors, variables, named colors, or arbitrary stylesheets.

## Lifecycle and action completion

The shell owns discovery, geometry, state synchronization, native controller containment, overlay retirement, suspension and teardown. Extensions do not implement attach/detach hooks. Web sources are hidden only after native accepts the projection. An unregistered renderer, a failing props decoder, unsupported placement or failed reader leaves that instance on the Web. Existing shell overlay policy applies; extensions return to the Web while Web overlays cover the page.

Element placement requires the source to fit fully inside the viewport and its ancestors' overflow clipping bounds, including Ionic's shadow scroll containers. Partially clipped sources stay on the Web and become eligible again when scrolled fully into view. Tab accessories use the system host's placement instead.

### Action completion

| Event                                                              | Result of `try await actions.activate(name)` |
| ------------------------------------------------------------------ | -------------------------------------------- |
| Original Web element receives its click                            | Completes.                                   |
| Handler starts a network request, navigation or modal presentation | Does not wait for that application work.     |
| Action is disabled, removed or stale                               | Rejects.                                     |
| Teardown, native task cancellation or bridge timeout               | Settles pending calls.                       |

The bridge acknowledgement is a Capacitor Promise method.

The [demo reader](https://github.com/webview-native-ui/ionic-theme-ios27/blob/main/demo/src/native-ui/counter.ts) and [demo SwiftUI View](https://github.com/webview-native-ui/ionic-theme-ios27/blob/main/demo/ios/App/App/NativeUICounter.swift) show both placements using app-local files. Open the Native UI demo page to compare native projection with its Web fallback.

## Example: mini-player

The demo mini-player shows the same pattern with track metadata and playback actions: a [DOM reader and Web fallback](https://github.com/webview-native-ui/ionic-theme-ios27/blob/main/demo/src/native-ui/mini-player.ts) paired with an [app-local SwiftUI View](https://github.com/webview-native-ui/ionic-theme-ios27/blob/main/demo/ios/App/App/NativeMiniPlayer.swift). The Web app owns playback state and modal presentation; native `open` and `toggle` actions activate its original buttons. This is a UI example, not an audio engine. Adapt the files after completing the [extension setup](native-ui-extensions.md).
