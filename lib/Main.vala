/*
 * Copyright (c) 2021 Payson Wallach
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

namespace Attention {
    /* A wrapper for arrays returned from X.Display.get_window_property with
     * format 32, which causes them to be freed correctly.
     */
    [Compact]
    public class XArray32 {
        protected ulong _length;
        protected ulong * data;

        public ulong length {
            get {
                return this._length;
            }
            private set {
                this._length = value;
            }
        }

        public XArray32 (ulong length, void * data) {
            this.length = length;
            this.data = (ulong *) data;
        }

        ~XArray32 () {
            if (data != null)
                X.free (data);
        }

        public ulong get (ulong index) requires (index < this.length) {
            return this.data[index];
        }

        public void set (ulong index, ulong item) requires (index < this.length) {
            this.data[index] = item;
        }

        public bool contains (ulong needle) {
            foreach (ulong? item in this)
                if (item == needle)
                    return true;

            return false;
        }

        public Iterator iterator () {
            return new Iterator (this);
        }

        [Compact]
        public class Iterator {
            protected ulong index;
            protected unowned XArray32 array;

            public Iterator (XArray32 array) {
                this.array = array;
            }

            public ulong? next_value () {
                this.index++;
                if (this.index < this.array.length)
                    return this.array[this.index];

                return null;
            }
        }
    }

    [DBus (name = "com.paysonwallach.attention")]
    private class DBusServer : Object {
        private uint owner_id = 0U;

        [DBus (visible = false)]
        public signal void activation_requested (string application_id);

        [DBus (visible = false)]
        public signal void activation_of_window_demanding_attention_requested ();

        private static Once<DBusServer> instance;

        public static unowned DBusServer get_default () {
            return instance.once (() => {
                return new DBusServer ();
            });
        }

        construct {
            /* *INDENT-OFF* */
            owner_id = Bus.own_name (
                BusType.SESSION,
                "com.paysonwallach.attention",
                BusNameOwnerFlags.ALLOW_REPLACEMENT | BusNameOwnerFlags.REPLACE,
                (connection) => {
                    try {
                        debug ("acquiring bus name...");
                        connection.register_object (
                            "/com/paysonwallach/attention", get_default ());
                    } catch (IOError err) {
                        error (err.message);
                    }
                },
                () => {},
                () => { error ("could not acquire bus name"); });
            /* *INDENT-ON* */
        }

        ~DBusServer () {
            if (owner_id != 0U)
                Bus.unown_name (owner_id);
        }

        public void activate (string application_id) throws DBusError, IOError {
            activation_requested (application_id);
        }

        public void activate_window_demanding_attention () throws DBusError, IOError {
            activation_of_window_demanding_attention_requested ();
        }

    }

    public class Main : Gala.Plugin {
        private enum GetWindowPropertyResult {
            SUCCESS,
            FAILURE,
            BAD_WINDOW
        }

        private Gala.AppCache app_cache;
        private Gala.WindowManager wm;
        private Gee.HashMap<string, Meta.Window> last_active_windows;

        public override void initialize (Gala.WindowManager wm) {
            this.wm = wm;
            app_cache = new Gala.AppCache ();
            last_active_windows = new Gee.HashMap<string, Meta.Window> ();

            var display = wm.get_display ();
            foreach (unowned Meta.WindowActor actor in display.get_window_actors ()) {
                if (actor.is_destroyed ())
                    continue;

                unowned Meta.Window window = actor.get_meta_window ();
                if (window.window_type == Meta.WindowType.NORMAL)
                    monitor_window (window);
            }

            display.window_created.connect (on_window_created);

            DBusServer.get_default ().activation_requested.connect (on_activation_requested);
            DBusServer.get_default ().activation_of_window_demanding_attention_requested.connect (on_activate_window_demanding_attention);
        }

        public override void destroy () {
            var display = wm.get_display ();
            foreach (unowned Meta.WindowActor actor in display.get_window_actors ()) {
                if (actor.is_destroyed ())
                    continue;

                unowned Meta.Window window = actor.get_meta_window ();
                if (window.window_type == Meta.WindowType.NORMAL)
                    monitor_window (window);
            }

            display.window_created.disconnect (on_window_created);
        }

        private void monitor_window (Meta.Window window) {
            window.focused.connect (on_window_focused);
            window.unmanaged.connect (unmonitor_window);
        }

        private void unmonitor_window (Meta.Window window) {
            window.focused.disconnect (on_window_focused);
            window.unmanaged.disconnect (unmonitor_window);
        }

        private void on_window_created (Meta.Window window) {
            if (window.window_type == Meta.WindowType.NORMAL)
                monitor_window (window);
        }

        private void on_window_focused (Meta.Window window) {
            var wm_class = window.get_wm_class ();
            var canonicalized_wm_class = wm_class.ascii_down ().delimit (" ", '-');
            var desktop_url = @"$canonicalized_wm_class.desktop";
            var desktop_app = app_cache.lookup_id (desktop_url);

            if (desktop_app == null) {
                desktop_url = @"$(window.get_gtk_application_id ()).desktop";
                desktop_app = app_cache.lookup_id (desktop_url);
            }

            if (desktop_app == null) {
                warning (@"unable to find DesktopAppInfo for $desktop_url");
                return;
            }

            last_active_windows.@set (desktop_app.get_id (), window);
        }

        private GetWindowPropertyResult get_window_property (X.Display display,
                                                             X.Window window,
                                                             X.Atom property,
                                                             bool @delete,
                                                             X.Atom type,
                                                             int format,
                                                             out ulong length,
                                                             out void * data) {
            X.Atom actual_type;
            int actual_format;
            ulong remaining_bytes;

            Gdk.error_trap_push ();
            var status = display.get_window_property (
                window,
                property,
                0L,
                long.MAX,
                @delete,
                type,
                out actual_type,
                out actual_format,
                out length,
                out remaining_bytes,
                out data);
            var x_error = Gdk.error_trap_pop ();
            if (unlikely (x_error != 0)) {
                switch (x_error) {
                case X.ErrorCode.BAD_WINDOW:
                    return GetWindowPropertyResult.BAD_WINDOW;
                case X.ErrorCode.BAD_ALLOC:
                    break;
                case X.ErrorCode.BAD_ATOM:
                    warning ("get_window_property received invalid atom");
                    break;
                case X.ErrorCode.BAD_VALUE:
                    warning ("get_window_property sent invalid value to X server");
                    break;
                default:
                    warning ("XGetWindowProperty caused unexpected error");
                    break;
                }
                return GetWindowPropertyResult.FAILURE;
            }

            return_val_if_fail (
                status == X.Success, GetWindowPropertyResult.FAILURE);

            if (actual_type == X.None || actual_type != type)
                return GetWindowPropertyResult.FAILURE;

            if (actual_format != format) {
                X.free (data);
                data = null;
                return GetWindowPropertyResult.FAILURE;
            }

            return GetWindowPropertyResult.SUCCESS;
        }

        private GetWindowPropertyResult get_window_property32 (X.Display display,
                                                               X.Window window,
                                                               X.Atom property,
                                                               bool @delete,
                                                               X.Atom type,
                                                               out XArray32 data) {
            ulong count;
            void * data_ptr;
            GetWindowPropertyResult result;
            result = get_window_property (
                display, window, property, @delete, type, 32, out count, out data_ptr
                );
            data = new XArray32 (count, data_ptr);
            return result;
        }

        private void activate_window (Meta.Display display, Meta.Window window) {
            var time = display.get_current_time ();
            var workspace = window.get_workspace ();

            if (workspace != wm.get_display ()
                 .get_workspace_manager ().get_active_workspace ())
                workspace.activate_with_focus (window, time);
            else
                window.activate (time);
        }

        private void on_activation_requested (string application_id) {
            debug (@"querying app cache for $application_id");
            var app = app_cache.lookup_id (@"$application_id.desktop");

            if (app == null)
                return;

            debug (@"querying windows for $(app.get_id ())");
            var window = last_active_windows.@get (app.get_id ());

            if (window == null)
                try {
                    app.launch (
                        null,
                        Gdk.Display.get_default ()
                         .get_app_launch_context ());
                } catch (Error err) {}
            else {
                debug (@"got window $(window.get_id ())");
                var display = wm.get_display ();

                activate_window (display, window);
            }
        }

        private void on_activate_window_demanding_attention () {
            var display = wm.get_display ();

            unowned X.Display xdisplay = display.get_x11_display ().get_xdisplay ();
            foreach (unowned Meta.WindowActor actor in display.get_window_actors ()) {
                if (actor.is_destroyed ())
                    continue;

                unowned Meta.Window window = actor.get_meta_window ();
                if (window.window_type == Meta.WindowType.NORMAL) {
                    XArray32 state;
                    if (
                        get_window_property32 (
                            xdisplay,
                            window.get_xwindow (),
                            Gdk.X11.get_xatom_by_name ("_NET_WM_STATE"),
                            false,
                            X.XA_ATOM,
                            out state
                            ) == GetWindowPropertyResult.SUCCESS
                        &&
                        Gdk.X11.get_xatom_by_name ("_NET_WM_STATE_DEMANDS_ATTENTION")
                        in state
                        ) {
                        activate_window (display, window);
                        return;
                    }
                }
            }

            Idle.add (() => {
                on_activate_window_demanding_attention ();

                return Source.REMOVE;
            });
        }

    }
}

/* *INDENT-OFF* */
public Gala.PluginInfo register_plugin () {
    return Gala.PluginInfo () {
        name = "Attention",
        author = "Payson Wallach <payson@paysonwallach.com>",
        plugin_type = typeof (Attention.Main),
        provides = Gala.PluginFunction.ADDITION,
        load_priority = Gala.LoadPriority.IMMEDIATE
    };
}
/* *INDENT-ON* */
