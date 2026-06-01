using GLib;
using Gtk;

namespace Singularity.Apps {

    public enum OutlineKind {
        FUNCTION, METHOD, CLASS, STRUCT, INTERFACE, ENUM, MODULE, CONSTANT, MACRO, VARIABLE, OTHER;

        public string icon_name () {
            switch (this) {
                case FUNCTION:  return "applications-utilities-symbolic";
                case METHOD:    return "applications-utilities-symbolic";
                case CLASS:     return "view-grid-symbolic";
                case STRUCT:    return "view-grid-symbolic";
                case INTERFACE: return "view-grid-symbolic";
                case ENUM:      return "view-list-symbolic";
                case MODULE:    return "system-file-manager-symbolic";
                case CONSTANT:  return "preferences-system-symbolic";
                case MACRO:     return "preferences-system-symbolic";
                case VARIABLE:  return "preferences-system-symbolic";
                default:        return "view-list-symbolic";
            }
        }
    }

    public class OutlineEntry {
        public OutlineKind kind;
        public string      name;
        public int         line;    // 0-based
        public uint32      start_byte;

        public OutlineEntry (OutlineKind kind, string name, int line, uint32 start_byte) {
            this.kind = kind;
            this.name = name;
            this.line = line;
            this.start_byte = start_byte;
        }
    }

    /**
     * Runs the tags.scm query against a parsed tree-sitter tree and
     * returns a flat outline of definitions. Pairing follows the
     * convention used by tree-sitter's tags.scm: each match emits one
     * @name capture (identifier) and one @definition.<kind> capture
     * (the enclosing node).
     */
    public class TsOutline {
        public static OutlineEntry[] extract (TsLanguageDef def, unowned TS.Tree tree, string buffer_text) {
            var result = new GenericArray<OutlineEntry> ();
            unowned TS.Query? tags_q = get_or_load_tags_query (def);
            if (tags_q == null) return {};

            var qc = new TS.QueryCursor ();
            qc.exec (tags_q, tree.root_node ());

            TS.QueryMatch match;
            while (qc.next_match (out match)) {
                string?     name_text = null;
                int         line      = -1;
                uint32      start_b   = 0;
                OutlineKind kind      = OutlineKind.OTHER;
                bool        has_def   = false;

                for (uint16 i = 0; i < match.capture_count; i++) {
                    unowned TS.QueryCapture cap = match.captures[i];
                    uint32 nlen = 0;
                    unowned string cname = tags_q.capture_name_for_id (cap.index, out nlen);
                    if (cname == null) continue;

                    if (cname == "name") {
                        uint32 sb = cap.node.start_byte ();
                        uint32 eb = cap.node.end_byte ();
                        if (sb < eb && (int) eb <= buffer_text.length) {
                            name_text = ((string)((char*) buffer_text.data + sb)).substring (
                                0, (long) (eb - sb));
                        }
                    } else if (cname.has_prefix ("definition.")) {
                        has_def = true;
                        var k = cname.substring ("definition.".length);
                        kind = kind_from_string (k);
                        line = (int) cap.node.start_point ().row;
                        start_b = cap.node.start_byte ();
                    } else if (cname.has_prefix ("reference.")) {
                        // skip references; outline only shows definitions
                    }
                }

                if (has_def && name_text != null) {
                    result.add (new OutlineEntry (kind, name_text, line, start_b));
                }
            }

            // Stable sort by line.
            result.sort ((a, b) => a.line - b.line);
            return result.steal ();
        }

        private static OutlineKind kind_from_string (string s) {
            switch (s) {
                case "function":  return OutlineKind.FUNCTION;
                case "method":    return OutlineKind.METHOD;
                case "class":     return OutlineKind.CLASS;
                case "struct":    return OutlineKind.STRUCT;
                case "interface": return OutlineKind.INTERFACE;
                case "enum":      return OutlineKind.ENUM;
                case "module":    return OutlineKind.MODULE;
                case "constant":  return OutlineKind.CONSTANT;
                case "macro":     return OutlineKind.MACRO;
                case "variable":  return OutlineKind.VARIABLE;
                case "type":      return OutlineKind.STRUCT;
                default:          return OutlineKind.OTHER;
            }
        }

        // tags.scm lives next to highlights.scm in our data dir; load lazily.
        private static unowned TS.Query? get_or_load_tags_query (TsLanguageDef def) {
            if (_tags_cache == null) {
                _tags_cache = new HashTable<string, TS.Query> (str_hash, str_equal);
            }
            unowned TS.Query? q = _tags_cache.lookup (def.name);
            if (q != null) return q;

            string[] roots = {};
            roots += Path.build_filename (Environment.get_user_data_dir (),
                                          "singularity-edit", "queries");
            foreach (var d in Environment.get_system_data_dirs ()) {
                roots += Path.build_filename (d, "singularity-edit", "queries");
            }
            roots += "/usr/share/singularity-edit/queries";
            roots += "/usr/local/share/singularity-edit/queries";

            foreach (var root in roots) {
                var p = Path.build_filename (root, def.name, "tags.scm");
                if (!FileUtils.test (p, FileTest.EXISTS)) continue;
                string contents;
                try { FileUtils.get_contents (p, out contents); }
                catch (Error e) { warning ("ts: tags %s: %s", p, e.message); return null; }

                uint32 err_off = 0;
                TS.QueryError err_type = TS.QueryError.None;
                var built = new TS.Query (def.language,
                    (uint8[]) contents.data, (uint32) contents.length,
                    out err_off, out err_type);
                if (err_type != TS.QueryError.None) {
                    warning ("ts: tags %s rejected at byte %u (err %d)",
                             p, err_off, (int) err_type);
                    return null;
                }
                _tags_cache.insert (def.name, (owned) built);
                return _tags_cache.lookup (def.name);
            }
            return null;
        }

