#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
archive=${1:?Usage: bash test/cog-pointer.sh /path/to/cog-0.18.5.tar.xz [--unpatched]}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
tar -xf "$archive" -C "$work"
if [[ ${2:-} != --unpatched ]]; then
    bash "$root/deps/nerves_system_br/buildroot-2026.08/support/scripts/apply-patches.sh" \
        "$work/cog-0.18.5" "$root/patches/cog" '*.patch'
fi
source_file="$work/cog-0.18.5/platform/drm/cog-platform-drm.c"

cat > "$work/check.c" <<'EOF'
#include <assert.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#define TRUE true
#define FALSE false
#define g_getenv getenv
#define g_warning(...) ((void) 0)
static int g_strcmp0(const char *first, const char *second)
{
    return first ? strcmp(first, second) : -1;
}
static bool pointer_enabled;
static struct {
    bool enabled;
    void *plane, *cursor;
    unsigned int x, y, screen_width, screen_height;
} cursor;
static struct { unsigned int width, height; } drm_data = { 1920, 1080 };
static struct { void *backend; } wpe_view_data;
static bool cursor_available;
static bool init_cursor(void) { return cursor.enabled = cursor_available; }
enum { wpe_input_pointer_event_type_motion, wpe_input_pointer_event_type_button };
struct wpe_input_pointer_event {
    unsigned int type, time, x, y, button, state, modifiers;
};
struct libinput_event_pointer {
    double x, y, dx, dy;
    unsigned int time, button, state;
};
#define libinput_event_pointer_get_absolute_x_transformed(event, width) ((event)->x * (width))
#define libinput_event_pointer_get_absolute_y_transformed(event, height) ((event)->y * (height))
#define libinput_event_pointer_get_dx(event) ((event)->dx)
#define libinput_event_pointer_get_dy(event) ((event)->dy)
#define libinput_event_pointer_get_time(event) ((event)->time)
#define libinput_event_pointer_get_button(event) ((event)->button)
#define libinput_event_pointer_get_button_state(event) ((event)->state)
static unsigned int dispatches, plane_updates;
static struct wpe_input_pointer_event last_event;
static void wpe_view_backend_dispatch_pointer_event(void *backend, struct wpe_input_pointer_event *event)
{
    (void) backend;
    ++dispatches;
    last_event = *event;
}
static int kms_plane_set(void *plane, void *framebuffer, unsigned int x, unsigned int y)
{
    (void) plane; (void) framebuffer; (void) x; (void) y;
    assert(cursor.enabled);
    ++plane_updates;
    return 0;
}
EOF

awk '/^input_handle_pointer_motion_event\(/ || /^input_handle_pointer_button_event / {
        printing = 1; print "static void"
    }
     printing { print }
    printing && /^}/ { printing = 0 }' \
    "$source_file" >> "$work/check.c"
printf '\nstatic void setup_pointer(void) {\n' >> "$work/check.c"
awk '/^    cursor.screen_width = drm_data.width;/ { printing = 1 }
     printing && /^    if \(!init_gbm/ { exit }
     printing { print }' "$source_file" >> "$work/check.c"
cat >> "$work/check.c" <<'EOF'
}
int main(void)
{
    struct libinput_event_pointer input = { .x = 0.25, .y = 0.75, .dx = 10, .dy = 20,
                                           .time = 42, .button = 272, .state = 1 };
    pointer_enabled = true;
    cursor.screen_width = 1920;
    cursor.screen_height = 1080;
    cursor.x = 960;
    cursor.y = 540;
    input_handle_pointer_motion_event(&input, false);
    assert(dispatches == 1 && plane_updates == 0);
    assert(last_event.x == 970 && last_event.y == 560);
    input_handle_pointer_motion_event(&input, true);
    assert(dispatches == 2 && plane_updates == 0);
    assert(last_event.x == 480 && last_event.y == 810 && last_event.time == 42);
    input_handle_pointer_button_event(&input);
    assert(dispatches == 3 && plane_updates == 0);
    assert(last_event.type == wpe_input_pointer_event_type_button);
    assert(last_event.button == 272 && last_event.state == 1);
    input.x = input.y = 2;
    input_handle_pointer_motion_event(&input, true);
    assert(last_event.x == 1919 && last_event.y == 1079);
    pointer_enabled = false;
    input_handle_pointer_motion_event(&input, false);
    input_handle_pointer_button_event(&input);
    assert(dispatches == 4 && plane_updates == 0);
    pointer_enabled = cursor.enabled = true;
    input_handle_pointer_motion_event(&input, true);
    assert(dispatches == 5 && plane_updates == 1);

    unsetenv("COG_PLATFORM_DRM_CURSOR");
    unsetenv("COG_PLATFORM_DRM_POINTER");
    cursor.enabled = false;
    setup_pointer();
    assert(!pointer_enabled && cursor.x == 960 && cursor.y == 540);
    assert(cursor.screen_width == 1920 && cursor.screen_height == 1080);
    setenv("COG_PLATFORM_DRM_POINTER", "0", 1);
    setup_pointer();
    assert(!pointer_enabled);
    setenv("COG_PLATFORM_DRM_POINTER", "1", 1);
    setenv("COG_PLATFORM_DRM_CURSOR", "1", 1);
    setup_pointer();
    assert(pointer_enabled && !cursor.enabled);
    input_handle_pointer_button_event(&input);
    assert(dispatches == 6 && plane_updates == 1);
    unsetenv("COG_PLATFORM_DRM_POINTER");
    cursor_available = true;
    setup_pointer();
    assert(pointer_enabled && cursor.enabled);
    puts("Cog pointer regression checks passed");
    return 0;
}
EOF
"${CC:-cc}" -std=gnu11 -Wall -Wextra -Wno-type-limits -Wno-unused-function \
    "$work/check.c" -o "$work/check"
"$work/check"