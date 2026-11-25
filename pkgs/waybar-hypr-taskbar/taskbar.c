#define _GNU_SOURCE

#include "waybar_cffi_module.h"

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <gio/gdesktopappinfo.h>
#include <gio/gio.h>
#include <json-c/json.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/un.h>
#include <unistd.h>

/* --------------------------------------------------------------------------
 * Event-driven Waybar CFFI taskbar for Hyprland 0.57+
 *
 * - Renders real per-app GTK icons resolved from installed .desktop files /
 *   GtkIconTheme (never generic category glyphs).
 * - Strictly filters to mapped, non-hidden windows on the active workspace,
 *   plus that workspace's *minimized* windows: minimized clients live on the
 *   hidden `special:minimized` workspace and are tagged `minimized-ws-<N>`
 *   with the workspace they were minimized from (see the SUPER+N bind in
 *   modules/hyprland-home.nix). Windows minimized from another workspace are
 *   never listed.
 * - Lays out across the *whole* span GTK allocates to the module: Waybar gives
 *   `cffi/taskbar` every pixel between modules-left (workspaces + layout) and
 *   modules-right (tray/net/bat/mem/clock) via `expand = true`, and the bar
 *   splits that span into equal, homogeneous slots (overflow collapses into a
 *   trailing `+N` chip). The focused monitor's logical width is only a fallback
 *   for the first frame, before the module has been allocated.
 * - Left-click focuses a visible window and restores + focuses a minimized
 *   one; middle-click minimizes a visible one; scroll cycles windows.
 * -------------------------------------------------------------------------- */

static const int LEFT_RESERVE_PX = 340;
static const int RIGHT_RESERVE_PX = 560;
static const int MIN_AVAIL_PX = 180;
static const int MIN_SLOT_PX = 52;
/* Horizontal chrome (CSS padding of `#hypr-taskbar`) that eats into the span. */
static const int TASKBAR_CHROME_PX = 8;
static const int DEFAULT_ICON_SIZE = 18;

/* Minimized windows are parked here by modules/hyprland-home.nix. */
#define MINIMIZED_WS_PREFIX "special:minimized"
#define MINIMIZED_TAG_PREFIX "minimized-ws-"

/* Sentinel for "no active workspace yet" (never a real Hyprland id). */
static const int NO_WORKSPACE = -999999;

typedef struct {
  char *address;
  char *title;
  char *wclass;
  char *initial_class;
  gboolean minimized;
} ClientInfo;

typedef struct {
  wbcffi_module *waybar_module;
  /* `scroll_box` wraps `box` so GTK3 delivers `scroll-event` to us (over the
   * buttons *and* over the gaps between them) before Waybar's own root event
   * box, whose `AModule::handleScroll` is connected earlier and consumes it. */
  GtkWidget *scroll_box;
  /* Waybar's container for this module: the widget whose allocation is the
   * full span we get to fill. */
  GtkWidget *root;
  GtkBox *box;
  int icon_size;

  /* Last full-span width reported by `size-allocate` (0 = not yet known). */
  int span_px;

  /* Workspace of the last render; click handlers restore/minimize into it. */
  int active_ws_id;

  char *sock_path;
  char *event_path;

  int event_fd;
  GIOChannel *event_chan;
  guint event_watch_id;
  GString *event_buf;

  guint reconnect_id;
  guint render_id;
  guint recheck_id;

  GPtrArray *order;       /* char* addresses, stable workspace order */
  GHashTable *icon_cache; /* "class\x1finitClass" -> GIcon* (ref'd) */
  GList *desktop_apps;    /* GList of GAppInfo* */
  gulong theme_changed_id;
  gulong scroll_id;
  gulong root_alloc_id;
} TaskbarMod;

static void schedule_render(TaskbarMod *mod);

static void client_info_free(gpointer data) {
  ClientInfo *c = (ClientInfo *)data;
  if (!c) return;
  g_free(c->address);
  g_free(c->title);
  g_free(c->wclass);
  g_free(c->initial_class);
  g_free(c);
}

/* ---- String normalization helpers for .desktop / icon matching ---- */

static char *str_lower_dup(const char *s) {
  if (!s) return g_strdup("");
  return g_ascii_strdown(s, -1);
}

static char *str_alnum_lower(const char *s) {
  if (!s) return g_strdup("");
  GString *out = g_string_new(NULL);
  for (const unsigned char *p = (const unsigned char *)s; *p; p++) {
    if (isalnum(*p)) {
      g_string_append_c(out, (char)tolower(*p));
    }
  }
  return g_string_free(out, FALSE);
}

static const char *last_dot_segment(const char *s) {
  if (!s) return "";
  const char *dot = strrchr(s, '.');
  return (dot && dot[1] != '\0') ? dot + 1 : s;
}

static char *strip_desktop_suffix(const char *id) {
  if (!id) return g_strdup("");
  size_t len = strlen(id);
  if (len > 8 && g_ascii_strcasecmp(id + len - 8, ".desktop") == 0) {
    return g_strndup(id, len - 8);
  }
  return g_strdup(id);
}

static char *exec_basename(const char *exec_str) {
  if (!exec_str || !*exec_str) return g_strdup("");
  while (*exec_str && isspace((unsigned char)*exec_str)) exec_str++;
  const char *end = exec_str;
  if (*exec_str == '"' || *exec_str == '\'') {
    char q = *exec_str++;
    end = strchr(exec_str, q);
    if (!end) end = exec_str + strlen(exec_str);
  } else {
    while (*end && !isspace((unsigned char)*end)) end++;
  }
  char *tok = g_strndup(exec_str, (gsize)(end - exec_str));
  char *base = g_path_get_basename(tok);
  g_free(tok);
  return base;
}

static char *strip_common_app_suffix(const char *s) {
  static const char *const suffixes[] = {
      "-desktop", "-browser", "-bin", ".bin", "-wrapped", NULL,
  };
  char *low = str_lower_dup(s);
  size_t len = strlen(low);
  for (int i = 0; suffixes[i]; i++) {
    size_t slen = strlen(suffixes[i]);
    if (len > slen && strcmp(low + len - slen, suffixes[i]) == 0) {
      low[len - slen] = '\0';
      break;
    }
  }
  return low;
}

