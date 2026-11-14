#!/usr/bin/env python3

import asyncio
import fcntl
import os
import re
import sys
import time

import iterm2
from iterm2.notifications import SubscriptionException

WINDOWED_SIZE = 12
FULLSCREEN_SIZE = 16

LOCK_PATH = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), ".fullscreen_font.lock"
)

# How long a starting instance waits for a previous one to notice its
# websocket died and release the lock. iTerm2 relaunches AutoLaunch scripts
# immediately on start, while the old instance may still be mid-shutdown.
LOCK_GRACE_SECONDS = 10.0
LOCK_POLL_SECONDS = 0.25


def acquire_singleton_lock():
    """Take an exclusive lock, or return None if another instance holds it.

    iTerm2 spawns this script on every launch. Copies from a previous run can
    survive as orphans (a disconnected instance used to hang forever), and two
    live copies collide on RPC registration with
    DUPLICATE_SERVER_ORIGINATED_RPC. Being a singleton makes that impossible.

    The lock is re-tried briefly so a relaunch right after an iTerm2 restart
    does not race the outgoing instance. The kernel drops the lock when this
    process exits, so a crash never wedges the script.
    """
    fd = os.open(LOCK_PATH, os.O_CREAT | os.O_RDWR, 0o644)
    waited = 0.0
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            break
        except OSError:
            if waited >= LOCK_GRACE_SECONDS:
                os.close(fd)
                return None
            time.sleep(LOCK_POLL_SECONDS)
            waited += LOCK_POLL_SECONDS
    os.ftruncate(fd, 0)
    os.write(fd, str(os.getpid()).encode())
    return fd