        private static HashTable<string, TS.Query>? _tags_cache = null;
    }

    //
    // OutlinePanel: bottom dock panel (VS Code-style). Sits at the bottom of
    // the EditWindow above the StatusBar, wrapped in a Revealer for slide-up.
    //
    public class OutlinePanel : Box {
        public signal void entry_activated (OutlineEntry entry);
        public signal void close_requested ();

        private ListBox list;
        private Label   empty_label;
        private Stack   stack;
        private Label   header_lbl;

        public OutlinePanel () {
            Object (orientation: Orientation.VERTICAL, spacing: 0);
            add_css_class ("edit-outline-panel");
            // Note: NO height_request on the panel itself, since that would leak
            // through Gtk.Revealer's measurement when collapsed on some GTK
            // builds. The minimum is set on the inner Stack instead.

            // Header bar: title + close button.
            var header = new Box (Orientation.HORIZONTAL, 6);
            header.margin_top = 4;
            header.margin_bottom = 4;
            header.margin_start = 12;
            header.margin_end   = 6;
            header.add_css_class ("edit-outline-header");

            header_lbl = new Label (_("<small><b>OUTLINE</b></small>"));
            header_lbl.use_markup = true;
            header_lbl.xalign = 0;
            header_lbl.hexpand = true;
            header_lbl.add_css_class ("dim-label");
            header.append (header_lbl);

            var close_btn = new Gtk.Button.from_icon_name ("window-close-symbolic");
            close_btn.add_css_class ("flat");
            close_btn.tooltip_text = _("Close panel");
            close_btn.clicked.connect (() => close_requested ());
            header.append (close_btn);

            append (header);

            stack = new Stack ();
            stack.transition_type = StackTransitionType.CROSSFADE;
            stack.transition_duration = 120;
            stack.hexpand = true;
            stack.vexpand = true;
            stack.height_request = 180;

            empty_label = new Label (_("No symbols in this file"));
            empty_label.add_css_class ("dim-label");
            empty_label.valign = Align.CENTER;
            empty_label.halign = Align.CENTER;
            stack.add_named (empty_label, "empty");

            list = new ListBox ();
            list.selection_mode = SelectionMode.SINGLE;
            list.add_css_class ("navigation-sidebar");
            list.row_activated.connect (on_row_activated);

            var scroll = new ScrolledWindow ();
            scroll.set_child (list);
            scroll.hexpand = true;
            scroll.vexpand = true;
            stack.add_named (scroll, "list");

            append (stack);
            stack.visible_child_name = "empty";
        }

        public void set_title_suffix (string? suffix) {
            if (suffix == null || suffix == "")
                header_lbl.label = _("<small><b>OUTLINE</b></small>");
            else
                header_lbl.label = _("<small><b>OUTLINE</b> · %s</small>").printf (
                    Markup.escape_text (suffix));
        }

        public void set_entries (OutlineEntry[] entries) {
            // Clear list
            Gtk.ListBoxRow? row = list.get_first_child () as ListBoxRow;
            while (row != null) {
                var next = row.get_next_sibling () as ListBoxRow;
                list.remove (row);
                row = next;
            }

            if (entries.length == 0) {
                stack.visible_child_name = "empty";
                return;
            }

            foreach (var e in entries) {
                var row_box = new Box (Orientation.HORIZONTAL, 8);
                row_box.margin_start = 12;
                row_box.margin_end   = 12;
                row_box.margin_top   = 3;
                row_box.margin_bottom = 3;

                var icon = new Image.from_icon_name (e.kind.icon_name ());
                icon.pixel_size = 14;
                row_box.append (icon);

                var name_lbl = new Label (e.name);
                name_lbl.xalign = 0;
                name_lbl.ellipsize = Pango.EllipsizeMode.END;
                name_lbl.hexpand = true;
                row_box.append (name_lbl);

                var line_lbl = new Label (_("L%d").printf (e.line + 1));
                line_lbl.add_css_class ("dim-label");
                line_lbl.add_css_class ("caption");
                row_box.append (line_lbl);

                var lr = new ListBoxRow ();
                lr.set_child (row_box);
                lr.set_data<OutlineEntry> ("entry", e);
                list.append (lr);
            }
            stack.visible_child_name = "list";
        }

        private void on_row_activated (ListBoxRow row) {
            var e = row.get_data<OutlineEntry> ("entry");
            if (e != null) entry_activated (e);
        }
    }
}