static char *name_before_paren_alnum(const char *name) {
  if (!name) return g_strdup("");
  const char *p = strchr(name, '(');
  char *prefix = p ? g_strndup(name, (gsize)(p - name)) : g_strdup(name);
  char *folded = str_alnum_lower(prefix);
  g_free(prefix);
  return folded;
}

/* Score how well a GDesktopAppInfo matches a candidate token (higher = better). */
static int score_desktop_match(GDesktopAppInfo *dapp, const char *cand) {
  if (!cand || !*cand) return 0;

  char *cand_low = str_lower_dup(cand);
  const char *cand_seg = last_dot_segment(cand_low);
  char *cand_alnum = str_alnum_lower(cand_low);
  char *cand_seg_alnum = str_alnum_lower(cand_seg);
  char *cand_stripped = strip_common_app_suffix(cand_low);

  int best = 0;

  const char *wm_class = g_desktop_app_info_get_startup_wm_class(dapp);
  if (wm_class && *wm_class) {
    char *wm_low = str_lower_dup(wm_class);
    const char *wm_seg = last_dot_segment(wm_low);
    char *wm_alnum = str_alnum_lower(wm_low);
    if (strcmp(wm_low, cand_low) == 0) {
      best = MAX(best, 100);
    } else if (strcmp(wm_low, cand_seg) == 0 || strcmp(wm_seg, cand_low) == 0 ||
               strcmp(wm_seg, cand_seg) == 0) {
      best = MAX(best, 90);
    } else if (*cand_seg_alnum && strcmp(wm_alnum, cand_seg_alnum) == 0) {
      best = MAX(best, 85);
    }
    g_free(wm_low);
    g_free(wm_alnum);
  }

  const char *id = g_app_info_get_id(G_APP_INFO(dapp));
  if (id && *id) {
    char *stem = strip_desktop_suffix(id);
    char *stem_low = str_lower_dup(stem);
    const char *stem_seg = last_dot_segment(stem_low);
    char *stem_alnum = str_alnum_lower(stem_low);
    char *stem_seg_alnum = str_alnum_lower(stem_seg);
    if (strcmp(stem_low, cand_low) == 0) {
      best = MAX(best, 95);
    } else if (strcmp(stem_low, cand_seg) == 0 ||
               strcmp(stem_seg, cand_low) == 0 ||
               strcmp(stem_seg, cand_seg) == 0) {
      best = MAX(best, 88);
    } else if (strcmp(stem_low, cand_stripped) == 0 ||
               strcmp(stem_seg, cand_stripped) == 0) {
      best = MAX(best, 82);
    } else if (*cand_seg_alnum &&
               (strcmp(stem_alnum, cand_alnum) == 0 ||
                strcmp(stem_seg_alnum, cand_seg_alnum) == 0 ||
                strcmp(stem_alnum, cand_seg_alnum) == 0)) {
      best = MAX(best, 80);
    }
    g_free(stem);
    g_free(stem_low);
    g_free(stem_alnum);
    g_free(stem_seg_alnum);
  }

  const char *exec_str = g_app_info_get_executable(G_APP_INFO(dapp));
  if (exec_str && *exec_str) {
    char *base = exec_basename(exec_str);
    char *base_low = str_lower_dup(base);
    char *base_stripped = strip_common_app_suffix(base_low);
    if (strcmp(base_low, cand_low) == 0 || strcmp(base_low, cand_seg) == 0) {
      best = MAX(best, 78);
    } else if (strcmp(base_stripped, cand_low) == 0 ||
               strcmp(base_stripped, cand_seg) == 0 ||
               strcmp(base_stripped, cand_stripped) == 0) {
      best = MAX(best, 74);
    }
    g_free(base);
    g_free(base_low);
    g_free(base_stripped);
  }

  const char *name = g_app_info_get_name(G_APP_INFO(dapp));
  if (name && *name) {
    char *name_alnum = str_alnum_lower(name);
    char *name_short = name_before_paren_alnum(name);
    if (*cand_seg_alnum &&
        (strcmp(name_alnum, cand_alnum) == 0 ||
         strcmp(name_short, cand_alnum) == 0 ||
         strcmp(name_short, cand_seg_alnum) == 0)) {
      best = MAX(best, 70);
    }
    g_free(name_alnum);
    g_free(name_short);
  }

  g_free(cand_low);
  g_free(cand_alnum);
  g_free(cand_seg_alnum);
  g_free(cand_stripped);
  return best;
}

static GIcon *resolve_app_gicon(TaskbarMod *mod, const char *wclass,
                                const char *initial_class) {
  char *cache_key =
      g_strdup_printf("%s\x1f%s", wclass ? wclass : "",
                      initial_class ? initial_class : "");
  GIcon *cached = (GIcon *)g_hash_table_lookup(mod->icon_cache, cache_key);
  if (cached) {
    g_free(cache_key);
    return g_object_ref(cached);
  }

  if (!mod->desktop_apps) {
    mod->desktop_apps = g_app_info_get_all();
  }

  GIcon *best_icon = NULL;
  int best_score = 0;

  for (GList *l = mod->desktop_apps; l != NULL; l = l->next) {
    if (!G_IS_DESKTOP_APP_INFO(l->data)) continue;
    GDesktopAppInfo *dapp = G_DESKTOP_APP_INFO(l->data);
    GIcon *icon = g_app_info_get_icon(G_APP_INFO(dapp));
    if (!icon) continue;

    int s1 = score_desktop_match(dapp, wclass);
    int s2 = score_desktop_match(dapp, initial_class);
    int score = MAX(s1, s2);
    if (score > best_score) {
      best_score = score;
      best_icon = icon;
    }
  }

  GIcon *result = NULL;
  if (best_icon && best_score >= 70) {
    result = g_object_ref(best_icon);
  } else {
    /* Try direct GtkIconTheme lookup for class / initialClass / last segment */
    GtkIconTheme *theme = gtk_icon_theme_get_default();
    const char *raw_cands[2] = {wclass, initial_class};
    for (int i = 0; i < 2 && !result; i++) {
      if (!raw_cands[i] || !*raw_cands[i]) continue;
      char *low = str_lower_dup(raw_cands[i]);
      const char *seg = last_dot_segment(low);
      char *stripped = strip_common_app_suffix(low);
      const char *tries[4] = {raw_cands[i], low, seg, stripped};
      for (int j = 0; j < 4; j++) {
        if (tries[j] && *tries[j] && gtk_icon_theme_has_icon(theme, tries[j])) {
          result = g_themed_icon_new(tries[j]);
          break;
        }
      }
      g_free(low);
      g_free(stripped);
    }
  }

  if (!result) {
    result = g_themed_icon_new("application-x-executable");
  }

  g_hash_table_insert(mod->icon_cache, cache_key, g_object_ref(result));
  return result;
}

