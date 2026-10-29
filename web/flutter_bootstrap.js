{{flutter_js}}
{{flutter_build_config}}

// Vedno ista različica CanvasKit, da vodja na špilu iPadom ponudi manj datotek (glej android.yml).
_flutter.loader.load({
  config: { canvasKitVariant: "full" },
});
