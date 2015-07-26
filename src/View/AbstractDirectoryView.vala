/***
    Copyright (C) 2015 elementary Developers

    This program is free software: you can redistribute it and/or modify it
    under the terms of the GNU Lesser General Public License version 3, as published
    by the Free Software Foundation.

    This program is distributed in the hope that it will be useful, but
    WITHOUT ANY WARRANTY; without even the implied warranties of
    MERCHANTABILITY, SATISFACTORY QUALITY, or FITNESS FOR A PARTICULAR
    PURPOSE. See the GNU General Public License for more details.

    You should have received a copy of the GNU General Public License along
    with this program. If not, see <http://www.gnu.org/licenses/>.

    Authors : Jeremy Wootten <jeremy@elementaryos.org>
***/

/* Implementations of AbstractDirectoryView are
     * IconView
     * ListView
     * ColumnView
*/

namespace FM {
    public abstract class AbstractDirectoryView : Gtk.ScrolledWindow {

        public enum TargetType {
            STRING,
            TEXT_URI_LIST,
            XDND_DIRECT_SAVE0,
            NETSCAPE_URL
        }

        protected enum ClickZone {
            EXPANDER,
            HELPER,
            ICON,
            NAME,
            BLANK_PATH,
            BLANK_NO_PATH,
            INVALID
        }

        const int MAX_TEMPLATES = 32;

        const Gtk.TargetEntry [] drag_targets = {
            {"text/plain", Gtk.TargetFlags.SAME_APP, TargetType.STRING},
            {"text/uri-list", Gtk.TargetFlags.SAME_APP, TargetType.TEXT_URI_LIST}
        };

        const Gtk.TargetEntry [] drop_targets = {
            {"text/uri-list", Gtk.TargetFlags.SAME_APP, TargetType.TEXT_URI_LIST},
            {"text/uri-list", Gtk.TargetFlags.OTHER_APP, TargetType.TEXT_URI_LIST},
            {"XdndDirectSave0", Gtk.TargetFlags.OTHER_APP, TargetType.XDND_DIRECT_SAVE0},
            {"_NETSCAPE_URL", Gtk.TargetFlags.OTHER_APP, TargetType.NETSCAPE_URL}
        };

        const Gdk.DragAction file_drag_actions = (Gdk.DragAction.COPY | Gdk.DragAction.MOVE | Gdk.DragAction.LINK);

        /* Menu Handling */
        const GLib.ActionEntry [] selection_entries = {
            {"open", on_selection_action_open_executable},
            {"open_with_app", on_selection_action_open_with_app, "s"},
            {"open_with_default", on_selection_action_open_with_default},
            {"open_with_other_app", on_selection_action_open_with_other_app},
            {"rename", on_selection_action_rename},
            {"view_in_location", on_selection_action_view_in_location},
            {"forget", on_selection_action_forget},
            {"cut", on_selection_action_cut},
            {"trash", on_selection_action_trash},
            {"delete", on_selection_action_delete},
            {"restore", on_selection_action_restore}
        };

        const GLib.ActionEntry [] background_entries = {
            {"new", on_background_action_new, "s"},
            {"create_from", on_background_action_create_from, "s"},
            {"sort_by", on_background_action_sort_by_changed, "s", "'name'"},
            {"reverse", on_background_action_reverse_changed, null, "false"},
            {"show_hidden", null, null, "false", change_state_show_hidden}
        };

        const GLib.ActionEntry [] common_entries = {
            {"copy", on_common_action_copy},
            {"paste_into", on_common_action_paste_into},
            {"open_in", on_common_action_open_in, "s"},
            {"bookmark", on_common_action_bookmark},
            {"properties", on_common_action_properties}
        };

        GLib.SimpleActionGroup common_actions;
        GLib.SimpleActionGroup selection_actions;
        GLib.SimpleActionGroup background_actions;

        private Marlin.ZoomLevel _zoom_level;
        public Marlin.ZoomLevel zoom_level {
            get {
                return _zoom_level;
            }

            set {
                if (value <= maximum_zoom &&
                    value >= minimum_zoom &&
                    value != _zoom_level) {

                        _zoom_level = value;
                        on_zoom_level_changed (value);
                }
            }
        }

        public int icon_size {
            get {
                return Marlin.zoom_level_to_icon_size (_zoom_level);
            }
        }

        protected Marlin.ZoomLevel minimum_zoom = Marlin.ZoomLevel.SMALLEST;
        protected Marlin.ZoomLevel maximum_zoom = Marlin.ZoomLevel.LARGEST;

        /* drag support */
        uint drag_scroll_timer_id = 0;
        uint drag_timer_id = 0;
        uint drag_enter_timer_id = 0;
        int drag_x = 0;
        int drag_y = 0;
        int drag_button;
        protected int drag_delay = 300;
        protected int drag_enter_delay = 1000;

        Gdk.DragAction current_suggested_action = Gdk.DragAction.DEFAULT;
        Gdk.DragAction current_actions = Gdk.DragAction.DEFAULT;

        unowned GLib.List<GOF.File> drag_file_list = null;
        GOF.File? drop_target_file = null;
        Gdk.Atom current_target_type = Gdk.Atom.NONE;

        /* drop site support */
        bool _drop_highlight;
        bool drop_highlight {
            get {
                return _drop_highlight;
            }

            set {
                if (value != _drop_highlight) {
                    if (value)
                        Gtk.drag_highlight (this);
                    else
                        Gtk.drag_unhighlight (this);
                }
                _drop_highlight = value;
            }
        }

        private bool drop_data_ready = false; /* whether the drop data was received already */
        private bool drop_occurred = false; /* whether the data was dropped */
        private bool drag_has_begun = false;
        protected bool dnd_disabled = false;
        private void* drag_data;
        private GLib.List<GLib.File> drop_file_list = null; /* the list of URIs that are contained in the drop data */

        /* support for generating thumbnails */
        uint thumbnail_request = 0;
        uint thumbnail_source_id = 0;
        Marlin.Thumbnailer thumbnailer = null;

        /**TODO** Support for preview see bug #1380139 */

        private string? previewer = null;

        /* Rename support */
        protected Marlin.TextRenderer? name_renderer = null;
        unowned Marlin.AbstractEditableLabel? editable_widget = null;
        public string original_name = "";
        public string proposed_name = "";

        /* Support for zoom by smooth scrolling */
        private double total_delta_y = 0.0;

        /* UI options for button press handling */
        protected bool single_click_rename = false;
        protected bool activate_on_blank = true;
        protected bool right_margin_unselects_all = false;
        public bool single_click_mode {get; set;}
        protected bool should_activate = false;
        protected bool should_scroll = true;
        protected bool should_deselect = false;
        protected Gtk.TreePath? click_path = null;
        protected uint click_zone = ClickZone.ICON;
        protected uint previous_click_zone = ClickZone.ICON;

        /* Cursors for different areas */
        private Gdk.Cursor editable_cursor;
        private Gdk.Cursor activatable_cursor;
        private Gdk.Cursor blank_cursor;
        private Gdk.Cursor selectable_cursor;

        private GLib.List<GLib.AppInfo> open_with_apps;
        protected GLib.List<GOF.Directory.Async> loaded_subdirectories = null;

        /*  Selected files are originally obtained with
            gtk_tree_model_get(): this function increases the reference
            count of the file object.*/
        protected GLib.List<GOF.File> selected_files = null;

        private GLib.List<GLib.File> templates = null;

        private GLib.AppInfo default_app;
        private Gtk.TreePath? hover_path = null;

        private bool can_trash_or_delete = true;

        /* Rapid keyboard paste support */
        protected bool pasting_files = false;
        protected bool select_added_files = false;
        private HashTable? pasted_files = null;

        public bool renaming {get; protected set; default = false;}

        private bool updates_frozen = false;
        protected bool tree_frozen = false;
        private bool in_trash = false;
        private bool in_recent = false;
        private bool in_network_root = false;
        protected bool is_loading;
        protected bool helpers_shown;

        private Gtk.Widget view;
        private unowned Marlin.ClipboardManager clipboard;
        protected FM.ListModel model;
        protected Marlin.IconRenderer icon_renderer;
        protected unowned Marlin.View.Slot slot;
        protected unowned Marlin.View.Window window; /*For convenience - this can be derived from slot */
        protected static DndHandler dnd_handler = new FM.DndHandler ();

        protected unowned Gtk.RecentManager recent;

        public signal void path_change_request (GLib.File location, int flag = 0, bool new_root = true);
        public signal void item_hovered (GOF.File? file);

        public AbstractDirectoryView (Marlin.View.Slot _slot) {
            slot = _slot;
            window = _slot.window;
            editable_cursor = new Gdk.Cursor (Gdk.CursorType.XTERM);
            activatable_cursor = new Gdk.Cursor (Gdk.CursorType.HAND1);
            selectable_cursor = new Gdk.Cursor (Gdk.CursorType.ARROW);
            blank_cursor = new Gdk.Cursor (Gdk.CursorType.CROSSHAIR);
            clipboard = ((Marlin.Application)(window.application)).get_clipboard_manager ();
            icon_renderer = new Marlin.IconRenderer ();
            thumbnailer = Marlin.Thumbnailer.get ();
            model = GLib.Object.@new (FM.ListModel.get_type (), null) as FM.ListModel;
            Preferences.settings.bind ("single-click", this, "single_click_mode", SettingsBindFlags.GET);

            recent = ((Marlin.Application)(window.application)).get_recent_manager ();

             /* Currently, "single-click rename" is disabled, matching existing UI
              * Currently, "activate on blank" is enabled, matching existing UI
              * Currently, "right margin unselects all" is disabled, matching existing UI
              */

            set_up__menu_actions ();
            set_up_directory_view ();
            view = create_view ();

            if (view != null) {
                add (view);
                show_all ();
                connect_drag_drop_signals (view);
                view.add_events (Gdk.EventMask.POINTER_MOTION_MASK |
                                 Gdk.EventMask.ENTER_NOTIFY_MASK |
                                 Gdk.EventMask.LEAVE_NOTIFY_MASK);
                view.motion_notify_event.connect (on_motion_notify_event);
                view.leave_notify_event.connect (on_leave_notify_event);
                view.enter_notify_event.connect (on_enter_notify_event);
                view.key_press_event.connect (on_view_key_press_event);
                view.button_press_event.connect (on_view_button_press_event);
                view.button_release_event.connect (on_view_button_release_event);
                view.draw.connect (on_view_draw);
            }

            freeze_tree (); /* speed up loading of icon view. Thawed when directory loaded */
            set_up_zoom_level ();
            change_zoom_level ();
        }

        ~AbstractDirectoryView () {
            debug ("ADV destruct");
        }

        public bool is_in_recent () {
            return in_recent;
        }

        protected virtual void set_up_name_renderer () {
            name_renderer.editable = false;
            name_renderer.follow_state = true;
            name_renderer.edited.connect (on_name_edited);
            name_renderer.editing_canceled.connect (on_name_editing_canceled);
            name_renderer.editing_started.connect (on_name_editing_started);
        }