static GtkWidget *make_icon_widget(TaskbarMod *mod, const char *wclass,
                                   const char *initial_class) {
  GIcon *gicon = resolve_app_gicon(mod, wclass, initial_class);
  GtkIconTheme *theme = gtk_icon_theme_get_default();
  int scale = mod->box ? gtk_widget_get_scale_factor(GTK_WIDGET(mod->box)) : 1;
  if (scale < 1) scale = 1;

  GtkWidget *img = NULL;
  GtkIconInfo *info = gtk_icon_theme_lookup_by_gicon_for_scale(
      theme, gicon, mod->icon_size, scale, GTK_ICON_LOOKUP_FORCE_SIZE);
  if (info) {
    GError *err = NULL;
    GdkPixbuf *pb = gtk_icon_info_load_icon(info, &err);
    g_object_unref(info);
    if (pb) {
      /* Guard against oversized SVG/PNG icons that ignored FORCE_SIZE */
      int target_px = mod->icon_size * scale;
      if (gdk_pixbuf_get_width(pb) != target_px ||
          gdk_pixbuf_get_height(pb) != target_px) {
        GdkPixbuf *scaled = gdk_pixbuf_scale_simple(pb, target_px, target_px,
                                                    GDK_INTERP_BILINEAR);
        if (scaled) {
          g_object_unref(pb);
          pb = scaled;
        }
      }
      cairo_surface_t *surf =
          gdk_cairo_surface_create_from_pixbuf(pb, scale, NULL);
      g_object_unref(pb);
      if (surf) {
        img = gtk_image_new_from_surface(surf);
        cairo_surface_destroy(surf);
      }
    }
    if (err) g_error_free(err);
  }

  if (!img) {
    img = gtk_image_new_from_gicon(gicon, GTK_ICON_SIZE_MENU);
    gtk_image_set_pixel_size(GTK_IMAGE(img), mod->icon_size);
  }

  g_object_unref(gicon);
  return img;
}

/* ---- Hyprland IPC helpers ---- */

static char *hypr_ipc_query(const char *sock_path, const char *cmd) {
  if (!sock_path || !cmd) return NULL;

  int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (fd < 0) return NULL;

  struct timeval tv = {.tv_sec = 1, .tv_usec = 0};
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  if (strlen(sock_path) >= sizeof(addr.sun_path)) {
    close(fd);
    return NULL;
  }
  strcpy(addr.sun_path, sock_path);

  if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
    close(fd);
    return NULL;
  }

  size_t len = strlen(cmd);
  size_t written = 0;
  while (written < len) {
    ssize_t n = write(fd, cmd + written, len - written);
    if (n <= 0) {
      if (n < 0 && errno == EINTR) continue;
      close(fd);
      return NULL;
    }
    written += (size_t)n;
  }

  GString *resp = g_string_new(NULL);
  char buf[8192];
  for (;;) {
    ssize_t n = read(fd, buf, sizeof(buf));
    if (n > 0) {
      g_string_append_len(resp, buf, n);
    } else if (n == 0) {
      break;
    } else {
      if (errno == EINTR) continue;
      break;
    }
  }
  close(fd);
  return g_string_free(resp, FALSE);
}

static struct json_object *hypr_ipc_json(const char *sock_path,
                                         const char *cmd) {
  char *raw = hypr_ipc_query(sock_path, cmd);
  if (!raw) return NULL;
  struct json_object *obj = json_tokener_parse(raw);
  g_free(raw);
  return obj;
}

static const char *json_get_str(struct json_object *obj, const char *key,
                                const char *fallback) {
  struct json_object *val = NULL;
  if (obj && json_object_object_get_ex(obj, key, &val) &&
      json_object_is_type(val, json_type_string)) {
    const char *s = json_object_get_string(val);
    return s ? s : fallback;
  }
  return fallback;
}

static int json_get_int(struct json_object *obj, const char *key,
                        int fallback) {
  struct json_object *val = NULL;
  if (obj && json_object_object_get_ex(obj, key, &val)) {
    return json_object_get_int(val);
  }
  return fallback;
}

static double json_get_double(struct json_object *obj, const char *key,
                              double fallback) {
  struct json_object *val = NULL;
  if (obj && json_object_object_get_ex(obj, key, &val)) {
    return json_object_get_double(val);
  }
  return fallback;
}

static gboolean json_get_bool(struct json_object *obj, const char *key,
                              gboolean fallback) {
  struct json_object *val = NULL;
  if (obj && json_object_object_get_ex(obj, key, &val)) {
    return json_object_get_boolean(val) ? TRUE : FALSE;
  }
  return fallback;
}

/* Collapse runs of whitespace / newlines for clean single-line labels. */
static char *clean_title(const char *raw, const char *fallback) {
  const char *src = (raw && *raw) ? raw : (fallback && *fallback ? fallback : "window");
  GString *out = g_string_new(NULL);
  gboolean prev_space = TRUE;
  for (const unsigned char *p = (const unsigned char *)src; *p; p++) {
    if (*p == '\n' || *p == '\r' || *p == '\t' || *p == ' ') {
      if (!prev_space) {
        g_string_append_c(out, ' ');
        prev_space = TRUE;
      }
    } else {
      g_string_append_c(out, (char)*p);
      prev_space = FALSE;
    }
  }
  while (out->len > 0 && out->str[out->len - 1] == ' ') {
    g_string_truncate(out, out->len - 1);
  }
  if (out->len == 0) {
    g_string_assign(out, (fallback && *fallback) ? fallback : "window");
  }
  return g_string_free(out, FALSE);
}

