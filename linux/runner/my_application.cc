#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// The size (in logical pixels) of the small icon shown in the GTK header bar.
static const int kHeaderBarIconSize = 24;

// Returns the absolute path of an application icon bundled with the Flutter
// assets (e.g. assets/sds-remote.png). The caller owns the returned string.
static gchar* get_app_icon_path(FlDartProject* project,
                                const gchar* filename) {
  const gchar* assets_path = fl_dart_project_get_assets_path(project);
  if (assets_path == nullptr) {
    return nullptr;
  }
  return g_build_filename(assets_path, "assets", filename, nullptr);
}

// Loads a GdkPixbuf from a bundled asset file, or nullptr if the asset is
// missing or cannot be decoded. The caller owns the returned pixbuf.
static GdkPixbuf* load_app_icon(FlDartProject* project, const gchar* filename) {
  g_autofree gchar* icon_path = get_app_icon_path(project, filename);
  if (icon_path == nullptr) {
    return nullptr;
  }

  g_autoptr(GError) error = nullptr;
  GdkPixbuf* icon = gdk_pixbuf_new_from_file(icon_path, &error);
  if (icon == nullptr) {
    g_warning("Failed to load icon from '%s': %s", icon_path, error->message);
  }
  return icon;
}

// Returns a new reference to [icon] scaled down to a square of at most [size]
// pixels, or nullptr if scaling failed. The caller owns the returned pixbuf.
static GdkPixbuf* scale_icon(GdkPixbuf* icon, int size) {
  const int width = gdk_pixbuf_get_width(icon);
  const int height = gdk_pixbuf_get_height(icon);
  if (width <= size && height <= size) {
    return GDK_PIXBUF(g_object_ref(icon));
  }
  return gdk_pixbuf_scale_simple(icon, size, size, GDK_INTERP_BILINEAR);
}

// Applies the sdsremote icon to the window so it shows up in the title bar,
// the task bar and the window switcher on Linux.
static void apply_window_icon(FlDartProject* project, GtkWindow* window,
                              GtkHeaderBar* header_bar) {
  // The full-size icon is used for the task bar and window switcher.
  GdkPixbuf* icon = load_app_icon(project, "sds-remote.png");
  if (icon != nullptr) {
    gtk_window_set_icon(window, icon);
    gtk_window_set_default_icon(icon);
  }

  // A GTK header bar does not render the window icon on its own, so add a
  // small version of the icon explicitly to the top bar. Prefer the dedicated
  // small asset and scale it down so it does not dominate the header bar.
  if (header_bar != nullptr) {
    GdkPixbuf* small_icon =
        load_app_icon(project, "sds-remote-icon_128_128.png");
    if (small_icon == nullptr) {
      small_icon = icon;  // Fall back to the full-size icon.
      icon = nullptr;     // Ownership was transferred to small_icon.
    }
    if (small_icon != nullptr) {
      g_autoptr(GdkPixbuf) scaled = scale_icon(small_icon, kHeaderBarIconSize);
      GtkWidget* icon_image =
          gtk_image_new_from_pixbuf(scaled != nullptr ? scaled : small_icon);
      gtk_widget_show(icon_image);
      gtk_header_bar_pack_start(header_bar, icon_image);
      g_object_unref(small_icon);
    }
  }

  if (icon != nullptr) {
    g_object_unref(icon);
  }
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  GtkHeaderBar* header_bar = nullptr;
  if (use_header_bar) {
    header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "sdsremote");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "sdsremote");
  }

  gtk_window_set_default_size(window, 1400, 900);
  
  // Set minimum window size
  GdkGeometry hints = {0};
  hints.min_width = 1400;
  hints.min_height = 900;
  gtk_window_set_geometry_hints(window, NULL, &hints, GDK_HINT_MIN_SIZE);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  // Show the sdsremote icon in the window title bar and task bar.
  apply_window_icon(project, window, header_bar);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
