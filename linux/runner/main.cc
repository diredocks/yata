#include <glib.h>

#include "my_application.h"

int main(int argc, char** argv) {
  // Flutter Linux 3.50+ renders FlView into a Wayland wl_subsurface stacked
  // above the GTK window's wl_surface, which hides GTK overlay children such
  // as webview_all_linux's WebKitWebView. Force X11 (XWayland) unless the
  // caller explicitly overrides GDK_BACKEND.
  g_setenv("GDK_BACKEND", "x11", FALSE);

  g_autoptr(MyApplication) app = my_application_new();
  return g_application_run(G_APPLICATION(app), argc, argv);
}