/* ---- GTK click / scroll callbacks ---- */

/* Fire a Lua dispatcher on Hyprland's command socket and drop the reply. */
static void hypr_dispatch(TaskbarMod *mod, const char *cmd) {
  if (!mod || !mod->sock_path || !cmd) return;
  char *resp = hypr_ipc_query(mod->sock_path, cmd);
  g_free(resp);
}

static void dispatch_clear_tags(TaskbarMod *mod, const char *addr) {
  char *cmd = g_strdup_printf(
      "dispatch hl.dsp.window.clear_tags({ window = \"address:%s\" })", addr);
  hypr_dispatch(mod, cmd);
  g_free(cmd);
}

/* Park `addr` on special:minimized, tagged with the workspace it left so the
 * taskbar can list it there and nowhere else. */
static void dispatch_minimize(TaskbarMod *mod, const char *addr) {
  char *cmd;

  dispatch_clear_tags(mod, addr);

  cmd = g_strdup_printf(
      "dispatch hl.dsp.window.tag({ tag = \"" MINIMIZED_TAG_PREFIX "%d\", "
      "window = \"address:%s\" })",
      mod->active_ws_id, addr);
  hypr_dispatch(mod, cmd);
  g_free(cmd);

  cmd = g_strdup_printf(
      "dispatch hl.dsp.window.move({ workspace = \"" MINIMIZED_WS_PREFIX
      "\", follow = false, window = \"address:%s\" })",
      addr);
  hypr_dispatch(mod, cmd);
  g_free(cmd);
}

/* Move a minimized window back onto the active workspace. `follow = true`
 * also focuses it (and closes the minimize workspace when it is being peeked
 * at), so no separate focus dispatch is needed — and focusing it while it is
 * still parked there would open the special workspace instead. */
static void dispatch_restore(TaskbarMod *mod, const char *addr) {
  char *cmd;

  dispatch_clear_tags(mod, addr);

  cmd = g_strdup_printf(
      "dispatch hl.dsp.window.move({ workspace = %d, follow = true, "
      "window = \"address:%s\" })",
      mod->active_ws_id, addr);
  hypr_dispatch(mod, cmd);
  g_free(cmd);
}

static void dispatch_focus(TaskbarMod *mod, const char *addr) {
  char *cmd = g_strdup_printf(
      "dispatch hl.dsp.focus({ window = \"address:%s\" })", addr);
  hypr_dispatch(mod, cmd);
  g_free(cmd);
}

static const char *task_addr(GtkWidget *widget) {
  const char *addr = (const char *)g_object_get_data(G_OBJECT(widget), "hypr-addr");
  return (addr && *addr) ? addr : NULL;
}

static gboolean task_is_minimized(GtkWidget *widget) {
  return g_object_get_data(G_OBJECT(widget), "hypr-minimized") != NULL;
}

/* Left click: focus a visible window, restore a minimized one. */
static void on_task_clicked(GtkButton *btn, gpointer user_data) {
  TaskbarMod *mod = (TaskbarMod *)user_data;
  GtkWidget *widget = GTK_WIDGET(btn);
  const char *addr = task_addr(widget);
  if (!mod || !mod->sock_path || !addr) return;

  if (task_is_minimized(widget)) {
    if (mod->active_ws_id == NO_WORKSPACE) return;
    dispatch_restore(mod, addr);
    return;
  }
  dispatch_focus(mod, addr);
}

/* Middle click on a visible window minimizes it (left click on an already
 * active window therefore keeps focusing instead of surprising the user). */
static gboolean on_task_button_press(GtkWidget *widget, GdkEventButton *ev,
                                     gpointer user_data) {
  TaskbarMod *mod = (TaskbarMod *)user_data;
  if (!mod || !mod->sock_path || !ev) return FALSE;
  if (ev->type != GDK_BUTTON_PRESS || ev->button != 2) return FALSE;
  if (task_is_minimized(widget)) return FALSE;

  const char *addr = task_addr(widget);
  if (!addr || mod->active_ws_id == NO_WORKSPACE) return FALSE;

  dispatch_minimize(mod, addr);
  return TRUE;
}

static gboolean on_taskbar_scroll(GtkWidget *widget, GdkEventScroll *ev,
                                  gpointer user_data) {
  (void)widget;
  TaskbarMod *mod = (TaskbarMod *)user_data;
  if (!mod || !mod->sock_path || !ev) return FALSE;

  const char *cmd = NULL;
  if (ev->direction == GDK_SCROLL_UP ||
      (ev->direction == GDK_SCROLL_SMOOTH && ev->delta_y < 0)) {
    cmd = "dispatch hl.dsp.window.cycle_next()";
  } else if (ev->direction == GDK_SCROLL_DOWN ||
             (ev->direction == GDK_SCROLL_SMOOTH && ev->delta_y > 0)) {
    cmd = "dispatch hl.dsp.window.cycle_next({ next = false })";
  }
  if (cmd) {
    char *resp = hypr_ipc_query(mod->sock_path, cmd);
    g_free(resp);
    return TRUE;
  }
  return FALSE;
}

/* ---- Render active-workspace taskbar with hard width cap ---- */

/* Does this minimized client belong to workspace `ws_id`?
 *
 * Minimized windows are tagged `minimized-ws-<N>` with the workspace they were
 * minimized from (see modules/hyprland-home.nix). A window parked on
 * special:minimized without such a tag predates the tagging (or was parked by
 * hand): its workspace is unknown, so it is listed on every workspace rather
 * than becoming unreachable. */
static gboolean minimized_on_workspace(struct json_object *client, int ws_id) {
  struct json_object *tags = NULL;
  if (!json_object_object_get_ex(client, "tags", &tags) ||
      !json_object_is_type(tags, json_type_array)) {
    return TRUE;
  }

  gboolean tagged = FALSE;
  size_t n_tags = json_object_array_length(tags);
  for (size_t i = 0; i < n_tags; i++) {
    struct json_object *t = json_object_array_get_idx(tags, i);
    if (!json_object_is_type(t, json_type_string)) continue;
    const char *tag = json_object_get_string(t);
    if (!tag || !g_str_has_prefix(tag, MINIMIZED_TAG_PREFIX)) continue;
    tagged = TRUE;
    /* Parse strictly: a bare "minimized-ws-" (or trailing garbage) must never
     * be read as workspace 0. */
    const char *num = tag + strlen(MINIMIZED_TAG_PREFIX);
    char *end = NULL;
    errno = 0;
    long tag_ws = strtol(num, &end, 10);
    if (end != num && *end == '\0' && errno == 0 && tag_ws == (long)ws_id) {
      return TRUE;
    }
  }
  return !tagged;
}