async def main(connection):
    app = await iterm2.async_get_app(connection)

    # Synchronizes fullscreen toggles and new-session handling.
    lock = asyncio.Lock()

    show_fs_tabs_key = (
        iterm2.preferences.PreferenceKey.SHOW_FULL_SCREEN_TAB_BAR
    )
    hide_single_tab_key = (
        iterm2.preferences.PreferenceKey.HIDE_TAB_BAR_WHEN_ONLY_ONE_TAB
    )

    async def set_font_size(session, size):
        profile = await session.async_get_profile()

        font = profile.normal_font
        new_font = re.sub(
            r"(\d+(?:\.\d+)?)([^0-9]*)$",
            lambda m: f"{size}{m.group(2)}",
            font,
        )

        change = iterm2.LocalWriteOnlyProfile()
        change.set_normal_font(new_font)
        await session.async_set_profile_properties(change)

    async def without_window_resize(callback):
        key = (
            iterm2.preferences.PreferenceKey
            .ADJUST_WINDOW_FOR_FONT_SIZE_CHANGE
        )

        old_value = await iterm2.preferences.async_get_preference(
            connection, key
        )

        try:
            await iterm2.preferences.async_set_preference(
                connection, key, False
            )

            await callback()

        finally:
            await iterm2.preferences.async_set_preference(
                connection, key, old_value
            )

    async def set_window_font_size(window, size):
        async def change_fonts():
            await asyncio.gather(*[
                set_font_size(session, size)
                for tab in window.tabs
                for session in tab.sessions
            ])

        await without_window_resize(change_fonts)

    async def set_single_session_font_size(session, size):
        async def change_font():
            await set_font_size(session, size)

        await without_window_resize(change_font)

    async def tabs_are_shown_preference():
        """Canonical 'show tabs' flag (fullscreen + single-tab windowed)."""
        showing = await iterm2.preferences.async_get_preference(
            connection, show_fs_tabs_key
        )
        if showing is None:
            showing = True
        return bool(showing)

    async def set_tabs_shown(show_tabs):
        # Fullscreen (and traditional-FS) windows honor this.
        await iterm2.preferences.async_set_preference(
            connection, show_fs_tabs_key, show_tabs
        )
        # Non-fullscreen windows only honor this when there is one tab.
        # iTerm always shows the tab bar with 2+ tabs outside fullscreen.
        await iterm2.preferences.async_set_preference(
            connection, hide_single_tab_key, not show_tabs
        )

    @iterm2.RPC
    async def toggle_fullscreen_font(
        session_id=iterm2.Reference("id")
    ):
        async with lock:
            session = app.get_session_by_id(session_id)
            if session is None:
                return

            window = session.tab.window

            is_fullscreen = await window.async_get_fullscreen()
            entering_fullscreen = not is_fullscreen

            if entering_fullscreen:
                await set_window_font_size(
                    window,
                    FULLSCREEN_SIZE,
                )

                await window.async_set_fullscreen(True)

            else:
                await window.async_set_fullscreen(False)

                await set_window_font_size(
                    window,
                    WINDOWED_SIZE,
                )

    async def register_with_retry(rpc_name, rpc_obj, attempts=5, delay=1.0):
        """Register an RPC, tolerating a stale holder from a crashed instance.

        iTerm2 keeps a name reserved until the owning socket is reaped, so a
        re-registration can briefly fail right after a restart.
        """
        for attempt in range(attempts):
            try:
                await rpc_obj.async_register(connection)
                return
            except SubscriptionException:
                if attempt == attempts - 1:
                    # Bail out hard rather than returning: run_forever() would
                    # keep running with no registrations, holding the singleton
                    # lock and blocking the instance that could actually work.
                    print(
                        f"{rpc_name}: another instance still holds this "
                        f"registration; exiting",
                        file=sys.stderr,
                        flush=True,
                    )
                    os._exit(1)
                await asyncio.sleep(delay)

    await register_with_retry("toggle_fullscreen_font", toggle_fullscreen_font)

    @iterm2.RPC
    async def toggle_tabs():
        show_tabs = await tabs_are_shown_preference()
        await set_tabs_shown(not show_tabs)

    await register_with_retry("toggle_tabs", toggle_tabs)

    # Start with tabs hidden in both modes (1-tab windowed + fullscreen).
    await set_tabs_shown(False)

    async def handle_new_sessions():
        async with iterm2.NewSessionMonitor(connection) as monitor:
            while True:
                session_id = await monitor.async_get()

                async with lock:
                    session = app.get_session_by_id(session_id)
                    if session is None:
                        continue

                    window = session.tab.window
                    is_fullscreen = await window.async_get_fullscreen()

                    size = (
                        FULLSCREEN_SIZE
                        if is_fullscreen
                        else WINDOWED_SIZE
                    )

                    await set_single_session_font_size(
                        session,
                        size,
                    )

    async def handle_tab_toggle_hotkey():
        # Intercept ⌘⇧T so it works in floating hotkey windows, where the
        # menu key equivalent for "Show Tabs in Fullscreen" often does not.
        pattern = iterm2.KeystrokePattern()
        pattern.required_modifiers = [
            iterm2.Modifier.COMMAND,
            iterm2.Modifier.SHIFT,
        ]
        pattern.keycodes = [iterm2.Keycode.ANSI_T]

        async with iterm2.KeystrokeFilter(connection, [pattern]):
            async with iterm2.KeystrokeMonitor(connection) as mon:
                while True:
                    keystroke = await mon.async_get()
                    mods = set(keystroke.modifiers)
                    if (
                        iterm2.Modifier.COMMAND in mods
                        and iterm2.Modifier.SHIFT in mods
                        and keystroke.keycode == iterm2.Keycode.ANSI_T
                    ):
                        await toggle_tabs()

    await asyncio.gather(
        handle_new_sessions(),
        handle_tab_toggle_hotkey(),
        exit_on_disconnect(connection),
    )


async def exit_on_disconnect(connection):
    """Hard-exit once the websocket closes.

    main() awaits only never-ending loops, so Connection.run() never gets to
    await its dispatch task and a dropped connection leaves this process alive
    forever holding dead sockets and the singleton lock. Exiting releases both
    so the instance iTerm2 spawns next can take over.
    """
    websocket = connection.websocket
    while not websocket.closed:
        await asyncio.sleep(1.0)
    os._exit(0)


if __name__ == "__main__":
    if acquire_singleton_lock() is None:
        print(
            "fullscreen_font: another instance is already running; exiting",
            file=sys.stderr,
            flush=True,
        )
        sys.exit(0)
    iterm2.run_forever(main)
