using Gtk;
using GLib;
using Singularity;
using Singularity.Widgets;

namespace Singularity.Apps {

    public class FileBrowserPane : Box {
        private Label    dir_lbl;
        private ListBox  list_box;
        public GLib.File current_dir;
        private EditWindow owner;

        public FileBrowserPane (EditWindow win) {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            owner = win;

            // Current-directory chip sits at the top of the sidebar.
            // No "FILES" section label: the sidebar is already a file
            // browser; a header would just be noise.
            var header = new Box (Orientation.VERTICAL, 0);
            header.margin_start  = 12;
            header.margin_end    = 12;
            header.margin_bottom = 4;

            dir_lbl = new Label ("~");
            dir_lbl.ellipsize  = Pango.EllipsizeMode.START;
            dir_lbl.xalign     = 0;
            dir_lbl.add_css_class ("dim-label");
            dir_lbl.add_css_class ("caption");
            header.append (dir_lbl);

            append (header);

            var scroll = new ScrolledWindow ();
            scroll.vexpand           = true;
            scroll.hscrollbar_policy = PolicyType.NEVER;

            list_box = new ListBox ();
            list_box.selection_mode = SelectionMode.SINGLE;
            list_box.add_css_class ("navigation-sidebar");
            scroll.set_child (list_box);
            append (scroll);

            list_box.row_activated.connect (on_row_activated);

            navigate_to (GLib.File.new_for_path (Environment.get_home_dir ()));
        }

        public void navigate_to (GLib.File dir) {
            current_dir = dir;
            string path = dir.get_path () ?? dir.get_uri ();
            string home = Environment.get_home_dir ();
            if (path.has_prefix (home))
                path = "~" + path.substring (home.length);
            dir_lbl.label = path;
            populate ();
        }

        public void navigate_to_file_dir (GLib.File file) {
            var parent = file.get_parent ();
            if (parent != null) navigate_to (parent);
        }

        private void populate () {
            while (list_box.get_row_at_index (0) != null)
                list_box.remove (list_box.get_row_at_index (0));

            if (current_dir.get_parent () != null)
                append_row (null, "..", true);

            try {
                var en = current_dir.enumerate_children (
                    "standard::name,standard::type",
                    GLib.FileQueryInfoFlags.NONE);

                GLib.List<GLib.FileInfo> dirs  = new GLib.List<GLib.FileInfo> ();
                GLib.List<GLib.FileInfo> files = new GLib.List<GLib.FileInfo> ();

                GLib.FileInfo? fi;
                while ((fi = en.next_file ()) != null) {
                    if (fi.get_name ().has_prefix (".")) continue;
                    if (fi.get_file_type () == GLib.FileType.DIRECTORY)
                        dirs.append (fi);
                    else
                        files.append (fi);
                }
                dirs.sort  ((a, b) => strcmp (a.get_name (), b.get_name ()));
                files.sort ((a, b) => strcmp (a.get_name (), b.get_name ()));

                foreach (var d in dirs)
                    append_row (current_dir.get_child (d.get_name ()), d.get_name (), true);
                foreach (var f in files)
                    append_row (current_dir.get_child (f.get_name ()), f.get_name (), false);
            } catch (Error e) {
                warning ("File browser: %s", e.message);
            }
        }

        private void append_row (GLib.File? file, string name, bool is_dir) {
            var row  = new ListBoxRow ();
            var hbox = new Box (Orientation.HORIZONTAL, 6);
            hbox.margin_start  = 6;
            hbox.margin_end    = 6;
            hbox.margin_top    = 3;
            hbox.margin_bottom = 3;

            var img = new Image.from_icon_name (
                is_dir ? "folder-symbolic" : "text-x-generic-symbolic");
            img.icon_size = IconSize.NORMAL;
            hbox.append (img);

            var lbl = new Label (null);
            lbl.xalign     = 0;
            lbl.ellipsize  = Pango.EllipsizeMode.END;
            lbl.hexpand    = true;
            if (is_dir) {
                lbl.label = "<b>%s</b>".printf (GLib.Markup.escape_text (name));
                lbl.use_markup = true;
            } else {
                lbl.label = name;
            }
            hbox.append (lbl);
            row.set_child (hbox);

            if (file != null)
                row.set_data<GLib.File> ("file", file);
            row.set_data<bool> ("is-dir", is_dir);
            list_box.append (row);
        }

        private void on_row_activated (ListBoxRow row) {
            bool is_dir      = row.get_data<bool> ("is-dir");
            GLib.File? file  = row.get_data<GLib.File> ("file");

            if (file == null) {
                var parent = current_dir.get_parent ();
                if (parent != null) navigate_to (parent);
                return;
            }
            if (is_dir)
                navigate_to (file);
            else
                owner.open_file (file);
        }
    }

}