static void clear_container(GtkContainer *container) {
  GList *children = gtk_container_get_children(container);
  for (GList *l = children; l != NULL; l = l->next) {
    gtk_widget_destroy(GTK_WIDGET(l->data));
  }
  g_list_free(children);
}

/* Width GTK actually gave this module, minus the CSS chrome that `#hypr-taskbar`
 * adds. -1 while the bar has not allocated us yet. */
static int root_span_px(TaskbarMod *mod) {
  if (!mod || !mod->root) return -1;
  int w = gtk_widget_get_allocated_width(mod->root);
  return w > 1 ? w - TASKBAR_CHROME_PX : -1;
}

/* Re-render whenever the bar grows/shrinks (monitor switch, tray items coming
 * and going, font changes), so the slot count follows the real span instead of
 * a stale estimate. Renders that do not change the span are ignored. */
static void on_root_size_allocate(GtkWidget *widget, GtkAllocation *allocation,
                                  gpointer data) {
  (void)widget;
  TaskbarMod *mod = (TaskbarMod *)data;
  if (!mod || !allocation) return;
  if (allocation->width <= 1) return;
  if (allocation->width - TASKBAR_CHROME_PX == mod->span_px) return;
  schedule_render(mod);
}

static void render_taskbar(TaskbarMod *mod) {
  if (!mod || !mod->box || !mod->sock_path) return;

  struct json_object *ws_obj = hypr_ipc_json(mod->sock_path, "j/activeworkspace");
  struct json_object *clients_obj = hypr_ipc_json(mod->sock_path, "j/clients");
  struct json_object *active_obj = hypr_ipc_json(mod->sock_path, "j/activewindow");
  struct json_object *mons_obj = hypr_ipc_json(mod->sock_path, "j/monitors");

  if (!ws_obj || !clients_obj ||
      !json_object_is_type(clients_obj, json_type_array)) {
    if (ws_obj) json_object_put(ws_obj);
    if (clients_obj) json_object_put(clients_obj);
    if (active_obj) json_object_put(active_obj);
    if (mons_obj) json_object_put(mons_obj);
    return;
  }

  int active_ws_id = json_get_int(ws_obj, "id", NO_WORKSPACE);
  const char *active_addr = json_get_str(active_obj, "address", "");

  mod->active_ws_id = active_ws_id;

  /* Compute logical width of focused monitor for strict overflow prevention. */
  int logical_w = 1536;
  if (mons_obj && json_object_is_type(mons_obj, json_type_array)) {
    size_t n_mons = json_object_array_length(mons_obj);
    for (size_t i = 0; i < n_mons; i++) {
      struct json_object *m = json_object_array_get_idx(mons_obj, i);
      gboolean focused = json_get_bool(m, "focused", FALSE);
      if (focused || i == 0) {
        int mw = json_get_int(m, "width", 1920);
        int mh = json_get_int(m, "height", 1200);
        int transform = json_get_int(m, "transform", 0);
        double scale = json_get_double(m, "scale", 1.0);
        if (scale <= 0.1) scale = 1.0;
        int eff_w = (transform % 2 == 1) ? mh : mw;
        logical_w = (int)llround((double)eff_w / scale);
        if (focused) break;
      }
    }
  }

  /* Collect the focused workspace's windows: mapped, non-hidden clients that
   * live there, plus the clients minimized *from* there. */
  GHashTable *by_addr = g_hash_table_new_full(g_str_hash, g_str_equal, NULL,
                                              client_info_free);
  GPtrArray *present_addrs = g_ptr_array_new();

  size_t n_clients = json_object_array_length(clients_obj);
  for (size_t i = 0; i < n_clients; i++) {
    struct json_object *c = json_object_array_get_idx(clients_obj, i);
    struct json_object *cws = NULL;
    if (!json_object_object_get_ex(c, "workspace", &cws)) continue;
    int cws_id = json_get_int(cws, "id", NO_WORKSPACE);
    const char *cws_name = json_get_str(cws, "name", "");
    gboolean minimized = g_str_has_prefix(cws_name, MINIMIZED_WS_PREFIX);

    if (minimized) {
      if (!minimized_on_workspace(c, active_ws_id)) continue;
    } else {
      if (cws_id != active_ws_id) continue;
      if (!json_get_bool(c, "mapped", TRUE)) continue;
      if (json_get_bool(c, "hidden", FALSE)) continue;
    }

    const char *addr = json_get_str(c, "address", "");
    if (!*addr) continue;

    ClientInfo *info = g_new0(ClientInfo, 1);
    info->address = g_strdup(addr);
    info->wclass = g_strdup(json_get_str(c, "class", ""));
    info->initial_class = g_strdup(json_get_str(c, "initialClass", ""));
    info->title = clean_title(json_get_str(c, "title", ""),
                              *info->wclass ? info->wclass : info->initial_class);
    info->minimized = minimized;

    g_hash_table_replace(by_addr, info->address, info);
    g_ptr_array_add(present_addrs, info->address);
  }

  /* Update stable order: keep existing still-present windows, append new ones. */
  GPtrArray *new_order = g_ptr_array_new_with_free_func(g_free);
  for (guint i = 0; i < mod->order->len; i++) {
    const char *a = (const char *)g_ptr_array_index(mod->order, i);
    if (g_hash_table_contains(by_addr, a)) {
      g_ptr_array_add(new_order, g_strdup(a));
    }
  }
  for (guint i = 0; i < present_addrs->len; i++) {
    const char *a = (const char *)g_ptr_array_index(present_addrs, i);
    gboolean found = FALSE;
    for (guint j = 0; j < new_order->len; j++) {
      if (strcmp((const char *)g_ptr_array_index(new_order, j), a) == 0) {
        found = TRUE;
        break;
      }
    }
    if (!found) g_ptr_array_add(new_order, g_strdup(a));
  }
  g_ptr_array_unref(mod->order);
  mod->order = new_order;

  /* Rebuild GTK widgets cleanly. */
  clear_container(GTK_CONTAINER(mod->box));

  /* Record the span even for an empty workspace: `on_root_size_allocate` only
   * re-renders when the span *changes*, so an empty taskbar that skipped this
   * would keep re-scheduling renders on every allocation. */
  int span_px = root_span_px(mod);
  if (span_px > 0) mod->span_px = span_px;

  guint total = mod->order->len;
  if (total > 0) {
    /* Until GTK allocates us, fall back to the focused monitor's logical width
     * minus a reserve for the neighbouring modules. */
    if (span_px < MIN_SLOT_PX) {
      span_px = logical_w - LEFT_RESERVE_PX - RIGHT_RESERVE_PX;
      if (span_px < MIN_AVAIL_PX) span_px = MIN_AVAIL_PX;
    }

    guint slots = (guint)(span_px / MIN_SLOT_PX);
    if (slots < 1) slots = 1;

    guint shown = MIN(total, slots);
    guint hidden = total - shown;

    /* Reserve the last slot for the `+N` chip, but never let the chip replace
     * the entire list on a very narrow bar. */
    if (hidden > 0 && slots > 1) {
      shown = slots - 1;
      hidden = total - shown;
    }

    /* Select visible list and ensure focused window is always visible. */
    GPtrArray *vis = g_ptr_array_new();
    gboolean active_in_vis = FALSE;
    ClientInfo *active_info = NULL;

    for (guint i = 0; i < total; i++) {
      const char *a = (const char *)g_ptr_array_index(mod->order, i);
      ClientInfo *ci = (ClientInfo *)g_hash_table_lookup(by_addr, a);
      if (!ci) continue;
      if (strcmp(ci->address, active_addr) == 0) active_info = ci;
      if (vis->len < shown) {
        g_ptr_array_add(vis, ci);
        if (ci == active_info) active_in_vis = TRUE;
      }
    }
    if (active_info && !active_in_vis && vis->len > 0) {
      g_ptr_array_index(vis, vis->len - 1) = active_info;
    }

    for (guint i = 0; i < vis->len; i++) {
      ClientInfo *ci = (ClientInfo *)g_ptr_array_index(vis, i);
      gboolean is_active = (strcmp(ci->address, active_addr) == 0);

      GtkWidget *btn = gtk_button_new();
      gtk_button_set_relief(GTK_BUTTON(btn), GTK_RELIEF_NONE);
      gtk_widget_set_can_focus(btn, FALSE);
      gtk_widget_set_tooltip_text(btn, ci->title);
      /* Middle click minimizes (GtkButton itself only reacts to button 1). */
      gtk_widget_add_events(btn, GDK_BUTTON_PRESS_MASK);
      g_object_set_data_full(G_OBJECT(btn), "hypr-addr", g_strdup(ci->address),
                             g_free);
      g_signal_connect(btn, "clicked", G_CALLBACK(on_task_clicked), mod);

      GtkStyleContext *ctx = gtk_widget_get_style_context(btn);
      gtk_style_context_add_class(ctx, "task");
      if (is_active) gtk_style_context_add_class(ctx, "active");
      if (ci->minimized) {
        gtk_style_context_add_class(ctx, "minimized");
        g_object_set_data(G_OBJECT(btn), "hypr-minimized", GINT_TO_POINTER(1));
      }
      g_signal_connect(btn, "button-press-event",
                       G_CALLBACK(on_task_button_press), mod);

      GtkWidget *inner = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 6);
      GtkWidget *icon = make_icon_widget(mod, ci->wclass, ci->initial_class);
      GtkWidget *label = gtk_label_new(ci->title);
      /* Let the label shrink to nothing and ellipsize inside its slot: the
       * width is dictated by the homogeneous box, not by the text. */
      gtk_label_set_ellipsize(GTK_LABEL(label), PANGO_ELLIPSIZE_END);
      gtk_label_set_single_line_mode(GTK_LABEL(label), TRUE);
      gtk_label_set_width_chars(GTK_LABEL(label), 1);
      gtk_label_set_max_width_chars(GTK_LABEL(label), 1);
      gtk_widget_set_hexpand(label, TRUE);
      gtk_widget_set_halign(label, GTK_ALIGN_START);

      gtk_box_pack_start(GTK_BOX(inner), icon, FALSE, FALSE, 0);
      gtk_box_pack_start(GTK_BOX(inner), label, TRUE, TRUE, 0);
      gtk_container_add(GTK_CONTAINER(btn), inner);
      gtk_box_pack_start(mod->box, btn, TRUE, TRUE, 0);
    }

    if (hidden > 0) {
      char *ov_txt = g_strdup_printf("+%u", hidden);
      GtkWidget *ov = gtk_label_new(ov_txt);
      g_free(ov_txt);
      gtk_style_context_add_class(gtk_widget_get_style_context(ov),
                                  "task-overflow");
      gtk_box_pack_start(mod->box, ov, TRUE, TRUE, 0);
    }

    g_ptr_array_unref(vis);
  }

  gtk_widget_show_all(GTK_WIDGET(mod->box));

  g_ptr_array_unref(present_addrs);
  g_hash_table_unref(by_addr);
  json_object_put(ws_obj);
  json_object_put(clients_obj);
  if (active_obj) json_object_put(active_obj);
  if (mons_obj) json_object_put(mons_obj);
}