        private void set_up_directory_view () {
            set_policy (Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
            set_shadow_type (Gtk.ShadowType.NONE);

            size_allocate.connect_after (on_size_allocate);
            button_press_event.connect (on_button_press_event);
            popup_menu.connect (on_popup_menu);

            unrealize.connect (() => {
                clipboard.changed.disconnect (on_clipboard_changed);
            });

            realize.connect (() => {
                clipboard.changed.connect (on_clipboard_changed);
                on_clipboard_changed ();
            });

            scroll_event.connect (on_scroll_event);

            get_vadjustment ().value_changed.connect ((alloc) => {
                schedule_thumbnail_timeout ();
            });

            (GOF.Preferences.get_default ()).notify["show-hidden-files"].connect (on_show_hidden_files_changed);
            (GOF.Preferences.get_default ()).notify["interpret-desktop-files"].connect (on_interpret_desktop_files_changed);

            connect_directory_handlers (slot.directory);

            model.row_deleted.connect (on_row_deleted);
            model.sort_column_changed.connect (on_sort_column_changed);

            model.set_sort_column_id (slot.directory.file.sort_column_id, slot.directory.file.sort_order);
        }

        private void set_up__menu_actions () {
            selection_actions = new GLib.SimpleActionGroup ();
            selection_actions.add_action_entries (selection_entries, this);
            insert_action_group ("selection", selection_actions);

            background_actions = new GLib.SimpleActionGroup ();
            background_actions.add_action_entries (background_entries, this);
            insert_action_group ("background", background_actions);

            common_actions = new GLib.SimpleActionGroup ();
            common_actions.add_action_entries (common_entries, this);
            insert_action_group ("common", common_actions);

            action_set_state (background_actions, "show_hidden", Preferences.settings.get_boolean ("show-hiddenfiles"));
        }

        public void zoom_in () {
                zoom_level = zoom_level + 1;
        }

        public void zoom_out () {
                zoom_level = zoom_level - 1;
        }

        private void set_up_zoom_level () {
            zoom_level = get_set_up_zoom_level ();
            model.set_property ("size", icon_size);
        }

        public void zoom_normal () {
            zoom_level = get_normal_zoom_level ();
        }

        public void select_first_for_empty_selection () {
            if (selected_files == null)
                set_cursor (new Gtk.TreePath.from_indices (0), false, true, true);
        }

        public void select_glib_files (GLib.List<GLib.File> location_list, GLib.File? focus_location) {
            unselect_all ();
            GLib.List<GOF.File>? file_list = null;

            location_list.@foreach ((loc) => {
                file_list.prepend (GOF.File.@get (loc));
            });

            /* Because the Icon View disconnects the model while loading, we need to wait until
             * the tree is thawed and the model reconnected before selecting the files */
            Idle.add_full (GLib.Priority.LOW, () => {
                if (!tree_frozen) {
                    file_list.@foreach ((file) => {
                        Gtk.TreeIter iter;
                        if (model.get_first_iter_for_file (file, out iter)) {
                            Gtk.TreePath path = model.get_path (iter);
                            if (path != null) {
                                select_path (path);
                                if (focus_location != null && focus_location.equal (file.location))
                                    /* set cursor and scroll to focus location*/
                                    set_cursor (path, false, false, true); 
                            }
                        }
                    });
                    return false;
                } else
                    return true;
            });
        }

        public unowned GLib.List<GLib.AppInfo> get_open_with_apps () {
            return open_with_apps;
        }

        public unowned GLib.AppInfo get_default_app () {
            return default_app;
        }

        public void set_updates_frozen (bool freeze) {
            if (freeze && !updates_frozen)
                freeze_updates ();
            else if (!freeze && updates_frozen)
                unfreeze_updates ();
        }

        public bool get_updates_frozen () {
            return updates_frozen;
        }

        protected void freeze_updates () {
            updates_frozen = true;
            slot.directory.freeze_update = true;
            action_set_enabled (selection_actions, "cut", false);
            action_set_enabled (common_actions, "copy", false);
            action_set_enabled (common_actions, "paste_into", false);
            action_set_enabled (window.win_actions, "select_all", false);

            size_allocate.disconnect (on_size_allocate);
            clipboard.changed.disconnect (on_clipboard_changed);
            view.enter_notify_event.disconnect (on_enter_notify_event);
            view.key_press_event.disconnect (on_view_key_press_event);
        }

        protected void unfreeze_updates () {
            updates_frozen = false;
            slot.directory.freeze_update = false;
            update_menu_actions ();
            size_allocate.connect (on_size_allocate);
            clipboard.changed.connect (on_clipboard_changed);
            view.enter_notify_event.connect (on_enter_notify_event);
            view.key_press_event.connect (on_view_key_press_event);

        }

        public new void grab_focus () {
            if (updates_frozen)
                return;

            if (view.get_realized ())
                view.grab_focus ();
            else { /* wait until realized */
                GLib.Timeout.add (100, () => {
                    view.grab_focus ();
                    return !view.get_realized ();
                });
            }
        }

        public unowned GLib.List<GOF.File> get_selected_files () {
            return selected_files;
        }

        public bool is_frozen () {
            return updates_frozen;
        }

/*** Protected Methods */
        protected void set_active_slot (bool scroll = true) {
            slot.active (scroll);
        }

        protected void load_location (GLib.File location) {
            path_change_request (location, Marlin.OpenFlag.DEFAULT, false);
        }

        protected void load_root_location (GLib.File location) {
            path_change_request (location, Marlin.OpenFlag.DEFAULT, true);
        }

    /** Operations on selections */
        protected void activate_selected_items (Marlin.OpenFlag flag = Marlin.OpenFlag.DEFAULT,
                                                GLib.List<GOF.File> selection = get_selected_files ()) {
            if (updates_frozen || in_trash)
                return;

            uint nb_elem = selection.length ();

            if (nb_elem < 1)
                return;

            unowned Gdk.Screen screen = Eel.gtk_widget_get_screen (this);

            if (nb_elem == 1) {
                activate_file (selection.data, screen, flag, true);
                return;
            }

            /* launch each selected file individually ignoring selections greater than 10
             * Do not launch with new instances of this app - open according to flag instead
             */
            if (nb_elem < 10 && (default_app == null || app_is_this_app (default_app))) {
                foreach (GOF.File file in selection) {
                    /* Prevent too rapid activation of files - causes New Tab to crash for example */
                    if (file.is_folder ()) {
                        /* By default, multiple folders open in new tabs */
                        if (flag == Marlin.OpenFlag.DEFAULT)
                            flag = Marlin.OpenFlag.NEW_TAB;

                        GLib.Idle.add (() => {
                            activate_file (file, screen, flag, false);
                            return false;
                        });
                    } else
                        GLib.Idle.add (() => {
                            file.open_single (screen, null);
                            return false;
                        });
                }
            } else if (default_app != null) {
                GLib.Idle.add (() => {
                    open_files_with (default_app, selection);
                    return false;
                });
            }
        }

        protected void preview_selected_items () {
            if (previewer == null)  /* At present this is the case! */
                activate_selected_items (Marlin.OpenFlag.DEFAULT);
            else {
                unowned GLib.List<GOF.File>? selection = get_selected_files ();

                if (selection == null)
                    return;

                Gdk.Screen screen = Eel.gtk_widget_get_screen (this);
                GLib.List<GLib.File> location_list = null;
                GOF.File file = selection.data;
                location_list.prepend (file.location);
                Gdk.AppLaunchContext context = screen.get_display ().get_app_launch_context ();
                try {
                    GLib.AppInfo previewer_app = GLib.AppInfo.create_from_commandline (previewer, null, 0);
                    previewer_app.launch (location_list, context as GLib.AppLaunchContext);
                } catch (GLib.Error error) {
                    Eel.show_error_dialog (_("Failed to preview"), error.message, null);
                }
            }
        }

        protected void select_gof_file (GOF.File file) {
            var iter = Gtk.TreeIter ();
            if (!model.get_first_iter_for_file (file, out iter))
                return; /* file not in model */

            var path = model.get_path (iter);
            set_cursor (path, false, true, false);
        }

        protected void add_gof_file_to_selection (GOF.File file) {
            var iter = Gtk.TreeIter ();

            if (!model.get_first_iter_for_file (file, out iter))
                return; /* file not in model */

            var path = model.get_path (iter);
            select_path (path);
        }

    /** Directory signal handlers. */
        /* Signal could be from subdirectory as well as slot directory */
        protected void connect_directory_handlers (GOF.Directory.Async dir) {
            assert (dir != null);
            dir.file_loaded.connect (on_directory_file_loaded);
            dir.file_added.connect (on_directory_file_added);
            dir.file_changed.connect (on_directory_file_changed);
            dir.file_deleted.connect (on_directory_file_deleted);
            dir.icon_changed.connect (on_directory_file_icon_changed);
            dir.done_loading.connect (on_directory_done_loading);
            dir.thumbs_loaded.connect (on_directory_thumbs_loaded);
        }

        protected void disconnect_directory_handlers (GOF.Directory.Async dir) {
            /* If the directory is still loading the file_loaded signal handler
            /* will not have been disconnected */
            if (dir.is_loading ())
                dir.file_loaded.disconnect (on_directory_file_loaded);

            dir.file_added.disconnect (on_directory_file_added);
            dir.file_changed.disconnect (on_directory_file_changed);
            dir.file_deleted.disconnect (on_directory_file_deleted);
            dir.icon_changed.disconnect (on_directory_file_icon_changed);
            dir.done_loading.disconnect (on_directory_done_loading);
            dir.thumbs_loaded.disconnect (on_directory_thumbs_loaded);
        }

        public void change_directory (GOF.Directory.Async old_dir, GOF.Directory.Async new_dir) {
            cancel ();
            freeze_tree ();
            disconnect_directory_handlers (old_dir);
            block_model ();
            model.clear ();
            unblock_model ();
            if (new_dir.can_load)
                connect_directory_handlers (new_dir);
        }

        public void reload () {
            change_directory (slot.directory, slot.directory);
        }

        protected void connect_drag_drop_signals (Gtk.Widget widget) {
            /* Set up as drop site */
            Gtk.drag_dest_set (widget, Gtk.DestDefaults.MOTION, drop_targets, Gdk.DragAction.ASK | file_drag_actions);
            widget.drag_drop.connect (on_drag_drop);
            widget.drag_data_received.connect (on_drag_data_received);
            widget.drag_leave.connect (on_drag_leave);
            widget.drag_motion.connect (on_drag_motion);

            /* Set up as drag source */
            Gtk.drag_source_set (widget, Gdk.ModifierType.BUTTON1_MASK, drag_targets, file_drag_actions);
            widget.drag_begin.connect (on_drag_begin);
            widget.drag_data_get.connect (on_drag_data_get);
            widget.drag_data_delete.connect (on_drag_data_delete);
            widget.drag_end.connect (on_drag_end);
        }

        protected void cancel_drag_timer () {
            disconnect_drag_timeout_motion_and_release_events ();
            cancel_timeout (ref drag_timer_id);
        }

        protected void cancel_thumbnailing () {
            slot.directory.cancel ();
            cancel_timeout (ref thumbnail_source_id);

            if (thumbnail_request > 0) {
                thumbnailer.dequeue (thumbnail_request);
                thumbnail_request = 0;
            }
        }

        protected bool is_drag_pending () {
            return drag_has_begun;
        }

        protected bool selection_only_contains_folders (GLib.List<GOF.File> list) {
            bool only_folders = true;

            list.@foreach ((file) => {
                if (!(file.is_folder () || file.is_root_network_folder ()))
                    only_folders = false;
            });

            return only_folders;
        }

    /** Handle scroll events */
        protected bool handle_scroll_event (Gdk.EventScroll event) {
            if (updates_frozen)
                return true;

            if ((event.state & Gdk.ModifierType.CONTROL_MASK) > 0) {
                switch (event.direction) {
                    case Gdk.ScrollDirection.UP:
                        zoom_in ();
                        return true;

                    case Gdk.ScrollDirection.DOWN:
                        zoom_out ();
                        return true;

                    case Gdk.ScrollDirection.SMOOTH:
                        double delta_x, delta_y;
                        event.get_scroll_deltas (out delta_x, out delta_y);
                        /* try to emulate a normal scrolling event by summing deltas.
                         * step size of 0.5 chosen to match sensitivity */
                        total_delta_y += delta_y;

                        if (total_delta_y >= 0.5) {
                            total_delta_y = 0;
                            zoom_out ();
                        } else if (total_delta_y <= -0.5) {
                            total_delta_y = 0;
                            zoom_in ();
                        }
                        return true;

                    default:
                        break;
                }
            }
            return false;
        }

        protected void show_or_queue_context_menu (Gdk.Event event) {
            if (selected_files != null)
                queue_context_menu (event);
            else
                show_context_menu (event);
        }

        protected unowned GLib.List<GOF.File> get_selected_files_for_transfer (GLib.List<unowned GOF.File> selection = get_selected_files ()) {
            unowned GLib.List<GOF.File> list = null;

            selection.@foreach ((file) => {
                list.prepend (file);
            });

            return list;
        }

/*** Private methods */
    /** File operations */

        private void activate_file (GOF.File _file, Gdk.Screen? screen, Marlin.OpenFlag flag, bool only_one_file) {
            if (updates_frozen || in_trash)
                return;

            GOF.File file = _file;
            if (in_recent)
                file = GOF.File.get_by_uri (file.get_display_target_uri ());

            default_app = Marlin.MimeActions.get_default_application_for_file (file);
            GLib.File location = file.get_target_location ();

            if (screen == null)
                screen = Eel.gtk_widget_get_screen (this);

            if (file.is_folder () ||
                file.get_ftype () == "inode/directory" ||
                file.is_root_network_folder ()) {

                switch (flag) {
                    case Marlin.OpenFlag.NEW_TAB:
                        window.add_tab (location, Marlin.ViewMode.CURRENT);
                        break;

                    case Marlin.OpenFlag.NEW_WINDOW:
                        window.add_window(location, Marlin.ViewMode.CURRENT);
                        break;

                    default:
                        if (only_one_file)
                            load_location (location);

                        break;
                }
            } else if (only_one_file && file.is_root_network_folder ())
                load_location (location);
            else if (only_one_file && file.is_executable ())
                file.execute (screen, null, null);
            else if (only_one_file && default_app != null)
                file.open_single (screen, default_app);
            else
                warning ("Unable to activate this file.  Default app is %s",
                         default_app != null ? default_app.get_name () : "null");
        }

        private void trash_or_delete_files (GLib.List<GOF.File> file_list,
                                            bool delete_if_already_in_trash,
                                            bool delete_immediately) {

            GLib.List<GLib.File> locations = null;
            if (in_recent) {
                file_list.@foreach ((file) => {
                    locations.prepend (GLib.File.new_for_uri (file.get_display_target_uri ()));
                });
            } else {
                file_list.@foreach ((file) => {
                    locations.prepend (file.location);
                });
            }

            if (locations != null) {
                locations.reverse ();

                if (delete_immediately)
                    Marlin.FileOperations.@delete (locations,
                                                   window as Gtk.Window,
                                                   after_trash_or_delete,
                                                   this);
                else
                    Marlin.FileOperations.trash_or_delete (locations,
                                                           window as Gtk.Window,
                                                           after_trash_or_delete,
                                                           this);
            }

            /* If in recent "folder" we need to refresh the view. */
            if (in_recent) {
                slot.directory.clear_directory_info ();
                slot.directory.need_reload ();
            }
        }

        private void add_file (GOF.File file, GOF.Directory.Async dir) {
            model.add_file (file, dir);

            if (select_added_files)
                add_gof_file_to_selection (file);
        }

        private void new_empty_file (string? parent_uri = null) {
            if (parent_uri == null)
                parent_uri = slot.directory.file.uri;

            /* Block the async directory file monitor to avoid generating unwanted "add-file" events */
            slot.directory.block_monitor ();
            Marlin.FileOperations.new_file (this as Gtk.Widget,
                                            null,
                                            parent_uri,
                                            null,
                                            null,
                                            0,
                                            (Marlin.CreateCallback?) create_file_done,
                                            this);
        }

        private void new_empty_folder () {
            /* Block the async directory file monitor to avoid generating unwanted "add-file" events */
            slot.directory.block_monitor ();
            Marlin.FileOperations.new_folder (null, null, slot.location, (Marlin.CreateCallback?) create_file_done, this);
        }

        protected void rename_file (GOF.File file_to_rename) {
            var iter = Gtk.TreeIter ();
            uint count = 0;
            /* Allow time for the file to appear in the tree model before renaming
             */
            GLib.Timeout.add (10, () => {
                if (model.get_first_iter_for_file (file_to_rename, out iter)) {
                    /* Assume writability on remote locations */
                    /**TODO** Reliably determine writability with various remote protocols.*/
                    if (file_to_rename.is_writable () || !slot.directory.is_local)
                        start_renaming_file (file_to_rename, false);
                    else
                        warning ("You do not have permission to rename this file");
                } else if (count < 100) {
                    /* Guard against possible infinite loop */
                    count++;
                    return true;
                }

                return false;
            });
        }


/** File operation callbacks */
        static void create_file_done (GLib.File? new_file, void* data) {
            var view = data as FM.AbstractDirectoryView;
            view.slot.directory.unblock_monitor ();

            if (new_file == null)
                return;


            if (view == null) {
                warning ("View invalid after creating file");
                return;
            }

            var file_to_rename = GOF.File.@get (new_file);
            view.slot.reload (true); /* non-local only */

            view.rename_file (file_to_rename); /* will wait for file to appear in model */
            view.slot.directory.unblock_monitor ();

        }

        /** Must pass a pointer to an instance of FM.AbstractDirectoryView as 3rd parameter when
          * using this callback */
        public static void after_trash_or_delete (bool user_cancel, void* data) {
            var view = data as FM.AbstractDirectoryView;
            if (view == null)
                return;

            view.can_trash_or_delete = true;
            view.slot.reload (true); /* non-local only */
        }

        private void trash_or_delete_selected_files (bool delete_immediately = false) {
        /* This might be rapidly called multiple times for the same selection
         * when using keybindings. So we remember if the current selection
         * was already removed (but the view doesn't know about it yet).
         */
            if (!can_trash_or_delete)
                return;

            unowned GLib.List<GOF.File> selection = get_selected_files_for_transfer ();
            if (selection != null) {
                can_trash_or_delete = false;

                trash_or_delete_files (selection, true, delete_immediately);
            }
        }

        private void delete_selected_files () {
            unowned GLib.List<GOF.File> selection = get_selected_files_for_transfer ();
            if (selection == null)
                return;

            GLib.List<GLib.File> locations = null;

            selection.@foreach ((file) => {
                locations.prepend (file.location);
            });

            locations.reverse ();
            Marlin.FileOperations.@delete (locations, window as Gtk.Window, after_trash_or_delete, this);
        }

/** Signal Handlers */

    /** Menu actions */
        /** Selection actions */

        private void on_selection_action_view_in_location (GLib.SimpleAction action, GLib.Variant? param) {
            view_selected_file ();
        }

        private void view_selected_file () {
            if (selected_files == null)
                return;

            foreach (GOF.File file in selected_files) {
                window.add_tab (GLib.File.new_for_uri (file.get_display_target_uri ()), Marlin.ViewMode.CURRENT);
            }        
        }

        private void on_selection_action_forget (GLib.SimpleAction action, GLib.Variant? param) {
            forget_selected_file ();
        }

        private void forget_selected_file () {
            if (selected_files == null)
                return;

            try {
                foreach (var file in selected_files) {
                    recent.remove_item (file.get_display_target_uri ());
                }
            } catch (Error err) {
                critical (err.message);
            }
        }

        private void on_selection_action_rename (GLib.SimpleAction action, GLib.Variant? param) {
            rename_selected_file ();
        }

        private void rename_selected_file () {
            if (selected_files == null)
                return;

            if (selected_files.next != null)
                warning ("Cannot rename multiple files (yet) - renaming first only");

            /**TODO** invoke batch renamer see bug #1014122*/

            rename_file (selected_files.first ().data);
        }

        private void on_selection_action_cut (GLib.SimpleAction action, GLib.Variant? param) {
            unowned GLib.List<GOF.File> selection = get_selected_files_for_transfer ();
            clipboard.cut_files (selection);
        }

        private void on_selection_action_trash (GLib.SimpleAction action, GLib.Variant? param) {
            trash_or_delete_selected_files (false);
        }

        private void on_selection_action_delete (GLib.SimpleAction action, GLib.Variant? param) {
            trash_or_delete_selected_files (true);
        }

        private void on_selection_action_restore (GLib.SimpleAction action, GLib.Variant? param) {
            unowned GLib.List<GOF.File> selection = get_selected_files_for_transfer ();
            Marlin.restore_files_from_trash (selection, window);
        }

        private void on_selection_action_open_executable (GLib.SimpleAction action, GLib.Variant? param) {
            unowned GLib.List<GOF.File> selection = get_files_for_action ();
            GOF.File file = selection.data as GOF.File;
            unowned Gdk.Screen screen = Eel.gtk_widget_get_screen (this);
            file.execute (screen, null, null);
        }

        private void on_selection_action_open_with_default (GLib.SimpleAction action, GLib.Variant? param) {
            activate_selected_items (Marlin.OpenFlag.DEFAULT);
        }

        private void on_selection_action_open_with_app (GLib.SimpleAction action, GLib.Variant? param) {
            var index = int.parse (param.get_string ());
            open_files_with (open_with_apps.nth_data ((uint)index), get_files_for_action ());
        }

        private void on_selection_action_open_with_other_app () {
            unowned GLib.List<GOF.File> selection = get_files_for_action ();
            GOF.File file = selection.data as GOF.File;

            Gtk.DialogFlags flags = Gtk.DialogFlags.MODAL |
                                    Gtk.DialogFlags.DESTROY_WITH_PARENT;

            var dialog = new Gtk.AppChooserDialog (window, flags, file.location);
            dialog.set_deletable (false);

            var app_chooser = dialog.get_widget () as Gtk.AppChooserWidget;
            app_chooser.set_show_recommended (true);

            var check_default = new Gtk.CheckButton.with_label (_("Set as default"));
            check_default.set_active (true);
            check_default.show ();

            var action_area = dialog.get_action_area () as Gtk.ButtonBox;
            action_area.add (check_default);
            action_area.set_child_secondary (check_default, true);

            dialog.show ();
            int response = dialog.run ();

            if (response == Gtk.ResponseType.OK) {
                var app =dialog.get_app_info ();
                if (check_default.get_active ()) {
                    try {
                        app.set_as_default_for_type (file.get_ftype ());
                    }
                    catch (GLib.Error error) {
                        critical ("Could not set as default: %s", error.message);
                    }
                }
                open_files_with (app, selection);
            }

            dialog.destroy ();
        }

        private void on_common_action_bookmark (GLib.SimpleAction action, GLib.Variant? param) {
            GLib.File location;
            if (selected_files != null)
                location = selected_files.data.get_target_location ();
            else
                location = slot.directory.file.get_target_location ();

            window.sidebar.add_uri (location.get_uri (), null);
        }

        /** Background actions */

        private void change_state_show_hidden (GLib.SimpleAction action) {
            window.change_state_show_hidden (action);
        }

        private void on_background_action_new (GLib.SimpleAction action, GLib.Variant? param) {
            switch (param.get_string ()) {
                case "FOLDER":
                    new_empty_folder ();
                    break;

                case "FILE":
                    new_empty_file ();
                    break;

                default:
                    break;
            }
        }

        private void on_background_action_create_from (GLib.SimpleAction action, GLib.Variant? param) {
            int index = int.parse (param.get_string ());
            create_from_template (templates.nth_data ((uint)index));
        }

        private void on_background_action_sort_by_changed (GLib.SimpleAction action, GLib.Variant? val) {
            string sort = val.get_string ();
            set_sort (sort, false);
        }
        private void on_background_action_reverse_changed (GLib.SimpleAction action, GLib.Variant? val) {
            set_sort (null, true);
        }

        private void set_sort (string? col_name, bool reverse) {
            int sort_column_id;
            Gtk.SortType sort_order;

            if (model.get_sort_column_id (out sort_column_id, out sort_order)) {
                if (col_name != null)
                    sort_column_id = get_column_id_from_string (col_name);

                if (reverse) {
                    if (sort_order == Gtk.SortType.ASCENDING)
                        sort_order = Gtk.SortType.DESCENDING;
                    else
                        sort_order = Gtk.SortType.ASCENDING;
                }

                model.set_sort_column_id (sort_column_id, sort_order);
            }
        }

        /** Common actions */

        private void on_common_action_open_in (GLib.SimpleAction action, GLib.Variant? param) {
            default_app = null;

            switch (param.get_string ()) {
                case "TAB":
                    activate_selected_items (Marlin.OpenFlag.NEW_TAB, get_files_for_action ());
                    break;

                case "WINDOW":
                    activate_selected_items (Marlin.OpenFlag.NEW_WINDOW, get_files_for_action ());
                    break;

                case "TERMINAL":
                    open_selected_in_terminal (get_files_for_action ());
                    break;

                default:
                    break;
            }
        }

        private void open_selected_in_terminal (GLib.List<GOF.File> selection = get_selected_files ()) {
            var terminal = new GLib.DesktopAppInfo (Marlin.OPEN_IN_TERMINAL_DESKTOP_ID);

            if (terminal != null)
                open_files_with (terminal, selection);
        }

        private void on_common_action_properties (GLib.SimpleAction action, GLib.Variant? param) {
            new Marlin.View.PropertiesWindow (get_files_for_action (), this, window);
        }

        private void on_common_action_copy (GLib.SimpleAction action, GLib.Variant? param) {
            clipboard.copy_files (get_selected_files_for_transfer (get_files_for_action ()));
        }

        public static void after_pasting_files (GLib.HashTable? uris, void* pointer) {
            if (pointer == null)
                return;

            var view = pointer as FM.AbstractDirectoryView;
            if (view == null) {
                warning ("view no longer valid after pasting files");
                return;
            }

            view.pasting_files = false;
            if (uris == null || uris.size () == 0)
                return;

            view.pasted_files = uris;

            Idle.add (() => {
                /* Select the most recently pasted files */
                GLib.List<GLib.File> pasted_files_list = null;
                view.pasted_files.foreach ((k, v) => {
                    if (k is GLib.File)
                        pasted_files_list.prepend (k as File);
                });

                view.slot.reload (true); /* non-local only */
                view.select_glib_files (pasted_files_list, pasted_files_list.first ().data);
                return false;
            });
        }

        private void on_common_action_paste_into (GLib.SimpleAction action, GLib.Variant? param) {
            if (pasting_files)
                return;

            var file = get_files_for_action ().nth_data (0);

            if (file != null && clipboard.get_can_paste ()) {
                GLib.File target;
                GLib.Callback? call_back;

                if (file.is_folder () && !clipboard.has_file (file))
                    target = file.get_target_location ();
                else
                    target = slot.location;

                if (target.has_uri_scheme ("trash")) {
                    /* Pasting files into trash is equivalent to trash or delete action */
                    pasting_files = false;
                    call_back = (GLib.Callback)after_trash_or_delete;
                } else {
                    pasting_files = true;
                    /* callback takes care of selecting pasted files */
                    call_back = (GLib.Callback)after_pasting_files;
                }

                clipboard.paste_files (target, this as Gtk.Widget, call_back);
            }
        }

        private void on_directory_file_added (GOF.Directory.Async dir, GOF.File file) {
            add_file (file, dir);
        }

        private void on_directory_file_loaded (GOF.Directory.Async dir, GOF.File file) {
            select_added_files = false;
            add_file (file, dir);
        }

        private void on_directory_file_changed (GOF.Directory.Async dir, GOF.File file) {
            remove_marlin_icon_info_cache (file);
            model.file_changed (file, dir);
            /* 2nd parameter is for returned request id if required - we do not use it? */
            /* This is required if we need to dequeue the request */
            if (slot.directory.is_local)
                thumbnailer.queue_file (file, null, false);
        }

        private void on_directory_file_icon_changed (GOF.Directory.Async dir, GOF.File file) {
            model.file_changed (file, dir);
        }

        private void on_directory_file_deleted (GOF.Directory.Async dir, GOF.File file) {
            remove_marlin_icon_info_cache (file);
            model.remove_file (file, dir);
            if (file.is_folder ()) {
                var file_dir = GOF.Directory.Async.cache_lookup (file.location);
                if (file_dir != null) {
                    file_dir.purge_dir_from_cache ();
                    slot.folder_deleted (file, file_dir);
                }
            }
        }

        private void  on_directory_done_loading (GOF.Directory.Async dir) {
            debug ("DV  directory done loading %s", dir.file.uri);
            dir.file_loaded.disconnect (on_directory_file_loaded);
            in_trash = slot.directory.is_trash;
            in_recent = slot.directory.is_recent;
            in_network_root = slot.directory.file.is_root_network_folder ();
            thaw_tree ();

            if (in_recent)
                model.set_sort_column_id (get_column_id_from_string ("modified"), Gtk.SortType.DESCENDING);
            else
                model.set_sort_column_id (slot.directory.file.sort_column_id, slot.directory.file.sort_order);

            /* This is a workround for a bug (Gtk?) in the drawing of the ListView where the columns
             * are sometimes not properly aligned when first drawn, only after redrawing the view. */
            Idle.add (() => {
                queue_draw ();
                return false;
            });
        }

        private void on_directory_thumbs_loaded (GOF.Directory.Async dir) {
            Marlin.IconInfo.infos_caches ();
        }

    /** Handle zoom level change */
        private void on_zoom_level_changed (Marlin.ZoomLevel zoom) {
            model.set_property ("size", icon_size);
            change_zoom_level ();

            if (get_realized () && slot.directory.is_local)
                load_thumbnails (slot.directory, zoom);
        }

    /** Handle Preference changes */
        private void on_show_hidden_files_changed (GLib.Object prefs, GLib.ParamSpec pspec) {
            bool show = (prefs as GOF.Preferences).show_hidden_files;
            cancel ();
            if (!show) {
                block_model ();
                model.clear ();
            }

            directory_hidden_changed (slot.directory, show);

            if (!show)
                unblock_model ();

            action_set_state (background_actions, "show_hidden", show);
        }

        private void directory_hidden_changed (GOF.Directory.Async dir, bool show) {
            dir.file_loaded.connect (on_directory_file_loaded); /* disconnected by on_done_loading callback.*/

            if (show)
                dir.load_hiddens ();
            else
                dir.load ();
        }

        private void on_interpret_desktop_files_changed () {
            slot.directory.update_desktop_files ();
        }

    /** Handle popup menu events */
        private bool on_popup_menu () {
            Gdk.Event event = Gtk.get_current_event ();
            show_or_queue_context_menu (event);
            return true;
        }

    /** Handle Button events */
        private bool on_drag_timeout_button_release (Gdk.EventButton event) {
            /* Only active during drag timeout */
            cancel_drag_timer ();

            if (drag_button == Gdk.BUTTON_SECONDARY)
                show_context_menu (event);

            return true;
        }

        private bool on_button_press_event (Gdk.EventButton event) {
            /* Extra mouse button action: button8 = "Back" button9 = "Forward" */
            GLib.Action? action = null;
            GLib.SimpleActionGroup main_actions = window.get_action_group ();
            if (event.type == Gdk.EventType.BUTTON_PRESS) {
                if (event.button == 8)
                    action = main_actions.lookup_action ("Back");
                else if (event.button == 9)
                    action = main_actions.lookup_action ("Forward");

                if (action != null) {
                    action.activate (null);
                    return true;
                }
            }
            return false;
        }

/** Handle Motion events */
        private bool on_drag_timeout_motion_notify (Gdk.EventMotion event) {
            /* Only active during drag timeout */
            Gdk.DragContext context;
            var widget = get_real_view ();
            int x = (int)event.x;
            int y = (int)event.y;

            if (Gtk.drag_check_threshold (widget, drag_x, drag_y, x, y)) {
                cancel_drag_timer ();
                should_activate = false;
                var target_list = new Gtk.TargetList (drag_targets);
                var actions = file_drag_actions;

                if (drag_button == 3)
                    actions |= Gdk.DragAction.ASK;

                context = Gtk.drag_begin_with_coordinates (widget,
                                target_list,
                                actions,
                                drag_button,
                                (Gdk.Event) event,
                                 x, y);
                return true;
            } else
                return false;
        }

/** Handle TreeModel events */
        protected virtual void on_row_deleted (Gtk.TreePath path) {
                unselect_all ();
        }

/** Handle clipboard signal */
        private void on_clipboard_changed () {
            /* show possible change in appearance of cut items */
            queue_draw ();
        }

/** Handle Selection changes */
        public void notify_selection_changed () {
            if (!get_realized ())
                return;

            if (updates_frozen)
                return;

            window.selection_changed (get_selected_files ());
        }

    /** Handle size allocation event */
        private void on_size_allocate (Gtk.Allocation allocation) {
            schedule_thumbnail_timeout ();
        }

/** DRAG AND DROP */

    /** Handle Drag source signals*/

        private void on_drag_begin (Gdk.DragContext context) {
            drag_has_begun = true;
            should_activate = false;
            drag_file_list = get_selected_files_for_transfer ();

            if (drag_file_list == null)
                return;

            GOF.File file = drag_file_list.first ().data;

            if (file != null && file.pix != null)
                Gtk.drag_set_icon_pixbuf (context, file.pix, 0, 0);
            else
                Gtk.drag_set_icon_name (context, "stock-file", 0, 0);
        }

        private void on_drag_data_get (Gdk.DragContext context,
                                       Gtk.SelectionData selection_data,
                                       uint info,
                                       uint timestamp) {
            GLib.StringBuilder sb = new GLib.StringBuilder ("");

            drag_file_list.@foreach ((file) => {
                sb.append (file.get_target_location ().get_uri ());
                sb.append ("\n");
            });

            selection_data.@set (selection_data.get_target (),
                                 8,
                                 sb.data);
        }

        private void on_drag_data_delete (Gdk.DragContext context) {
            /* block real_view default handler because handled in on_drag_end */
            GLib.Signal.stop_emission_by_name (get_real_view (), "drag-data-delete");
        }

        private void on_drag_end (Gdk.DragContext context) {
            cancel_timeout (ref drag_scroll_timer_id);
            drag_file_list = null;
            drop_target_file = null;
            current_suggested_action = Gdk.DragAction.DEFAULT;
            current_actions = Gdk.DragAction.DEFAULT;
            drag_has_begun = false;
            drop_occurred = false;
        }


/** Handle Drop target signals*/
        private bool on_drag_motion (Gdk.DragContext context,
                                     int x,
                                     int y,
                                     uint timestamp) {
            /* if we don't have drop data already ... */
            if (!drop_data_ready && !get_drop_data (context, x, y, timestamp))
                return false;
            else
            /* We have the drop data - check whether we can drop here*/
                check_destination_actions_and_target_file (context, x, y, timestamp);

            if (drag_scroll_timer_id == 0)
                start_drag_scroll_timer (context);

            Gdk.drag_status (context, current_suggested_action, timestamp);
            return true;
        }

        private bool on_drag_drop (Gdk.DragContext context,
                                   int x,
                                   int y,
                                   uint timestamp) {
            Gtk.TargetList list = null;
            string? uri = null;
            bool ok_to_drop = false;

            Gdk.Atom target = Gtk.drag_dest_find_target  (get_real_view (), context, list);

            if (target == Gdk.Atom.intern_static_string ("XdndDirectSave0")) {
                GOF.File? target_file = get_drop_target_file (x, y, null);
                if (target_file != null) {
                    /* get XdndDirectSave file name from DnD source window */
                    string? filename = dnd_handler.get_source_filename (context);
                    if (filename != null) {
                        /* Get uri of source file when dropped */
                        uri = target_file.get_target_location ().resolve_relative_path (filename).get_uri ();
                        /* Setup the XdndDirectSave property on the source window */
                        dnd_handler.set_source_uri (context, uri);
                        ok_to_drop = true;
                    } else
                        Eel.show_error_dialog (_("Cannot drop this file"), _("Invalid file name provided"), null);
                }
            } else
                ok_to_drop = (target != Gdk.Atom.NONE);

            if (ok_to_drop) {
                drop_occurred = true;
                /* request the drag data from the source (initiates
                 * saving in case of XdndDirectSave).*/
                Gtk.drag_get_data (get_real_view (), context, target, timestamp);
            }

            return ok_to_drop;
        }


        private void on_drag_data_received (Gdk.DragContext context,
                                            int x,
                                            int y,
                                            Gtk.SelectionData selection_data,
                                            uint info,
                                            uint timestamp
                                            ) {
            bool success = false;

            if (!drop_data_ready) {
                /* We don't have the drop data - extract uri list from selection data */
                string? text;
                if (dnd_handler.selection_data_is_uri_list (selection_data, info, out text)) {
                    drop_file_list = EelGFile.list_new_from_string (text);
                    drop_data_ready = true;
                }
            }

            if (drop_occurred) {
                drop_occurred = false;
                if (current_actions != Gdk.DragAction.DEFAULT) {
                    slot.reload (true); /* non-local only */

                    switch (info) {
                        case TargetType.XDND_DIRECT_SAVE0:
                            success = dnd_handler.handle_xdnddirectsave  (context,
                                                                          drop_target_file,
                                                                           selection_data);
                            break;

                        case TargetType.NETSCAPE_URL:
                            success = dnd_handler.handle_netscape_url  (context,
                                                                        drop_target_file,
                                                                        selection_data);
                            break;

                        case TargetType.TEXT_URI_LIST:
                            if ((current_actions & file_drag_actions) != 0) {
                                if (selected_files != null)
                                    unselect_all ();

                                select_added_files = true;
                                success = dnd_handler.handle_file_drag_actions  (get_real_view (),
                                                                                 window,
                                                                                 context,
                                                                                 drop_target_file,
                                                                                 drop_file_list,
                                                                                 current_actions,
                                                                                 current_suggested_action,
                                                                                 timestamp);
                            }
                            break;

                        default:
                            break;
                    }
                }
                Gtk.drag_finish (context, success, false, timestamp);
                on_drag_leave (context, timestamp);
            }
        }

        private void on_drag_leave (Gdk.DragContext context, uint timestamp) {
            /* reset the drop-file for the icon renderer */
            icon_renderer.set_property ("drop-file", GLib.Value (typeof (Object)));
            /* stop any running drag autoscroll timer */
            cancel_timeout (ref drag_scroll_timer_id);
            cancel_timeout (ref drag_enter_timer_id);

            /* disable the drop highlighting around the view */
            if (drop_highlight) {
                drop_highlight = false;
                queue_draw ();
            }

            /* reset the "drop data ready" status and free the URI list */
            if (drop_data_ready) {
                drop_file_list = null;
                drop_data_ready = false;
            }
            /* disable the highlighting of the items in the view */
            highlight_path (null);
        }

/** DnD helpers */

        private GOF.File? get_drop_target_file (int x, int y, out Gtk.TreePath? path_return) {
            Gtk.TreePath? path = get_path_at_pos (x, y);
            GOF.File? file = null;

            if (path != null) {
                file = model.file_for_path (path);
                if (file == null) {
                    /* must be on expanded empty folder, use the folder path instead */
                    Gtk.TreePath folder_path = path.copy ();
                    folder_path.up ();
                    file = model.file_for_path (folder_path);
                } else {
                    /* can only drop onto folders and executables */
                    if (!file.is_folder () && !file.is_executable ()) {
                        file = null;
                        path = null;
                    }
                }
            }

            if (path == null)
                /* drop to current folder instead */
                file = slot.directory.file;

            path_return = path;
            return file;
        }

        private bool get_drop_data (Gdk.DragContext context, int x, int y, uint timestamp) {
            Gtk.TargetList? list = null;
            Gdk.Atom target = Gtk.drag_dest_find_target (get_real_view (), context, list);
            bool result = false;
            current_target_type = target;
            /* Check if we can handle it yet */
            if (target == Gdk.Atom.intern_static_string ("XdndDirectSave0") ||
                target == Gdk.Atom.intern_static_string ("_NETSCAPE_URL")) {

                /* Determine file at current position (if any) */
                Gtk.TreePath? path = null;
                GOF.File? file = get_drop_target_file (x, y, out path);


                if (file != null &&
                    file.is_folder () &&
                    file.is_writable ()) {
                    icon_renderer.@set ("drop-file", file);
                    highlight_path (path);
                    drop_data_ready = true;
                    result = true;
                }
            } else if (target != Gdk.Atom.NONE)
                /* request the drag data from the source */
                Gtk.drag_get_data (get_real_view (), context, target, timestamp); /* emits "drag_data_received" */

            return result;
        }

        private void check_destination_actions_and_target_file (Gdk.DragContext context, int x, int y, uint timestamp) {
            Gtk.TreePath? path;
            GOF.File? file = get_drop_target_file (x, y, out path);
            string uri = file != null ? file.uri : "";
            string current_uri = drop_target_file != null ? drop_target_file.uri : "";

            Gdk.drag_status (context, Gdk.DragAction.MOVE, timestamp);
            if (uri != current_uri) {
                drop_target_file = file;
                current_actions = Gdk.DragAction.DEFAULT;
                current_suggested_action = Gdk.DragAction.DEFAULT;

                if (file != null) {
                    if (current_target_type == Gdk.Atom.intern_static_string ("XdndDirectSave0")) {
                        current_suggested_action = Gdk.DragAction.COPY;
                        current_actions = current_suggested_action;
                    } else
                        current_actions = file.accepts_drop (drop_file_list, context, out current_suggested_action);

                    highlight_drop_file (drop_target_file, current_actions, path);

                    if (file.is_folder () && is_valid_drop_folder (file)) {
                        /* open the target folder after a short delay */
                        cancel_timeout (ref drag_enter_timer_id);
                        drag_enter_timer_id = GLib.Timeout.add_full (GLib.Priority.LOW,
                                                                     drag_enter_delay,
                                                                     () => {
                            load_location (file.get_target_location ());
                            drag_enter_timer_id = 0;
                            return false;
                        });
                    }
                }
            }
        }

        private bool is_valid_drop_folder (GOF.File file) {
            /* Cannot drop onto a file onto its parent or onto itself */
            if (file.uri != slot.uri &&
                drag_file_list != null &&
                drag_file_list.index (file) < 0)

                return true;
            else
                return false;
        }

        private void highlight_drop_file (GOF.File drop_file, Gdk.DragAction action, Gtk.TreePath? path) {
            bool can_drop = (action > Gdk.DragAction.DEFAULT);

            if (drop_highlight != can_drop) {
                drop_highlight = can_drop;
                queue_draw ();
            }

            /* Set the icon_renderer drop-file if there is an action */
            drop_file =  can_drop ? drop_file : null;
            icon_renderer.set_property ("drop-file", drop_file);

            highlight_path (can_drop ? path : null);
        }

/** MENU FUNCTIONS */

        /*
         * (derived from thunar: thunar_standard_view_queue_popup)
         *
         * Schedules a context menu popup in response to
         * a right-click button event. Right-click events
         * need to be handled in a special way, as the
         * user may also start a drag using the right
         * mouse button and therefore this function
         * schedules a timer, which - once expired -
         * opens the context menu. If the user moves
         * the mouse prior to expiration, a right-click
         * drag (with #GDK_ACTION_ASK) will be started
         * instead.
        **/

        private void queue_context_menu (Gdk.Event event) {
            if (drag_timer_id > 0) /* already queued */
                return;

            start_drag_timer (event);
        }

        protected void start_drag_timer (Gdk.Event event) {
            connect_drag_timeout_motion_and_release_events ();
            var button_event = (Gdk.EventButton)event;
            drag_button = (int)(button_event.button);

            drag_timer_id = GLib.Timeout.add_full (GLib.Priority.LOW,
                                                   drag_delay,
                                                   () => {
                on_drag_timeout_button_release((Gdk.EventButton)event);
                return false;
            });
        }

        protected void show_context_menu (Gdk.Event event) {
            /* select selection or background context menu */
            update_menu_actions ();
            var builder = new Gtk.Builder.from_file (Config.UI_DIR + "directory_view_popup.ui");
            GLib.MenuModel? model = null;

            if (get_selected_files () != null)
                model = build_menu_selection (ref builder, in_trash, in_recent);
            else
                model = build_menu_background (ref builder, in_trash, in_recent);

            if (model != null && model is GLib.MenuModel) {
                /* add any additional entries from plugins */
                var menu = new Gtk.Menu.from_model (model);

                if (!in_trash)
                    plugins.hook_context_menu (menu as Gtk.Widget, get_selected_files ());

                menu.set_screen (null);
                menu.attach_to_widget (this, null);
                Eel.pop_up_context_menu (menu,
                                         Eel.DEFAULT_POPUP_MENU_DISPLACEMENT,
                                         Eel.DEFAULT_POPUP_MENU_DISPLACEMENT,
                                         (Gdk.EventButton) event);
            }
        }

        private bool valid_selection_for_edit () {
            foreach (GOF.File file in get_selected_files ()) {
                if (file.is_root_network_folder ())
                    return false;
            }
            return true;
        }

        private GLib.MenuModel? build_menu_selection (ref Gtk.Builder builder, bool in_trash, bool in_recent) {
            GLib.Menu menu = new GLib.Menu ();

            var clipboard_menu = builder.get_object ("clipboard-selection") as GLib.Menu;

            if (in_trash) {
                menu.append_section (null, builder.get_object ("popup-trash-selection") as GLib.Menu);

                clipboard_menu.remove (1); /* Copy */
                clipboard_menu.remove (1); /* Paste (index updated by previous line) */

                menu.append_section (null, clipboard_menu);
            } else if (in_recent) {
                var open_menu = build_menu_open (ref builder);
                if (open_menu != null)
                    menu.append_section (null, open_menu);

                menu.append_section (null, builder.get_object ("view-in-location") as GLib.Menu);
                menu.append_section (null, builder.get_object ("forget") as GLib.Menu);

                clipboard_menu.remove (0); /* Cut */
                clipboard_menu.remove (1); /* Paste */

                menu.append_section (null, clipboard_menu);

                menu.append_section (null, builder.get_object ("trash") as GLib.MenuModel);
                menu.append_section (null, builder.get_object ("properties") as GLib.Menu);
            } else {
                var open_menu = build_menu_open (ref builder);
                if (open_menu != null)
                    menu.append_section (null, open_menu);

                if (slot.directory.file.is_smb_server ()) {
                    if (common_actions.get_action_enabled ("paste_into"))
                        menu.append_section (null, builder.get_object ("paste") as GLib.MenuModel);
                } else if (valid_selection_for_edit ()) {
                    /* Do not display the 'Paste into' menuitem if selection is not a folder.
                     * We have to hard-code the menuitem index so any change to the clipboard-
                     * selection menu definition in directory_view_popup.ui may necessitate changing
                     * the index below.
                     */
                    if (!common_actions.get_action_enabled ("paste_into"))
                        clipboard_menu.remove (2);

                    menu.append_section (null, clipboard_menu);

                    if (slot.directory.has_trash_dirs)
                        menu.append_section (null, builder.get_object ("trash") as GLib.MenuModel);
                    else
                        menu.append_section (null, builder.get_object ("delete") as GLib.MenuModel);

                    menu.append_section (null, builder.get_object ("rename") as GLib.MenuModel);
                }

                if (common_actions.get_action_enabled ("bookmark"))
                    menu.append_section (null, builder.get_object ("bookmark") as GLib.MenuModel);

                menu.append_section (null, builder.get_object ("properties") as GLib.MenuModel);
            }

            return menu as MenuModel;
        }

        private GLib.MenuModel? build_menu_background (ref Gtk.Builder builder, bool in_trash, bool in_recent) {
            var menu = new GLib.Menu ();

            if (in_trash) {
                if (common_actions.get_action_enabled ("paste_into")) {
                    menu.append_section (null, builder.get_object ("paste") as GLib.MenuModel);

                    return menu as MenuModel;
                } else
                    return null;
            }

            if (in_recent) {
                menu.append_section (null, builder.get_object ("sort-by") as GLib.MenuModel);
                menu.append_section (null, builder.get_object ("hidden") as GLib.MenuModel);

                return menu as MenuModel;
            }

            menu.append_section (null, build_menu_open (ref builder));

            if (!in_network_root) {
                if (common_actions.get_action_enabled ("paste_into"))
                    menu.append_section (null, builder.get_object ("paste") as GLib.MenuModel);

                GLib.MenuModel? template_menu = build_menu_templates ();
                var new_menu = builder.get_object ("new") as GLib.Menu;

                if (template_menu != null) {
                    var new_submenu = builder.get_object ("new-submenu") as GLib.Menu;
                    new_submenu.append_section (null, template_menu);
                }

                menu.append_section (null, new_menu as GLib.MenuModel);

                menu.append_section (null, builder.get_object ("sort-by") as GLib.MenuModel);
            }

            if (common_actions.get_action_enabled ("bookmark"))
                menu.append_section (null, builder.get_object ("bookmark") as GLib.MenuModel);

            menu.append_section (null, builder.get_object ("hidden") as GLib.MenuModel);

            if (!in_network_root)
                menu.append_section (null, builder.get_object ("properties") as GLib.MenuModel);

            return menu as MenuModel;
        }

        private GLib.MenuModel build_menu_open (ref Gtk.Builder builder) {
            var menu = new GLib.Menu ();
            GLib.MenuModel? app_submenu;

            string label = _("Invalid");
            unowned GLib.List<unowned GOF.File> files_for_action = get_files_for_action ();
            unowned GLib.List<unowned GOF.File> selection = null;

            if (in_recent) {
                files_for_action.@foreach ((file) => {
                    selection.append (GOF.File.get_by_uri (file.get_display_target_uri ()));
                });
            } else
                selection = files_for_action;

            unowned GOF.File selected_file = selection.data;

            if (!selected_file.is_folder () && selected_file.is_executable ()) {
                label = _("Run");
                menu.append (label, "selection.open");
            } else if (default_app != null) {
                var app_name = default_app.get_display_name ();
                if (app_name != "Files") {
                    label = (_("Open in %s")).printf (app_name);
                    menu.append (label, "selection.open_with_default");
                }
            }

            // Hide open_with menu for the moment
            (!in_recent ? app_submenu = build_submenu_open_with_applications (ref builder, selection) : app_submenu = null);

            if (app_submenu != null && app_submenu.get_n_items () > 0) {
                if (selected_file.is_folder () || selected_file.is_root_network_folder ())
                    label =  _("Open in");
                else
                    label = _("Open with");

                menu.append_submenu (label, app_submenu);
            }

            return menu as MenuModel;
        }

        private GLib.MenuModel? build_submenu_open_with_applications (ref Gtk.Builder builder,
                                                                      GLib.List<GOF.File> selection) {

            var open_with_submenu = new GLib.Menu ();
            int index = -1;

            if (common_actions.get_action_enabled ("open_in")) {
                open_with_submenu.append_section (null, builder.get_object ("open-in") as GLib.MenuModel);

                if (!selection.data.is_mountable () && !selection.data.is_root_network_folder ())
                    open_with_submenu.append_section (null, builder.get_object ("open-in-terminal") as GLib.MenuModel);
                else
                    return open_with_submenu;
            }

            open_with_apps = Marlin.MimeActions.get_applications_for_files (selection);
            filter_default_app_from_open_with_apps ();
            filter_this_app_from_open_with_apps ();

            if (open_with_apps != null) {
                var apps_section = new GLib.Menu ();
                string last_label = "";
                open_with_apps.@foreach ((app) => {
                    if (app != null && app is AppInfo) {
                        var label = app.get_display_name ();
                        /* The following mainly applies to Nautilus, whose display name is also "Files" */
                        if (label == "Files") {
                            label = app.get_executable ();
                            label = label[0].toupper ().to_string () + label.substring (1);
                        }

                        /* Do not show same name twice - some apps have more than one .desktop file
                         * with the same name (e.g. Nautilus)
                         */
                        if (label != last_label) {
                            index++;
                            apps_section.append (label, "selection.open_with_app::" + index.to_string ());
                            last_label = label.dup ();
                        }
                    }
                });

                if (index >= 0)
                    open_with_submenu.append_section (null, apps_section);
            }

            if (selection.length () == 1) {
                var other_app_menu = new GLib.Menu ();
                other_app_menu.append ( _("Other Application"), "selection.open_with_other_app");
                open_with_submenu.append_section (null, other_app_menu);
            }

            return open_with_submenu as GLib.MenuModel;
        }

        private GLib.MenuModel? build_menu_templates () {
            /* Potential optimisation - do just once when app starts or view created */
            templates = null;
            var template_path = "%s/Templates".printf (GLib.Environment.get_home_dir ());
            var template_folder = GLib.File.new_for_path (template_path);
            load_templates_from_folder (template_folder);

            if (templates.length () == 0)
                return null;

            var templates_menu = new GLib.Menu ();
            var templates_submenu = new GLib.Menu ();
            int index = 0;
            int count = 0;

            templates.@foreach ((template) => {
                var label = template.get_basename ();
                var ftype = template.query_file_type (GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS, null);
                if (ftype == GLib.FileType.DIRECTORY) {
                    var submenu = new GLib.MenuItem.submenu (label, templates_submenu);
                    templates_menu.append_item (submenu);
                    templates_submenu = new GLib.Menu ();             
                } else {
                    templates_submenu.append (label, "background.create_from::" + index.to_string ());
                    count ++;
                }

                index++;
            });

            templates_menu.append_section (null, templates_submenu);

            if (count < 1)
                return null;
            else
                return templates_menu as MenuModel;
        }

        private void update_menu_actions () {
            if (updates_frozen)
                return;

            unowned GLib.List<GOF.File> selection = get_files_for_action ();
            GOF.File file;

            uint selection_count = selection.length ();
            bool more_than_one_selected = (selection_count > 1);
            bool single_folder = false;
            bool only_folders = selection_only_contains_folders (selection);
            bool can_rename = false;
            bool can_show_properties = false;

            if (!(in_recent && selection_count > 1))
                can_show_properties = true;
            else
                can_show_properties = false;

            update_default_app (selection);

            if (selection_count > 0) {
                file = selection.data;
                if (file != null) {
                    single_folder = (!more_than_one_selected && file.is_folder ());
                    can_rename = file.is_writable ();
                } else
                    critical ("File in selection is null");
            } else {
                file = slot.directory.file;
                single_folder = (!more_than_one_selected && file.is_folder ());
            }

            update_paste_action_enabled (single_folder);
            update_select_all_action ();
            update_menu_actions_sort ();

            action_set_enabled (common_actions, "open_in", only_folders);
            action_set_enabled (selection_actions, "rename", selection_count == 1 && can_rename);
            action_set_enabled (selection_actions, "view_in_location", selection_count > 0);
            action_set_enabled (selection_actions, "open", selection_count == 1);
            action_set_enabled (selection_actions, "cut", selection_count > 0);
            action_set_enabled (selection_actions, "trash", slot.directory.has_trash_dirs);
            action_set_enabled (common_actions, "properties", can_show_properties);

            /* Both folder and file can be bookmarked if local, but only remote folders can be bookmarked
             * because remote file bookmarks do not work correctly for unmounted locations */
            bool can_bookmark = (!more_than_one_selected || single_folder) &&
                                 (slot.directory.is_local ||
                                 (file.get_ftype () != null && file.get_ftype () == "inode/directory") ||
                                 file.is_smb_server ());

            action_set_enabled (common_actions, "bookmark", can_bookmark);

            /**TODO** inhibit copy for unreadable files see bug #1392465*/

            action_set_enabled (common_actions, "copy", !in_trash);
            action_set_enabled (common_actions, "bookmark", !more_than_one_selected);
        }

        private void update_menu_actions_sort () {
            int sort_column_id;
            Gtk.SortType sort_order;

            if (model.get_sort_column_id (out sort_column_id, out sort_order)) {
                GLib.Variant val = new GLib.Variant.string (get_string_from_column_id (sort_column_id));
                action_set_state (background_actions, "sort_by", val);
                val = new GLib.Variant.boolean (sort_order == Gtk.SortType.DESCENDING);
                action_set_state (background_actions, "reverse", val);
            }
        }

        private void update_default_app (GLib.List<unowned GOF.File> selection) {
            GLib.List<GOF.File> files = null;
            string uri = "";

            if (in_recent) {
                selection.@foreach ((file) => {
                    uri = file.get_display_target_uri ();

                    if (uri != null)
                        files.append (GOF.File.get_by_uri (uri));
                });

                if (files != null)
                    default_app = Marlin.MimeActions.get_default_application_for_files (files);
            } else
                default_app = Marlin.MimeActions.get_default_application_for_files (selection);
        }

        private void update_paste_action_enabled (bool single_folder) {
            if (clipboard != null && clipboard.get_can_paste ())
                action_set_enabled (common_actions, "paste_into", single_folder);
            else
                action_set_enabled (common_actions, "paste_into", false);
        }

        private void update_select_all_action () {
            action_set_enabled (window.win_actions, "select_all", !slot.directory.is_empty ());
        }

    /** Menu helpers */

        private void action_set_enabled (GLib.SimpleActionGroup? action_group, string name, bool enabled) {
            if (action_group != null) {
                GLib.SimpleAction? action = (action_group.lookup_action (name) as GLib.SimpleAction);
                if (action != null) {
                    action.set_enabled (enabled);
                    return;
                }
            }
            critical ("Action name not found: %s - cannot enable", name);
        }

        private void action_set_state (GLib.SimpleActionGroup? action_group, string name, GLib.Variant val) {
            if (action_group != null) {
                GLib.SimpleAction? action = (action_group.lookup_action (name) as GLib.SimpleAction);
                if (action != null) {
                    action.set_state (val);
                    return;
                }
            }
            critical ("Action name not found: %s - cannot set state", name);
        }

        private void load_templates_from_folder (GLib.File template_folder) {
            GLib.List<GLib.File> file_list = null;
            GLib.List<GLib.File> folder_list = null;

            GLib.FileEnumerator enumerator;
            var f_attr = GLib.FileAttribute.STANDARD_NAME + GLib.FileAttribute.STANDARD_TYPE;
            var flags = GLib.FileQueryInfoFlags.NOFOLLOW_SYMLINKS;
            try {
                enumerator = template_folder.enumerate_children (f_attr, flags, null);
                uint count = templates.length ();
                GLib.File location;
                GLib.FileInfo? info = enumerator.next_file (null);

                while (count < MAX_TEMPLATES && (info != null)) {
                    location = template_folder.get_child (info.get_name ());
                    if (info.get_file_type () == GLib.FileType.DIRECTORY) {
                        folder_list.prepend (location);
                    } else {
                        file_list.prepend (location);
                        count ++;
                    }

                    info = enumerator.next_file (null);
                }
            } catch (GLib.Error error) {
                return;
            }

            if (file_list.length () > 0) {
                file_list.sort ((a,b) => {
                    return strcmp (a.get_basename ().down (), b.get_basename ().down ());
                });
                foreach (var file in file_list)
                    templates.append (file);

                templates.append (template_folder);
            }

            if (folder_list.length () > 0) {
                /* recursively load templates from subdirectories */
                folder_list.@foreach ((folder) => {
                    load_templates_from_folder (folder);
                });
            }
        }

        private void filter_this_app_from_open_with_apps () {
            unowned GLib.List<AppInfo> l = open_with_apps;

            while (l != null) {
                if (l.data is AppInfo) {
                    if (app_is_this_app (l.data)) {
                        open_with_apps.delete_link (l);
                        break;
                    }
                } else {
                    open_with_apps.delete_link (l);
                    l = open_with_apps;
                    if (l == null)
                        break;
                }
                l = l.next;
            }
        }

        private bool app_is_this_app (AppInfo ai) {
            string exec_name = ai.get_executable ();

            return (exec_name == APP_NAME || exec_name == TERMINAL_NAME);
        }

        private void filter_default_app_from_open_with_apps () {
            if (default_app == null)
                return;

            string? id1, id2;
            id2 = default_app.get_id ();

            if (id2 != null) {
                unowned GLib.List<AppInfo> l = open_with_apps;

                while (l != null && l.data is AppInfo) {
                    id1 = l.data.get_id ();

                    if (id1 != null && id1 == id2) {
                        open_with_apps.delete_link (l);
                        break;
                    }

                    l = l.next;
                }
            }
        }

        /** Menu action functions */

        private void create_from_template (GLib.File template) {
            /* Block the async directory file monitor to avoid generating unwanted "add-file" events */
            slot.directory.block_monitor ();
            var new_name = (_("Untitled %s")).printf (template.get_basename ());
            Marlin.FileOperations.new_file_from_template (this,
                                                          null,
                                                          slot.location,
                                                          new_name,
                                                          template,
                                                          create_file_done,
                                                          this);
        }

        private void open_files_with (GLib.AppInfo app, GLib.List<GOF.File> files) {
            GOF.File.launch_files (files, get_screen (), app);
        }


/** Thumbnail handling */
        private void schedule_thumbnail_timeout () {
            /* delay creating the idle until the view has finished loading.
             * this is done because we only can tell the visible range reliably after
             * all items have been added and we've perhaps scrolled to the file remembered
             * the last time */

            if (thumbnail_source_id != 0 ||
                !(slot is GOF.AbstractSlot) ||
                slot.directory == null ||
                !slot.directory.is_local)

                return;

            thumbnail_source_id = GLib.Timeout.add (175, () => {
                if (!(slot is GOF.AbstractSlot) || slot.directory == null)
                    return false;

                if (slot.directory.is_loading ())
                    return true;

                cancel_thumbnailing ();

                /* compute visible item range */
                Gtk.TreePath start_path, end_path, path;
                Gtk.TreeIter iter;
                bool valid_iter;
                GOF.File file;
                GLib.List<GOF.File> visible_files = null;

                if (get_visible_range (out start_path, out end_path)) {
                    /* iterate over the range to collect all files */
                    valid_iter = model.get_iter (out iter, start_path);

                    while (valid_iter) {
                        file = model.file_for_iter (iter);

                        /* Ask thumbnail if ThumbState UNKNOWN or NONE */
                        if (file != null && file.flags < 2)
                            visible_files.prepend (file);

                        /* check if we've reached the end of the visible range */
                        path = model.get_path (iter);

                        if (path.compare (end_path) != 0)
                            valid_iter = get_next_visible_iter (ref iter);
                        else
                            valid_iter = false;
                    }
                }

                if (visible_files != null)
                    thumbnailer.queue_files (visible_files, out thumbnail_request, false);

                thumbnail_source_id = 0;
                return false;
            });
        }


/** HELPER AND CONVENIENCE FUNCTIONS */

        protected void block_model () {
            model.row_deleted.disconnect (on_row_deleted);
            updates_frozen = true;
        }

        protected void unblock_model () {
            model.row_deleted.connect (on_row_deleted);
            updates_frozen = false;
        }

        private void load_thumbnails (GOF.Directory.Async dir, Marlin.ZoomLevel zoom) {
            /* Async function checks dir is not loading and dir is local */
            dir.queue_load_thumbnails (Marlin.zoom_level_to_icon_size (zoom));
        }

        private Gtk.Widget? get_real_view () {
            return (this as Gtk.Bin).get_child ();
        }

        private void connect_drag_timeout_motion_and_release_events () {
            var real_view = get_real_view ();
            real_view.button_release_event.connect (on_drag_timeout_button_release);
            real_view.motion_notify_event.connect (on_drag_timeout_motion_notify);
        }

        private void disconnect_drag_timeout_motion_and_release_events () {
            if (drag_timer_id == 0)
                return;

            var real_view = get_real_view ();
            real_view.button_release_event.disconnect (on_drag_timeout_button_release);
            real_view.motion_notify_event.disconnect (on_drag_timeout_motion_notify);
        }

        private void start_drag_scroll_timer (Gdk.DragContext context) {
            drag_scroll_timer_id = GLib.Timeout.add_full (GLib.Priority.LOW,
                                                          50,
                                                          () => {
                Gtk.Widget widget = (this as Gtk.Bin).get_child ();
                Gdk.Device pointer = context.get_device ();
                Gdk.Window window = widget.get_window ();
                int x, y, w, h;

                window.get_device_position (pointer, out x, out y, null);
                window.get_geometry (null, null, out w, out h);

                scroll_if_near_edge (y, h, 20, get_vadjustment ());
                scroll_if_near_edge (x, w, 20, get_hadjustment ());
                return true;
            });
        }

        private void scroll_if_near_edge (int pos, int dim, int threshold, Gtk.Adjustment adj) {
                /* check if we are near the edge */
                int band = 2 * threshold;
                int offset = pos - band;
                if (offset > 0)
                    offset = int.max (band - (dim - pos), 0);

                if (offset != 0) {
                    /* change the adjustment appropriately */
                    var val = adj.get_value ();
                    var lower = adj.get_lower ();
                    var upper = adj.get_upper ();
                    var page = adj.get_page_size ();

                    val = (val + 2 * offset).clamp (lower, upper - page);
                    adj.set_value (val);
                }
        }

        private void remove_marlin_icon_info_cache (GOF.File file) {
            string? path = file.get_thumbnail_path ();

            if (path != null) {
                Marlin.IconSize s;

                for (int z = Marlin.ZoomLevel.SMALLEST;
                     z <= Marlin.ZoomLevel.LARGEST;
                     z++) {

                    s = Marlin.zoom_level_to_icon_size ((Marlin.ZoomLevel)z);
                    Marlin.IconInfo.remove_cache (path, s);
                }
            }
        }

        /* For actions on the background we need to return the current slot directory, but this
         * should not be added to the list of selected files
         */
        private unowned GLib.List<GOF.File> get_files_for_action () {
            unowned GLib.List<GOF.File> action_files = null;

            if (selected_files == null)
                action_files.prepend (slot.directory.file);
            else
                action_files = selected_files;

            return action_files;
        }

        protected void on_view_items_activated () {
            activate_selected_items (Marlin.OpenFlag.DEFAULT);
        }

        protected virtual void on_view_selection_changed () {
            update_selected_files ();
            if (updates_frozen)
                return;

            notify_selection_changed ();
        }

/** Keyboard event handling **/

        /** Returns true if the code parameter matches the keycode of the keyval parameter for
          * any keyboard group or level (in order to allow for non-QWERTY keyboards) **/ 
        protected bool match_keycode (int keyval, uint code) {
            Gdk.KeymapKey [] keys;
            Gdk.Keymap keymap = Gdk.Keymap.get_default ();
            if (keymap.get_entries_for_keyval (keyval, out keys)) {
                foreach (var key in keys) {
                    if (code == key.keycode)
                        return true;
                }
            }

            return false;
        }

        protected virtual bool on_view_key_press_event (Gdk.EventKey event) {
            if (updates_frozen || event.is_modifier == 1)
                return false;

            var mods = event.state & Gtk.accelerator_get_default_mod_mask ();
            bool no_mods = (mods == 0);
            bool shift_pressed = ((mods & Gdk.ModifierType.SHIFT_MASK) != 0);
            bool only_shift_pressed = shift_pressed && ((mods & ~Gdk.ModifierType.SHIFT_MASK) == 0);
            bool control_pressed = ((mods & Gdk.ModifierType.CONTROL_MASK) != 0);
            bool alt_pressed = ((mods & Gdk.ModifierType.MOD1_MASK) != 0);
            bool other_mod_pressed = (((mods & ~Gdk.ModifierType.SHIFT_MASK) & ~Gdk.ModifierType.CONTROL_MASK) != 0);
            bool only_control_pressed = control_pressed && !other_mod_pressed; /* Shift can be pressed */
            bool only_alt_pressed = alt_pressed && ((mods & ~Gdk.ModifierType.MOD1_MASK) == 0);
            bool in_trash = slot.location.has_uri_scheme ("trash");
            bool in_recent = slot.location.has_uri_scheme ("recent");

            switch (event.keyval) {
                case Gdk.Key.F10:
                    if (only_control_pressed) {
                        show_or_queue_context_menu (event);
                        return true;
                    }
                    break;

                case Gdk.Key.F2:
                    if (no_mods && selection_actions.get_action_enabled ("rename")) {
                        rename_selected_file ();
                        return true;
                    }
                    break;

                case Gdk.Key.Delete:
                case Gdk.Key.KP_Delete:
                    if (no_mods) {
                        /* If already in trash, permanently delete the file */
                        trash_or_delete_selected_files (in_trash);
                        return true;
                    } else if (only_shift_pressed) {
                        trash_or_delete_selected_files (true);
                        return true;
                    } else if (only_shift_pressed && !renaming) {
                        delete_selected_files ();
                        return true;
                    }
                    break;

                case Gdk.Key.space:
                    if (view_has_focus ()) {
                        if (only_shift_pressed  && !in_trash)
                            activate_selected_items (Marlin.OpenFlag.NEW_TAB);
                        else if (no_mods)
                            preview_selected_items ();
                        else
                            return false;

                        return true;
                    }
                    break;

                case Gdk.Key.Return:
                case Gdk.Key.KP_Enter:
                    if (in_trash)
                        return false;
                    else if (in_recent)
                        activate_selected_items (Marlin.OpenFlag.DEFAULT);
                    else if (only_shift_pressed)
                        activate_selected_items (Marlin.OpenFlag.NEW_TAB);
                    else if (only_alt_pressed)
                        common_actions.activate_action ("properties", null);
                    else if (no_mods)
                         activate_selected_items (Marlin.OpenFlag.DEFAULT);
                    else
                        return false;

                    return true;

                case Gdk.Key.minus:
                    if (only_alt_pressed) {
                        Gtk.TreePath? path = get_path_at_cursor ();
                        if (path != null && path_is_selected (path))
                            unselect_path (path);

                        return true;
                    }
                    break;

                case Gdk.Key.Escape:
                    if (no_mods)
                        unselect_all ();

                    break;

                case Gdk.Key.Menu:
                case Gdk.Key.MenuKB:
                    if (no_mods)
                        show_context_menu (event);

                   return true;

                case Gdk.Key.N:
                    if (shift_pressed && only_control_pressed)
                        new_empty_folder ();

                   return true;

                case Gdk.Key.A:
                    if (shift_pressed && only_control_pressed)
                        invert_selection ();

                   return true;

                default:
                    break;
            }

            /* Use hardware keycodes for cut, copy and paste so the key used
             * is unaffected by internationalized layout */
            if (only_control_pressed) {
                uint keycode = event.hardware_keycode;
                if (match_keycode (Gdk.Key.c, keycode)) {
                    /* Should not copy files in the trash - cut instead */
                    if (in_trash) {
                        Eel.show_warning_dialog (_("Cannot copy files that are in the trash"),
                                                 _("Cutting the selection instead"),
                                                 window as Gtk.Window);

                        selection_actions.activate_action ("cut", null);
                    } else
                        common_actions.activate_action ("copy", null);

                    return true;
                } else if (match_keycode (Gdk.Key.v, keycode)) {
                    if (!in_recent) {
                        /* Will drop any existing selection and paste into current directory */
                        action_set_enabled (common_actions, "paste_into", true);
                        unselect_all ();
                        common_actions.activate_action ("paste_into", null);
                        return true;
                    }
                } else if (match_keycode (Gdk.Key.x, keycode)) {
                    selection_actions.activate_action ("cut", null);
                    return true;
                }
            }

            /* Use find function instead of view interactive search */
            if (no_mods || only_shift_pressed) {
                /* Use printable characters to initiate search */
                if (((unichar)(Gdk.keyval_to_unicode (event.keyval))).isprint ()) {
                    window.win_actions.activate_action ("find", "CURRENT_DIRECTORY_ONLY");
                    window.key_press_event (event);
                    return true;
                }
            }

            return false;
        }

        protected bool on_motion_notify_event (Gdk.EventMotion event) {
            Gtk.TreePath? path = null;

            if (renaming)
                return true;

            click_zone = get_event_position_info ((Gdk.EventButton)event, out path, false);
            GOF.File? file = path != null ? model.file_for_path (path) : null;

            if (click_zone != previous_click_zone) {
                var win = view.get_window ();
                switch (click_zone) {
                    case ClickZone.NAME:
                        if (single_click_rename && file != null && file.is_writable ())
                            win.set_cursor (editable_cursor);
                        else
                            win.set_cursor (selectable_cursor);

                        break;

                    case ClickZone.BLANK_NO_PATH:
                        win.set_cursor (selectable_cursor);
                        break;

                    case ClickZone.ICON:
                        win.set_cursor (activatable_cursor);
                        break;

                    default:
                        win.set_cursor (selectable_cursor);
                        break;
                }

                previous_click_zone = click_zone;
            }

            if (updates_frozen)
                return false;

            if ((path != null && hover_path == null) ||
                (path == null && hover_path != null) ||
                (path != null && hover_path != null && path.compare (hover_path) != 0)) {

                /* cannot get file info while network disconnected */
                if (slot.directory.is_local || slot.directory.check_network ()) {
                    /* cannot get file info while network disconnected */
                    item_hovered (file);
                    hover_path = path;
                } else {
                    slot.reload (true); /* non-local only */
                }
            }

            return false;
        }

        protected bool on_leave_notify_event (Gdk.EventCrossing event) {
            item_hovered (null); /* Ensure overlay statusbar disappears */
            return false;
        }

        protected bool on_enter_notify_event (Gdk.EventCrossing event) {
            if (slot.is_active)
                grab_focus (); /* Cause OverLay to appear */

            return false;
        }

        protected virtual bool on_scroll_event (Gdk.EventScroll event) {
            if ((event.state & Gdk.ModifierType.CONTROL_MASK) == 0) {
                double increment = 0.0;

                switch (event.direction) {
                    case Gdk.ScrollDirection.LEFT:
                        increment = 5.0;
                        break;

                    case Gdk.ScrollDirection.RIGHT:
                        increment = -5.0;
                        break;

                    case Gdk.ScrollDirection.SMOOTH:
                        double delta_x;
                        event.get_scroll_deltas (out delta_x, null);
                        increment = delta_x * 10.0;
                        break;

                    default:
                        break;
                }
                if (increment != 0.0)
                    slot.horizontal_scroll_event (increment);
            }
            return handle_scroll_event (event);
        }

    /** name renderer signals */
        protected void on_name_editing_started (Gtk.CellEditable? editable, string path) {
            if (renaming)
                return;

            renaming = true;
            freeze_updates ();
            editable_widget = editable as Marlin.AbstractEditableLabel;
            original_name = editable_widget.get_text ().dup ();
        }

        protected void on_name_editing_canceled () {
            if (!renaming)
                return;

            renaming = false;
            name_renderer.editable = false;
            unfreeze_updates ();
            grab_focus ();
        }

        protected void on_name_edited (string path_string, string new_name) {
            if (!renaming)
                return;

            if (new_name != "") {
                var path = new Gtk.TreePath.from_string (path_string);
                Gtk.TreeIter? iter = null;
                model.get_iter (out iter, path);

                GOF.File? file = null;
                model.@get (iter, FM.ListModel.ColumnID.FILE_COLUMN, out file);

                /* Only rename if name actually changed */
                original_name = file.info.get_name ();
                if (new_name != original_name) {
                    proposed_name = new_name;
                    file.rename (new_name, (GOF.FileOperationCallback)rename_callback, (void*)this);
                }
            }

            on_name_editing_canceled ();

            if (new_name != original_name)
                slot.reload (true); /* non-local only */
        }


        public static void rename_callback (GOF.File file, GLib.File? result_location, GLib.Error error, void* data) {
            FM.AbstractDirectoryView? view = null;
            Marlin.View.PropertiesWindow? pw = null;

            var object = (GLib.Object)data;

            if (object is FM.AbstractDirectoryView)
                view = (FM.AbstractDirectoryView)data;
            else if (object is Marlin.View.PropertiesWindow) {
                pw = (Marlin.View.PropertiesWindow)object;
                view = pw.view;
            }

            assert (view != null);

            if (error != null) {
                Eel.show_error_dialog (_("Could not rename to '%s'").printf (view.proposed_name),
                                       error.message,
                                       view.window as Gtk.Window);
            } else {
                Marlin.UndoManager.instance ().add_rename_action (file.location,
                                                                  view.original_name);

                view.select_gof_file (file);  /* Select and scroll to show renamed file */
                view.slot.reload (true);
            }

            if (pw != null) {
                if (error == null)
                    pw.reset_entry_text (file.info.get_name ());
                else
                    pw.reset_entry_text ();  //resets entry to old name
            }
         }

        public virtual bool on_view_draw (Cairo.Context cr) {
            /* If folder is empty, draw the empty message in the middle of the view
             * otherwise pass on event */
            if (slot.directory.is_empty () || slot.directory.permission_denied) {
                Pango.Layout layout = create_pango_layout (null);

                if (slot.directory.is_empty () && slot.directory.location.get_uri_scheme () == "recent")
                    layout.set_markup (slot.empty_recents, -1);
                else if (slot.directory.is_empty ())
                    layout.set_markup (slot.empty_message, -1);
                else if (slot.directory.permission_denied)
                    layout.set_markup (slot.denied_message, -1);

                Pango.Rectangle? extents = null;
                layout.get_extents (null, out extents);

                double width = Pango.units_to_double (extents.width);
                double height = Pango.units_to_double (extents.height);

                double x = (double) get_allocated_width () / 2 - width / 2;
                double y = (double) get_allocated_height () / 2 - height / 2;
                get_style_context ().render_layout (cr, x, y, layout);

                return true;
            }

            return false;
        }

        protected virtual bool handle_primary_button_click (Gdk.EventButton event, Gtk.TreePath? path) {
            bool double_click_event = (event.type == Gdk.EventType.@2BUTTON_PRESS);

            if (!double_click_event)
                start_drag_timer ((Gdk.Event)event);

            return true;
        }

        protected bool handle_secondary_button_click (Gdk.EventButton event) {
            should_scroll = false;
            show_or_queue_context_menu (event);
            return true;
        }

        protected void block_drag_and_drop () {
            drag_data = view.get_data ("gtk-site-data");
            GLib.SignalHandler.block_matched (view, GLib.SignalMatchType.DATA, 0, 0,  null, null, drag_data);
            dnd_disabled = true;
        }

        protected void unblock_drag_and_drop () {
            GLib.SignalHandler.unblock_matched (view, GLib.SignalMatchType.DATA, 0, 0,  null, null, drag_data);
            dnd_disabled = false;
        }

        protected virtual bool on_view_button_press_event (Gdk.EventButton event) {
            grab_focus (); /* cancels any renaming */
            Gtk.TreePath? path = null;

            /* Remember position of click for detecting drag motion*/
            drag_x = (int)(event.x);
            drag_y = (int)(event.y);

            click_zone = get_event_position_info (event, out path, true);
            /* certain positions fake a no path blank zone */
            if (click_zone == ClickZone.BLANK_NO_PATH && path != null) {
                unselect_path (path);
                path = null;
            }
            click_path = path;

            /* Unless single click renaming is enabled, treat name same as blank zone */
            if (!single_click_rename && click_zone == ClickZone.NAME)
                click_zone = ClickZone.BLANK_PATH;


            var mods = event.state & Gtk.accelerator_get_default_mod_mask ();
            bool no_mods = (mods == 0);
            bool control_pressed = ((mods & Gdk.ModifierType.CONTROL_MASK) != 0);
            bool other_mod_pressed = (((mods & ~Gdk.ModifierType.SHIFT_MASK) & ~Gdk.ModifierType.CONTROL_MASK) != 0);
            bool only_control_pressed = control_pressed && !other_mod_pressed; /* Shift can be pressed */

            bool path_selected = (path != null ? path_is_selected (path) : false);
            bool on_blank = (click_zone == ClickZone.BLANK_NO_PATH || click_zone == ClickZone.BLANK_PATH);

            /* Block drag and drop to allow rubberbanding and prevent unwanted effects of
             * dragging on blank areas
             */
            block_drag_and_drop ();

            /* Handle un-modified clicks or control-clicks here else pass on.
             */
            if (!no_mods && !only_control_pressed) {
                return window.button_press_event (event);
            }

            if (!path_selected && click_zone != ClickZone.HELPER) {
                if (no_mods)
                    unselect_all ();

                /* If modifier pressed then default handler determines selection */
                if (no_mods && !on_blank)
                    select_path (path);
            }

            bool result = true;
            should_activate = false;
            should_scroll = true;

            switch (event.button) {
                case Gdk.BUTTON_PRIMARY:
                    /* Control-click should deselect previously selected path on key release (unless
                     * pointer moves)
                     */
                    should_deselect = only_control_pressed && path_selected;

                    switch (click_zone) {
                        case ClickZone.BLANK_NO_PATH:
                            result = false;
                            break;

                        case ClickZone.BLANK_PATH:
                        case ClickZone.ICON:
                            bool double_click_event = (event.type == Gdk.EventType.@2BUTTON_PRESS);
                            /* determine whether should activate on key release (unless pointer moved)*/
                            should_activate =  no_mods &&
                                               (!on_blank || activate_on_blank) &&
                                               (single_click_mode || double_click_event);

                            /* We need to decide whether to rubberband or drag&drop.
                             * Rubberband if modifer pressed or if not on the icon and either
                             * the item is unselected or activate_on_blank is not enabled.
                             */

                            if (!no_mods || (on_blank && (!activate_on_blank || !path_selected)))
                                 result = false; /* Rubberband */
                            else
                                result = handle_primary_button_click (event, path);

                            break;

                        case ClickZone.HELPER:
                            if (path_selected)
                                unselect_path (path);
                            else
                                select_path (path);

                            break;

                        case ClickZone.NAME:
                            rename_file (selected_files.data);
                            break;

                        case ClickZone.EXPANDER:
                            /* on expanders (if any) or xpad. Handle ourselves so that clicking
                             * on xpad also expands/collapses row (accessibility)*/
                            result = expand_collapse (path);
                            break;

                        case ClickZone.INVALID:
                            result = true; /* Prevent rubberbanding */
                            break;

                        default:
                            break;
                    }
                    break;

                case Gdk.BUTTON_MIDDLE:
                    if (path_is_selected (path))
                        activate_selected_items (Marlin.OpenFlag.NEW_TAB);

                    break;

                case Gdk.BUTTON_SECONDARY:
                    if (click_zone == ClickZone.NAME ||
                        (!single_click_rename && click_zone == ClickZone.BLANK_PATH))

                        select_path (path);

                    result = handle_secondary_button_click (event);
                    break;

                default:
                    result = handle_default_button_click (event);
                    break;
            }

            return result;
        }

        protected virtual bool on_view_button_release_event (Gdk.EventButton event) {
            if (dnd_disabled)
                unblock_drag_and_drop ();

            /* Ignore button release from click that started renaming.
             * View may lose focus during a drag if another tab is hovered, in which case
             * we do not want to refocus this view.
             * Under both these circumstances, 'should_activate' will be false */
            if (renaming || !view_has_focus ())
                return true;

            slot.active (should_scroll);

            Gtk.Widget widget = get_real_view ();
            int x = (int)event.x;
            int y = (int)event.y;
            /* Only take action if pointer has not moved */
            if (!Gtk.drag_check_threshold (widget, drag_x, drag_y, x, y)) {
                if (should_activate)
                    activate_selected_items (Marlin.OpenFlag.DEFAULT);
                else if (should_deselect && click_path != null)
                    unselect_path (click_path);
            }
            should_activate = false;
            should_deselect = false;
            click_path = null;
            return false;
        }

        public virtual void change_zoom_level () {
            icon_renderer.set_property ("zoom-level", zoom_level);
            icon_renderer.set_property ("size", icon_size);
            helpers_shown = single_click_mode && (zoom_level >= Marlin.ZoomLevel.SMALL);
            icon_renderer.set_property ("selection-helpers", helpers_shown);
        }

        private void start_renaming_file (GOF.File file, bool preselect_whole_name) {
            /* Select whole name if we are in renaming mode already */
            if (renaming)
                return;

            Gtk.TreeIter? iter = null;
            if (!model.get_first_iter_for_file (file, out iter)) {
                critical ("Failed to find rename file in model");
                return;
            }

            /* Freeze updates to the view to prevent losing rename focus when the tree view updates */
            freeze_updates ();

            Gtk.TreePath path = model.get_path (iter);

            /* Scroll to row to be renamed and then start renaming after a delay
             * so that file to be renamed is on screen.  This avoids the renaming being
             * cancelled */
            set_cursor (path, false, true, false);
            uint count = 0;
            Gtk.TreePath? start_path = null;
            bool ok_next_time   = false;

            GLib.Timeout.add (50, () => {
                /* Wait until view stops scrolling before starting to rename (up to 1 second)
                 * Scrolling is deemed to have stopped when the starting visible path is stable
                 * over two cycles */
                Gtk.TreePath? start = null;
                Gtk.TreePath? end = null;
                get_visible_range (out start, out end);
                count++;

                if (start_path == null || (count < 20 && start.compare (start_path) != 0)) {
                    start_path = start;
                    ok_next_time = false;
                    return true;
                } else if (!ok_next_time) {
                    ok_next_time = true;
                    return true;
                }

                /* set cursor_on_cell also triggers editing-started, where we save the editable widget */
                name_renderer.editable = true;
                set_cursor_on_cell (path, name_renderer as Gtk.CellRenderer, true, false);

                if (editable_widget != null) {
                    int start_offset= 0, end_offset = -1;
                    if (!file.is_folder ())
                        Marlin.get_rename_region (original_name, out start_offset, out end_offset, preselect_whole_name);

                    editable_widget.select_region (start_offset, end_offset);
                } else {
                    warning ("Editable widget is null");
                    on_name_editing_canceled ();
                }
                return false;
            });

        }

        protected string get_string_from_column_id (int id) {
            switch (id) {
                case FM.ListModel.ColumnID.FILENAME:
                    return "name";

                case FM.ListModel.ColumnID.SIZE:
                    return "size";

                case FM.ListModel.ColumnID.TYPE:
                    return "type";

                case FM.ListModel.ColumnID.MODIFIED:
                    return "modified";

                default:
                    warning ("column id not recognised - using 'name'");
                    return "name";
            }
        }

        protected int get_column_id_from_string (string col_name) {
            switch (col_name) {
                case "name":
                    return FM.ListModel.ColumnID.FILENAME;

                case "size":
                    return FM.ListModel.ColumnID.SIZE;

                case "type":
                    return FM.ListModel.ColumnID.TYPE;

                case "modified":
                    return FM.ListModel.ColumnID.MODIFIED;

                default:
                    warning ("column name not recognised - using FILENAME");

                return FM.ListModel.ColumnID.FILENAME;
            }
        }

        protected void on_sort_column_changed () {
            int sort_column_id;
            Gtk.SortType sort_order;

            if (!model.get_sort_column_id (out sort_column_id, out sort_order))
                return;

            var info = new GLib.FileInfo ();
            info.set_attribute_string ("metadata::marlin-sort-column-id",
                                       get_string_from_column_id (sort_column_id));
            info.set_attribute_string ("metadata::marlin-sort-reversed",
                                       (sort_order == Gtk.SortType.DESCENDING ? "true" : "false"));

            var dir = slot.directory;
            dir.file.sort_column_id = sort_column_id;
            dir.file.sort_order = sort_order;

            dir.location.set_attributes_async.begin (info,
                                               GLib.FileQueryInfoFlags.NONE,
                                               GLib.Priority.DEFAULT,
                                               null,
                                               (obj, res) => {
                try {
                    GLib.FileInfo inf;
                    dir.location.set_attributes_async.end (res, out inf);
                } catch (GLib.Error e) {
                    warning ("Could not set file attributes - %s", e.message);
                }
            });
        }

        protected void cancel_timeout (ref uint id) {
            if (id > 0) {
                GLib.Source.remove (id);
                id = 0;
            }
        }

        protected virtual bool expand_collapse (Gtk.TreePath? path) {
            return true;
        }

        protected virtual bool handle_default_button_click (Gdk.EventButton event) {
            /* pass unhandled events to the Marlin.View.Window */
            return window.button_press_event (event);
        }

        protected virtual bool get_next_visible_iter (ref Gtk.TreeIter iter, bool recurse = true) {
            return model.iter_next (ref iter);
        }

        public virtual void cancel () {
            cancel_thumbnailing ();
            cancel_drag_timer ();
            cancel_timeout (ref drag_scroll_timer_id);
            loaded_subdirectories.@foreach ((dir) => {
                remove_subdirectory (dir);
            });
        }

        protected bool is_on_icon (int x, int y, int orig_x, int orig_y, ref bool on_helper) {
            bool on_icon =  (x >= orig_x &&
                             x <= orig_x + icon_size &&
                             y >= orig_y &&
                             y <= orig_y + icon_size);

            if (!on_icon || !helpers_shown)
                on_helper = false;
            else {
                var helper_size = icon_renderer.get_helper_size () + 2;
                on_helper = (x - orig_x <= helper_size &&
                             y - orig_y <= helper_size);
            }

            return on_icon;
        }

        protected void invert_selection () {
            GLib.List<Gtk.TreeRowReference> selected_row_refs = null;

            foreach (Gtk.TreePath p in get_selected_paths ())
                selected_row_refs.prepend (new Gtk.TreeRowReference (model, p));

            select_all ();

            foreach (Gtk.TreeRowReference r in selected_row_refs) {
                var p = r.get_path ();
                if (p != null)
                    unselect_path (p);
            }
        }

        public virtual void sync_selection () {}
        public virtual void highlight_path (Gtk.TreePath? path) {}
        protected virtual void add_subdirectory (GOF.Directory.Async dir) {}
        protected virtual void remove_subdirectory (GOF.Directory.Async dir) {}

/** Abstract methods - must be overridden*/
        public abstract GLib.List<Gtk.TreePath> get_selected_paths () ;
        public abstract Gtk.TreePath? get_path_at_pos (int x, int y);
        public abstract Gtk.TreePath? get_path_at_cursor ();
        public abstract void select_all ();
        public abstract void unselect_all ();
        public abstract void select_path (Gtk.TreePath? path);
        public abstract void unselect_path (Gtk.TreePath? path);
        public abstract bool path_is_selected (Gtk.TreePath? path);
        public abstract bool get_visible_range (out Gtk.TreePath? start_path, out Gtk.TreePath? end_path);
        public abstract void set_cursor (Gtk.TreePath? path,
                                         bool start_editing,
                                         bool select,
                                         bool scroll_to_top);
        protected abstract Gtk.Widget? create_view ();
        protected abstract Marlin.ZoomLevel get_set_up_zoom_level ();
        protected abstract Marlin.ZoomLevel get_normal_zoom_level ();
        protected abstract bool view_has_focus ();
        protected abstract void update_selected_files ();
        protected abstract uint get_event_position_info (Gdk.EventButton event,
                                                         out Gtk.TreePath? path,
                                                         bool rubberband = false);
        protected abstract void scroll_to_cell (Gtk.TreePath? path,
                                                bool scroll_to_top);
        protected abstract void set_cursor_on_cell (Gtk.TreePath path,
                                                    Gtk.CellRenderer renderer,
                                                    bool start_editing,
                                                    bool scroll_to_top);
        protected abstract void freeze_tree ();
        protected abstract void thaw_tree ();

/** Unimplemented methods
 *  fm_directory_view_parent_set ()  - purpose unclear
*/
    }
}