/* ---- Coalesced refresh scheduling & Hyprland socket2 listener ---- */

static gboolean on_render_timeout(gpointer user_data) {
  TaskbarMod *mod = (TaskbarMod *)user_data;
  mod->render_id = 0;
  render_taskbar(mod);
  return G_SOURCE_REMOVE;
}

static gboolean on_recheck_timeout(gpointer user_data) {
  TaskbarMod *mod = (TaskbarMod *)user_data;
  mod->recheck_id = 0;
  render_taskbar(mod);
  return G_SOURCE_REMOVE;
}

static void schedule_render(TaskbarMod *mod) {
  if (mod->render_id) g_source_remove(mod->render_id);
  if (mod->recheck_id) g_source_remove(mod->recheck_id);
  mod->render_id = g_timeout_add(20, on_render_timeout, mod);
  mod->recheck_id = g_timeout_add(150, on_recheck_timeout, mod);
}

static gboolean is_relevant_event(const char *line) {
  static const char *const events[] = {
      "workspace>>",     "workspacev2>>",     "focusedmon>>",
      "focusedmonv2>>",  "activewindow>>",    "activewindowv2>>",
      "openwindow>>",    "closewindow>>",     "movewindow>>",
      "movewindowv2>>",  "windowtitle>>",     "windowtitlev2>>",
      "fullscreen>>",    "changefloatingmode>>", "monitoradded>>",
      "monitorremoved>>", "activespecial>>",  NULL,
  };
  for (int i = 0; events[i]; i++) {
    if (g_str_has_prefix(line, events[i])) return TRUE;
  }
  return FALSE;
}

static gboolean connect_event_socket(TaskbarMod *mod);

static gboolean on_reconnect_timer(gpointer user_data) {
  TaskbarMod *mod = (TaskbarMod *)user_data;
  if (connect_event_socket(mod)) {
    mod->reconnect_id = 0;
    schedule_render(mod);
    return G_SOURCE_REMOVE;
  }
  return G_SOURCE_CONTINUE;
}

static void close_event_socket(TaskbarMod *mod) {
  if (mod->event_watch_id) {
    g_source_remove(mod->event_watch_id);
    mod->event_watch_id = 0;
  }
  if (mod->event_chan) {
    g_io_channel_unref(mod->event_chan);
    mod->event_chan = NULL;
  }
  if (mod->event_fd >= 0) {
    close(mod->event_fd);
    mod->event_fd = -1;
  }
}

static gboolean on_event_readable(GIOChannel *src, GIOCondition cond,
                                  gpointer user_data) {
  (void)src;
  TaskbarMod *mod = (TaskbarMod *)user_data;

  if (cond & (G_IO_HUP | G_IO_ERR | G_IO_NVAL)) {
    close_event_socket(mod);
    if (!mod->reconnect_id) {
      mod->reconnect_id = g_timeout_add_seconds(1, on_reconnect_timer, mod);
    }
    return G_SOURCE_REMOVE;
  }

  char buf[8192];
  gboolean interesting = FALSE;
  for (;;) {
    ssize_t n = read(mod->event_fd, buf, sizeof(buf));
    if (n > 0) {
      g_string_append_len(mod->event_buf, buf, n);
    } else if (n == 0) {
      close_event_socket(mod);
      if (!mod->reconnect_id) {
        mod->reconnect_id = g_timeout_add_seconds(1, on_reconnect_timer, mod);
      }
      return G_SOURCE_REMOVE;
    } else {
      if (errno == EINTR) continue;
      if (errno == EAGAIN || errno == EWOULDBLOCK) break;
      close_event_socket(mod);
      if (!mod->reconnect_id) {
        mod->reconnect_id = g_timeout_add_seconds(1, on_reconnect_timer, mod);
      }
      return G_SOURCE_REMOVE;
    }
  }

  char *nl;
  while ((nl = strchr(mod->event_buf->str, '\n')) != NULL) {
    gsize line_len = (gsize)(nl - mod->event_buf->str);
    *nl = '\0';
    if (is_relevant_event(mod->event_buf->str)) {
      interesting = TRUE;
    }
    g_string_erase(mod->event_buf, 0, (gssize)(line_len + 1));
  }

  if (interesting) schedule_render(mod);
  return G_SOURCE_CONTINUE;
}

static gboolean connect_event_socket(TaskbarMod *mod) {
  if (!mod->event_path) return FALSE;
  close_event_socket(mod);

  int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
  if (fd < 0) return FALSE;

  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  if (strlen(mod->event_path) >= sizeof(addr.sun_path)) {
    close(fd);
    return FALSE;
  }
  strcpy(addr.sun_path, mod->event_path);

  if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
    close(fd);
    return FALSE;
  }

  int flags = fcntl(fd, F_GETFL, 0);
  if (flags >= 0) fcntl(fd, F_SETFL, flags | O_NONBLOCK);

  mod->event_fd = fd;
  mod->event_chan = g_io_channel_unix_new(fd);
  g_io_channel_set_encoding(mod->event_chan, NULL, NULL);
  g_io_channel_set_buffered(mod->event_chan, FALSE);
  mod->event_watch_id = g_io_add_watch(
      mod->event_chan,
      (GIOCondition)(G_IO_IN | G_IO_HUP | G_IO_ERR | G_IO_NVAL),
      on_event_readable, mod);
  return TRUE;
}

static void on_icon_theme_changed(GtkIconTheme *theme, gpointer user_data) {
  (void)theme;
  TaskbarMod *mod = (TaskbarMod *)user_data;
  if (!mod) return;
  g_hash_table_remove_all(mod->icon_cache);
  if (mod->desktop_apps) {
    g_list_free_full(mod->desktop_apps, g_object_unref);
    mod->desktop_apps = NULL;
  }
  schedule_render(mod);
}

/* ---- Waybar CFFI ABI v2 entrypoints ---- */

const size_t wbcffi_version = 2;

void *wbcffi_init(const wbcffi_init_info *init_info,
                  const wbcffi_config_entry *config_entries,
                  size_t config_entries_len) {
  TaskbarMod *mod = g_new0(TaskbarMod, 1);
  mod->waybar_module = init_info->obj;
  mod->icon_size = DEFAULT_ICON_SIZE;
  mod->active_ws_id = NO_WORKSPACE;
  mod->event_fd = -1;
  mod->event_buf = g_string_new(NULL);
  mod->order = g_ptr_array_new_with_free_func(g_free);
  mod->icon_cache = g_hash_table_new_full(g_str_hash, g_str_equal, g_free,
                                          g_object_unref);

  for (size_t i = 0; i < config_entries_len; i++) {
    if (strcmp(config_entries[i].key, "icon_size") == 0 &&
        config_entries[i].value) {
      int v = atoi(config_entries[i].value);
      if (v >= 12 && v <= 48) mod->icon_size = v;
    }
  }

  const char *runtime = g_getenv("XDG_RUNTIME_DIR");
  const char *sig = g_getenv("HYPRLAND_INSTANCE_SIGNATURE");
  if (runtime && sig && *runtime && *sig) {
    mod->sock_path = g_strdup_printf("%s/hypr/%s/.socket.sock", runtime, sig);
    mod->event_path = g_strdup_printf("%s/hypr/%s/.socket2.sock", runtime, sig);
  }

  GtkContainer *root = init_info->get_root_widget(init_info->obj);
  if (!root) {
    g_hash_table_unref(mod->icon_cache);
    g_ptr_array_unref(mod->order);
    g_string_free(mod->event_buf, TRUE);
    g_free(mod->sock_path);
    g_free(mod->event_path);
    g_free(mod);
    return NULL;
  }

  /* Homogeneous: every task button gets an identical share of the full span,
   * so the row reads like AwesomeWM's tasklist rather than a shrink-wrapped
   * strip in the middle of the bar. */
  mod->box = GTK_BOX(gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0));
  gtk_box_set_homogeneous(mod->box, TRUE);
  /* CSS keeps targeting `#hypr-taskbar`, which stays on the inner box. */
  gtk_widget_set_name(GTK_WIDGET(mod->box), "hypr-taskbar");
  gtk_widget_set_hexpand(GTK_WIDGET(mod->box), TRUE);
  gtk_widget_set_halign(GTK_WIDGET(mod->box), GTK_ALIGN_FILL);

  mod->scroll_box = gtk_event_box_new();
  gtk_event_box_set_visible_window(GTK_EVENT_BOX(mod->scroll_box), FALSE);
  gtk_event_box_set_above_child(GTK_EVENT_BOX(mod->scroll_box), FALSE);
  gtk_widget_add_events(mod->scroll_box,
                        GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK);
  gtk_widget_set_hexpand(mod->scroll_box, TRUE);
  gtk_container_add(GTK_CONTAINER(mod->scroll_box), GTK_WIDGET(mod->box));
  gtk_container_add(root, mod->scroll_box);

  mod->root = GTK_WIDGET(root);
  gtk_widget_set_hexpand(mod->root, TRUE);
  gtk_widget_set_halign(mod->root, GTK_ALIGN_FILL);
  mod->root_alloc_id = g_signal_connect(mod->root, "size-allocate",
                                        G_CALLBACK(on_root_size_allocate), mod);

  mod->scroll_id = g_signal_connect(mod->scroll_box, "scroll-event",
                                    G_CALLBACK(on_taskbar_scroll), mod);

  GtkIconTheme *theme = gtk_icon_theme_get_default();
  mod->theme_changed_id = g_signal_connect(
      theme, "changed", G_CALLBACK(on_icon_theme_changed), mod);

  if (connect_event_socket(mod)) {
    render_taskbar(mod);
  } else if (mod->event_path) {
    mod->reconnect_id = g_timeout_add_seconds(1, on_reconnect_timer, mod);
  }

  return mod;
}

void wbcffi_deinit(void *instance) {
  TaskbarMod *mod = (TaskbarMod *)instance;
  if (!mod) return;

  if (mod->render_id) g_source_remove(mod->render_id);
  if (mod->recheck_id) g_source_remove(mod->recheck_id);
  if (mod->reconnect_id) g_source_remove(mod->reconnect_id);
  close_event_socket(mod);

  if (mod->theme_changed_id) {
    GtkIconTheme *theme = gtk_icon_theme_get_default();
    if (theme) g_signal_handler_disconnect(theme, mod->theme_changed_id);
  }

  if (mod->scroll_box && mod->scroll_id) {
    g_signal_handler_disconnect(mod->scroll_box, mod->scroll_id);
  }

  if (mod->root && mod->root_alloc_id) {
    g_signal_handler_disconnect(mod->root, mod->root_alloc_id);
  }

  if (mod->desktop_apps) g_list_free_full(mod->desktop_apps, g_object_unref);
  if (mod->icon_cache) g_hash_table_unref(mod->icon_cache);
  if (mod->order) g_ptr_array_unref(mod->order);
  if (mod->event_buf) g_string_free(mod->event_buf, TRUE);
  g_free(mod->sock_path);
  g_free(mod->event_path);
  g_free(mod);
}

void wbcffi_update(void *instance) {
  if (!instance) return;
  render_taskbar((TaskbarMod *)instance);
}

void wbcffi_refresh(void *instance, int signal) {
  (void)signal;
  if (!instance) return;
  schedule_render((TaskbarMod *)instance);
}

void wbcffi_doaction(void *instance, const char *action_name) {
  (void)action_name;
  if (!instance) return;
  schedule_render((TaskbarMod *)instance);
}

/* ---- Optional standalone icon-resolution self-test binary ---- */
#ifdef TASKBAR_CHECK_MAIN
int main(int argc, char **argv) {
  gtk_init_check(&argc, &argv);

  TaskbarMod mod;
  memset(&mod, 0, sizeof(mod));
  mod.icon_size = DEFAULT_ICON_SIZE;
  mod.icon_cache = g_hash_table_new_full(g_str_hash, g_str_equal, g_free,
                                         g_object_unref);

  GtkIconTheme *theme = gtk_icon_theme_get_default();
  for (int i = 1; i < argc; i++) {
    GIcon *gicon = resolve_app_gicon(&mod, argv[i], argv[i]);
    char *gstr = g_icon_to_string(gicon);
    GtkIconInfo *info = gtk_icon_theme_lookup_by_gicon(
        theme, gicon, DEFAULT_ICON_SIZE, GTK_ICON_LOOKUP_FORCE_SIZE);
    const char *path = info ? gtk_icon_info_get_filename(info) : NULL;
    printf("%-28s -> icon=%-28s file=%s\n", argv[i], gstr ? gstr : "(null)",
           path ? path : "(theme/missing)");
    if (info) g_object_unref(info);
    g_free(gstr);
    g_object_unref(gicon);
  }

  if (mod.desktop_apps) g_list_free_full(mod.desktop_apps, g_object_unref);
  g_hash_table_unref(mod.icon_cache);
  return 0;
}
#endif
